defmodule Sensocto.AttributeStoreTiered do
  @moduledoc """
  ETS-based tiered storage for sensor attribute data.

  ## Storage Tiers (all in-memory via ETS)

  1. **Hot tier** (ETS): Last @hot_limit entries per attribute
     - Fastest access, used for real-time display
     - Direct ETS reads/writes, no process bottleneck

  2. **Warm tier** (ETS): Next @warm_limit entries per attribute
     - Fast concurrent reads
     - Automatically managed with overflow from hot tier

  ## Concurrency

  All write operations go directly to ETS without any process involvement.
  This eliminates Agent mailbox backlog under high load.

  ## Memory Budget

  With default limits (500 hot + 10,000 warm = 10,500 per attribute):
  - 1000 sensors × 5 attributes × 10,500 entries × 200 bytes ≈ 10 GB

  Adjust @hot_limit and @warm_limit based on available memory.

  ## Usage

  Drop-in replacement for Sensocto.AttributeStore with same public API.
  """
  require Logger

  # Tier limits - all in-memory (configurable via application env)
  # These are the "relaxed" limits used when system is idle (~10min at 100Hz)
  @default_hot_limit 1_000
  @default_warm_limit 60_000
  @default_query_limit 500

  # Adaptive limit multipliers based on system load
  # Retention targets at 100Hz: normal=~10min, elevated=~5min, high=~2min, critical=~30sec
  @adaptive_limits %{
    normal: %{hot_mult: 1.0, warm_mult: 1.0},
    elevated: %{hot_mult: 0.8, warm_mult: 0.5},
    high: %{hot_mult: 0.4, warm_mult: 0.2},
    critical: %{hot_mult: 0.2, warm_mult: 0.05}
  }

  # Type-specific limits for large payload types that only need recent data
  @realtime_only_types [
    "skeleton",
    "pose",
    "body_pose",
    "pose_skeleton",
    "video_frame",
    "depth_map"
  ]
  @realtime_hot_limit 1
  @realtime_warm_limit 0

  # ETS tables
  @hot_table :attribute_store_hot
  @warm_table :attribute_store_warm
  @sensors_table :attribute_store_sensors

  # Get current load level from SystemLoadMonitor (fast ETS read)
  defp get_load_level do
    case :ets.whereis(:system_load_cache) do
      :undefined ->
        :normal

      _tid ->
        case :ets.lookup(:system_load_cache, :load_level) do
          [{_, level}] -> level
          [] -> :normal
        end
    end
  end

  # Get adaptive multiplier for current load level
  defp adaptive_multiplier do
    Map.get(@adaptive_limits, get_load_level(), @adaptive_limits.normal)
  end

  # Base limits from config
  defp base_hot_limit,
    do: Application.get_env(:sensocto, :attribute_store_hot_limit, @default_hot_limit)

  defp base_warm_limit,
    do: Application.get_env(:sensocto, :attribute_store_warm_limit, @default_warm_limit)

  # Effective limits after applying adaptive multiplier
  defp hot_limit do
    mult = adaptive_multiplier()
    max(round(base_hot_limit() * mult.hot_mult), 10)
  end

  defp warm_limit do
    mult = adaptive_multiplier()
    max(round(base_warm_limit() * mult.warm_mult), 100)
  end

  defp hot_limit_for_type(attribute_type) when attribute_type in @realtime_only_types,
    do: @realtime_hot_limit

  defp hot_limit_for_type(_), do: hot_limit()

  defp warm_limit_for_type(attribute_type) when attribute_type in @realtime_only_types,
    do: @realtime_warm_limit

  defp warm_limit_for_type(_), do: warm_limit()

  @doc """
  Starts a SensorStub process for supervisor compatibility.
  The actual data storage uses ETS directly.
  """
  defdelegate start_link(config), to: Sensocto.AttributeStoreTiered.SensorStub

  @doc """
  Ensures the global warm storage ETS table exists.
  Kept for backwards compatibility - tables are now created by TableOwner.
  """
  def ensure_warm_table do
    Sensocto.AttributeStoreTiered.TableOwner.ensure_tables()
  end

  @doc """
  Store a new measurement for an attribute.
  Non-blocking direct ETS write - no process mailbox involved.

  Performance optimization: We track the count alongside payloads and only run
  the expensive Enum.split when the list exceeds 2x the hot_limit. This reduces
  split frequency from every write to ~once per hot_limit writes (~1000x improvement).
  """
  def put_attribute(sensor_id, attribute_id, timestamp, payload) do
    key = {sensor_id, attribute_id}
    new_entry = %{payload: payload, timestamp: timestamp}
    attr_type = infer_attribute_type(attribute_id)
    type_hot_limit = hot_limit_for_type(attr_type)
    type_warm_limit = warm_limit_for_type(attr_type)

    # Get current hot data with count (new format includes count)
    {current_payloads, current_count} =
      case :ets.lookup(@hot_table, key) do
        # New format with count
        [{^key, {payloads, _type, count, _updated}}] when is_integer(count) ->
          {payloads, count}

        # Legacy format without count - migrate on read
        [{^key, {payloads, _type, _updated}}] ->
          {payloads, length(payloads)}

        [] ->
          {[], 0}
      end

    # Prepend new entry
    new_payloads = [new_entry | current_payloads]
    new_count = current_count + 1

    # Only split when we exceed 2x the limit (amortizes the O(n) split cost)
    {hot_payloads, overflow, final_count} =
      if new_count > type_hot_limit * 2 do
        {hp, of} = Enum.split(new_payloads, type_hot_limit)
        {hp, of, type_hot_limit}
      else
        {new_payloads, [], new_count}
      end

    # Store in hot tier with count
    :ets.insert(
      @hot_table,
      {key, {hot_payloads, attr_type, final_count, System.monotonic_time(:millisecond)}}
    )

    # Push overflow to warm tier if applicable
    if overflow != [] and type_warm_limit > 0 do
      push_to_warm_tier(sensor_id, attribute_id, overflow, type_warm_limit)
    end

    :ok
  end

  @doc """
  Get all attributes with their recent measurements.
  Returns only hot tier data by default for performance.
  """
  def get_attributes(sensor_id, limit \\ @default_query_limit) do
    # Match all keys for this sensor in hot tier (handles both old 3-tuple and new 4-tuple format)
    match_spec_new = [{{{sensor_id, :"$1"}, {:"$2", :_, :_, :_}}, [], [{{:"$1", :"$2"}}]}]
    match_spec_old = [{{{sensor_id, :"$1"}, {:"$2", :_, :_}}, [], [{{:"$1", :"$2"}}]}]

    case :ets.whereis(@hot_table) do
      :undefined ->
        %{}

      _tid ->
        # Try new format first, fall back to old format
        results = :ets.select(@hot_table, match_spec_new)

        results =
          if results == [] do
            :ets.select(@hot_table, match_spec_old)
          else
            results
          end

        results
        |> Enum.reduce(%{}, fn {attr_id, payloads}, acc ->
          Map.put(acc, attr_id, Enum.take(payloads, limit))
        end)
    end
  end

  @doc """
  Get data for a specific attribute with optional time filtering.
  Can include warm tier data when needed.
  """
  def get_attribute(
        sensor_id,
        attribute_id,
        from_timestamp,
        to_timestamp \\ :infinity,
        limit \\ @default_query_limit
      ) do
    hot_data = get_hot_data(sensor_id, attribute_id)
    warm_data = get_warm_data(sensor_id, attribute_id)

    all_data =
      (hot_data ++ warm_data)
      |> Enum.sort_by(& &1.timestamp)

    filtered =
      all_data
      |> maybe_filter_time(from_timestamp, to_timestamp)
      |> maybe_take(limit)

    {:ok, filtered}
  end

  @doc """
  Get attribute data including warm tier.
  Use this when you need more historical data than hot tier provides.
  """
  def get_attribute_extended(sensor_id, attribute_id, limit \\ @default_warm_limit) do
    hot_data = get_hot_data(sensor_id, attribute_id)
    warm_data = get_warm_data(sensor_id, attribute_id)

    (hot_data ++ warm_data)
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.take(limit)
  end

  @doc """
  Remove an attribute and its data from all tiers.
  """
  def remove_attribute(sensor_id, attribute_id) do
    key = {sensor_id, attribute_id}

    # Remove from hot tier
    if :ets.whereis(@hot_table) != :undefined do
      :ets.delete(@hot_table, key)
    end

    # Remove from warm tier
    if :ets.whereis(@warm_table) != :undefined do
      :ets.delete(@warm_table, key)
    end

    :ok
  end

  @doc """
  Get memory stats for this sensor's attribute store.
  """
  def stats(sensor_id) do
    hot_count =
      if :ets.whereis(@hot_table) != :undefined do
        # New format returns count directly, old format needs length
        match_spec_new = [
          {{{sensor_id, :_}, {:_, :_, :"$1", :_}}, [{:is_integer, :"$1"}], [:"$1"]}
        ]

        match_spec_old = [{{{sensor_id, :_}, {:"$1", :_, :_}}, [], [:"$1"]}]

        new_counts = :ets.select(@hot_table, match_spec_new)

        if new_counts != [] do
          Enum.sum(new_counts)
        else
          :ets.select(@hot_table, match_spec_old)
          |> Enum.map(&length/1)
          |> Enum.sum()
        end
      else
        0
      end

    warm_count =
      if :ets.whereis(@warm_table) != :undefined do
        match_spec = [{{{sensor_id, :_}, :"$1"}, [], [:"$1"]}]

        :ets.select(@warm_table, match_spec)
        |> Enum.map(&length/1)
        |> Enum.sum()
      else
        0
      end

    attr_count =
      if :ets.whereis(@hot_table) != :undefined do
        :ets.select_count(@hot_table, [
          {{{sensor_id, :_}, :_}, [], [true]}
        ])
      else
        0
      end

    %{
      sensor_id: sensor_id,
      hot_entries: hot_count,
      warm_entries: warm_count,
      attributes: attr_count
    }
  end

  @doc """
  Cleanup resources when sensor is terminated.
  Removes all data for this sensor from all tiers.
  """
  def cleanup(sensor_id) do
    # Remove from sensors tracking table
    if :ets.whereis(@sensors_table) != :undefined do
      :ets.delete(@sensors_table, sensor_id)
    end

    # Delete all hot tier entries for this sensor
    if :ets.whereis(@hot_table) != :undefined do
      :ets.match_delete(@hot_table, {{sensor_id, :_}, :_})
    end

    # Delete all warm tier entries for this sensor
    if :ets.whereis(@warm_table) != :undefined do
      :ets.match_delete(@warm_table, {{sensor_id, :_}, :_})
    end

    :ok
  end

  @doc """
  Clear all stored data (useful when all sensors are stopped).
  """
  def clear_all do
    if :ets.whereis(@sensors_table) != :undefined do
      :ets.delete_all_objects(@sensors_table)
    end

    if :ets.whereis(@hot_table) != :undefined do
      :ets.delete_all_objects(@hot_table)
    end

    if :ets.whereis(@warm_table) != :undefined do
      :ets.delete_all_objects(@warm_table)
    end

    :ok
  end

  @doc """
  Get current adaptive limits based on system load.
  Returns the effective limits being applied right now.
  """
  def current_limits do
    load_level = get_load_level()
    mult = adaptive_multiplier()

    %{
      load_level: load_level,
      hot_limit: hot_limit(),
      warm_limit: warm_limit(),
      base_hot_limit: base_hot_limit(),
      base_warm_limit: base_warm_limit(),
      hot_multiplier: mult.hot_mult,
      warm_multiplier: mult.warm_mult,
      retention_at_100hz: %{
        hot_seconds: hot_limit() / 100,
        warm_seconds: warm_limit() / 100,
        total_seconds: (hot_limit() + warm_limit()) / 100
      }
    }
  end

  ## Private functions

  defp infer_attribute_type(attribute_id) do
    cond do
      attribute_id in @realtime_only_types -> attribute_id
      String.contains?(to_string(attribute_id), "skeleton") -> "skeleton"
      String.contains?(to_string(attribute_id), "pose") -> "pose"
      String.contains?(to_string(attribute_id), "depth") -> "depth_map"
      true -> "default"
    end
  end

  defp push_to_warm_tier(sensor_id, attribute_id, entries, type_warm_limit) do
    if :ets.whereis(@warm_table) != :undefined do
      key = {sensor_id, attribute_id}

      existing =
        case :ets.lookup(@warm_table, key) do
          [{^key, data}] -> data
          [] -> []
        end

      new_warm = Enum.take(entries ++ existing, type_warm_limit)
      :ets.insert(@warm_table, {key, new_warm})
    end
  end

  defp get_hot_data(sensor_id, attribute_id) do
    if :ets.whereis(@hot_table) != :undefined do
      key = {sensor_id, attribute_id}

      case :ets.lookup(@hot_table, key) do
        # New format with count
        [{^key, {payloads, _type, _count, _updated}}] -> payloads
        # Legacy format without count
        [{^key, {payloads, _type, _updated}}] -> payloads
        [] -> []
      end
    else
      []
    end
  end

  defp get_warm_data(sensor_id, attribute_id) do
    if :ets.whereis(@warm_table) != :undefined do
      key = {sensor_id, attribute_id}

      case :ets.lookup(@warm_table, key) do
        [{^key, data}] -> data
        [] -> []
      end
    else
      []
    end
  end

  defp maybe_filter_time(payloads, nil, _to), do: payloads
  defp maybe_filter_time(payloads, _from, nil), do: payloads

  defp maybe_filter_time(payloads, from_timestamp, :infinity) do
    Enum.filter(payloads, fn %{timestamp: ts} -> ts >= from_timestamp end)
  end

  defp maybe_filter_time(payloads, from_timestamp, to_timestamp) do
    Enum.filter(payloads, fn %{timestamp: ts} ->
      ts >= from_timestamp && ts <= to_timestamp
    end)
  end

  defp maybe_take(payloads, nil), do: payloads
  defp maybe_take(payloads, :infinity), do: payloads

  defp maybe_take(payloads, limit) when is_integer(limit) and limit > 0,
    do: Enum.take(payloads, -limit)

  defp maybe_take(payloads, _), do: payloads
end
