defmodule Sensocto.AttributeStoreTiered do
  @moduledoc """
  Tiered in-memory storage for sensor attribute data.

  ## Storage Tiers (all in-memory)

  1. **Hot tier** (process memory): Last @hot_limit entries per attribute
     - Fastest access, used for real-time display
     - Stored in Agent state

  2. **Warm tier** (ETS): Next @warm_limit entries per attribute
     - Fast concurrent reads
     - Automatically managed with overflow from hot tier

  Database persistence is opt-in and not yet implemented.
  All data lives in memory for maximum performance.

  ## Memory Budget

  With default limits (500 hot + 10,000 warm = 10,500 per attribute):
  - 1000 sensors × 5 attributes × 10,500 entries × 200 bytes ≈ 10 GB

  Adjust @hot_limit and @warm_limit based on available memory.

  ## Usage

  Drop-in replacement for Sensocto.AttributeStore with same public API.
  """
  use Agent
  require Logger

  # Tier limits - all in-memory (configurable via application env)
  # Hot: fastest access, in process memory
  @default_hot_limit 500
  # Warm: fast concurrent reads via ETS
  @default_warm_limit 10_000
  @default_query_limit 500

  # ETS table name prefix
  @warm_table_prefix :attribute_store_warm_

  defp hot_limit, do: Application.get_env(:sensocto, :attribute_store_hot_limit, @default_hot_limit)
  defp warm_limit, do: Application.get_env(:sensocto, :attribute_store_warm_limit, @default_warm_limit)

  def start_link(%{sensor_id: sensor_id} = configuration) do
    Logger.debug("AttributeStoreTiered start_link: #{inspect(configuration)}")

    # Create ETS table for warm storage
    warm_table = warm_table_name(sensor_id)

    if :ets.whereis(warm_table) == :undefined do
      :ets.new(warm_table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    Agent.start_link(fn -> %{sensor_id: sensor_id} end, name: via_tuple(sensor_id))
  end

  @doc """
  Store a new measurement for an attribute.
  Automatically manages tier overflow.
  """
  def put_attribute(sensor_id, attribute_id, timestamp, payload) do
    Agent.update(via_tuple(sensor_id), fn state ->
      srv_put_attribute_state(state, sensor_id, attribute_id, timestamp, payload)
    end)
  end

  @doc """
  Get all attributes with their recent measurements.
  Returns only hot tier data by default for performance.
  """
  def get_attributes(sensor_id, limit \\ @default_query_limit) do
    Agent.get(via_tuple(sensor_id), fn state ->
      Enum.reduce(state, %{}, fn
        {:sensor_id, _}, acc ->
          acc

        {attribute_id, attr}, acc ->
          limited_payloads =
            case attr do
              %{payloads: payloads} -> Enum.take(payloads, limit)
              _ -> []
            end

          Map.put(acc, attribute_id, limited_payloads)
      end)
    end)
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
    Agent.get(via_tuple(sensor_id), fn state ->
      hot_data = get_hot_data(state, attribute_id)
      warm_data = get_warm_data(sensor_id, attribute_id)

      # Combine hot and warm data (hot is newer)
      all_data = hot_data ++ warm_data

      filtered =
        all_data
        |> maybe_filter_time(from_timestamp, to_timestamp)
        |> maybe_take(limit)

      {:ok, filtered}
    end)
  end

  @doc """
  Get attribute data including warm tier.
  Use this when you need more historical data than hot tier provides.
  """
  def get_attribute_extended(sensor_id, attribute_id, limit \\ @default_warm_limit) do
    Agent.get(via_tuple(sensor_id), fn state ->
      hot_data = get_hot_data(state, attribute_id)
      warm_data = get_warm_data(sensor_id, attribute_id)

      (hot_data ++ warm_data)
      |> Enum.take(limit)
    end)
  end

  @doc """
  Remove an attribute and its data from all tiers.
  """
  def remove_attribute(sensor_id, attribute_id) do
    # Remove from warm tier
    warm_table = warm_table_name(sensor_id)

    if :ets.whereis(warm_table) != :undefined do
      :ets.delete(warm_table, attribute_id)
    end

    # Remove from hot tier
    Agent.update(via_tuple(sensor_id), fn state ->
      Map.delete(state, attribute_id)
    end)
  end

  @doc """
  Get memory stats for this sensor's attribute store.
  """
  def stats(sensor_id) do
    Agent.get(via_tuple(sensor_id), fn state ->
      hot_count =
        state
        |> Enum.reject(fn {k, _} -> k == :sensor_id end)
        |> Enum.map(fn {_attr_id, %{payloads: payloads}} -> length(payloads) end)
        |> Enum.sum()

      warm_table = warm_table_name(sensor_id)

      warm_count =
        if :ets.whereis(warm_table) != :undefined do
          :ets.info(warm_table, :size)
        else
          0
        end

      %{
        sensor_id: sensor_id,
        hot_entries: hot_count,
        warm_entries: warm_count,
        attributes: map_size(state) - 1
      }
    end)
  end

  @doc """
  Cleanup resources when sensor is terminated.
  """
  def cleanup(sensor_id) do
    warm_table = warm_table_name(sensor_id)

    if :ets.whereis(warm_table) != :undefined do
      :ets.delete(warm_table)
    end
  end

  ## Private functions

  defp srv_put_attribute_state(state, sensor_id, attribute_id, timestamp, payload) do
    new_entry = %{payload: payload, timestamp: timestamp}

    current_attr =
      case Map.get(state, attribute_id) do
        nil -> %{payloads: []}
        attr -> attr
      end

    # Prepend new entry to hot data
    new_payloads = [new_entry | current_attr.payloads]

    # Check if we need to overflow to warm tier
    {hot_payloads, overflow} = Enum.split(new_payloads, hot_limit())

    # Push overflow to warm tier
    if overflow != [] do
      push_to_warm_tier(sensor_id, attribute_id, overflow)
    end

    Map.put(state, attribute_id, %{current_attr | payloads: hot_payloads})
  end

  defp push_to_warm_tier(sensor_id, attribute_id, entries) do
    warm_table = warm_table_name(sensor_id)

    if :ets.whereis(warm_table) != :undefined do
      # Get existing warm data
      existing =
        case :ets.lookup(warm_table, attribute_id) do
          [{^attribute_id, data}] -> data
          [] -> []
        end

      # Prepend new entries and limit
      new_warm = Enum.take(entries ++ existing, warm_limit())
      :ets.insert(warm_table, {attribute_id, new_warm})
    end
  end

  defp get_hot_data(state, attribute_id) do
    case Map.get(state, attribute_id) do
      %{payloads: payloads} -> payloads
      _ -> []
    end
  end

  defp get_warm_data(sensor_id, attribute_id) do
    warm_table = warm_table_name(sensor_id)

    if :ets.whereis(warm_table) != :undefined do
      case :ets.lookup(warm_table, attribute_id) do
        [{^attribute_id, data}] -> data
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

  # Handle nil, :infinity, or missing limit by returning all data
  defp maybe_take(payloads, nil), do: payloads
  defp maybe_take(payloads, :infinity), do: payloads
  defp maybe_take(payloads, limit) when is_integer(limit) and limit > 0, do: Enum.take(payloads, limit)
  defp maybe_take(payloads, _), do: payloads

  defp warm_table_name(sensor_id) do
    # Convert sensor_id to atom-safe format
    safe_id = sensor_id |> to_string() |> String.replace("-", "_")
    :"#{@warm_table_prefix}#{safe_id}"
  end

  defp via_tuple(sensor_id) do
    {:via, Registry, {Sensocto.SimpleAttributeRegistry, sensor_id}}
  end
end
