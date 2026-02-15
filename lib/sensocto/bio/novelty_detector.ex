defmodule Sensocto.Bio.NoveltyDetector do
  @moduledoc """
  Locus Coeruleus-inspired novelty detection.

  Detects anomalous sensor readings using online statistics (Welford's algorithm)
  and broadcasts attention boosts for novel events.

  ## How It Works

  1. Each sensor/attribute pair maintains running mean and variance
  2. New values are compared against baseline (z-score calculation)
  3. Values beyond threshold (default: 3.0 = 99.7th percentile) trigger novelty
  4. Novelty events broadcast via PubSub, causing temporary attention boost

  ## Biological Inspiration

  The locus coeruleus detects novelty and floods the brain with norepinephrine,
  instantly boosting alertness. We replicate this by auto-boosting attention
  for statistically anomalous data.
  """

  use GenServer
  require Logger

  @novelty_threshold 3.0
  @min_samples 10
  @debounce_ms 10_000
  @cleanup_interval :timer.minutes(5)

  defstruct sensor_stats: %{},
            novelty_events: [],
            threshold: @novelty_threshold

  defmodule Stats do
    @moduledoc false
    defstruct [:mean, :m2, :count, :last_novelty]

    def new, do: %__MODULE__{mean: 0.0, m2: 0.0, count: 0, last_novelty: nil}
  end

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Report a batch of sensor readings for novelty analysis.
  Called by AttributeServer after pushing data.
  """
  def report_batch(sensor_id, attribute_id, batch) when is_list(batch) do
    GenServer.cast(__MODULE__, {:report_batch, sensor_id, attribute_id, batch})
  end

  @doc """
  Get current novelty score for a sensor/attribute.
  Returns 0.0-1.0 where 1.0 = highly anomalous.
  """
  def get_novelty_score(sensor_id, attribute_id) do
    case :ets.lookup(:bio_novelty_scores, {sensor_id, attribute_id}) do
      [{_, score, _timestamp}] -> score
      [] -> 0.0
    end
  rescue
    ArgumentError -> 0.0
  end

  @doc """
  Get baseline statistics for debugging.
  """
  def get_stats(sensor_id, attribute_id) do
    GenServer.call(__MODULE__, {:get_stats, sensor_id, attribute_id})
  end

  @doc """
  Get recent novelty events for monitoring.
  """
  def get_recent_events(limit \\ 20) do
    GenServer.call(__MODULE__, {:get_recent_events, limit})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    :ets.new(:bio_novelty_scores, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    threshold = Keyword.get(opts, :threshold, @novelty_threshold)

    # Subscribe to sensor lifecycle events for cleanup
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "discovery:sensors")

    # Schedule periodic cleanup of stale stats
    Process.send_after(self(), :cleanup_stale_stats, @cleanup_interval)

    Logger.info("Bio.NoveltyDetector started (threshold: #{threshold}σ)")

    {:ok, %__MODULE__{threshold: threshold}}
  end

  @impl true
  def handle_cast({:report_batch, sensor_id, attribute_id, batch}, state) do
    key = {sensor_id, attribute_id}
    stats = Map.get(state.sensor_stats, key, Stats.new())
    values = extract_values(batch)

    if length(values) > 0 do
      {new_stats, max_z_score} = process_values(stats, values)
      novelty_score = sigmoid(max_z_score - state.threshold)

      :ets.insert(:bio_novelty_scores, {key, novelty_score, System.system_time(:millisecond)})

      new_state =
        if max_z_score > state.threshold and new_stats.count >= @min_samples do
          handle_novelty_detected(
            sensor_id,
            attribute_id,
            max_z_score,
            novelty_score,
            new_stats,
            state
          )
        else
          state
        end

      new_sensor_stats = Map.put(new_state.sensor_stats, key, new_stats)
      {:noreply, %{new_state | sensor_stats: new_sensor_stats}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:get_stats, sensor_id, attribute_id}, _from, state) do
    stats = Map.get(state.sensor_stats, {sensor_id, attribute_id})
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_recent_events, limit}, _from, state) do
    events = Enum.take(state.novelty_events, limit)
    {:reply, events, state}
  end

  @impl true
  def handle_info({:sensor_unregistered, sensor_id, _node}, state) do
    # Remove all stats entries for this sensor
    new_stats =
      state.sensor_stats
      |> Enum.reject(fn {{sid, _attr_id}, _stats} -> sid == sensor_id end)
      |> Map.new()

    # Remove ETS entries for this sensor
    :ets.match_delete(:bio_novelty_scores, {{sensor_id, :_}, :_, :_})

    {:noreply, %{state | sensor_stats: new_stats}}
  end

  @impl true
  def handle_info({:sensor_registered, _sensor_id, _view_state, _node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:sensor_updated, _sensor_id, _view_state, _node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_stale_stats, state) do
    # Sweep entries where the sensor is no longer alive
    new_stats =
      state.sensor_stats
      |> Enum.filter(fn {{sensor_id, _attr_id}, _stats} ->
        Sensocto.SimpleSensor.alive?(sensor_id)
      end)
      |> Map.new()

    removed = map_size(state.sensor_stats) - map_size(new_stats)

    if removed > 0 do
      # Also clean ETS entries for removed sensors
      removed_sensor_ids =
        MapSet.difference(
          state.sensor_stats |> Map.keys() |> Enum.map(&elem(&1, 0)) |> MapSet.new(),
          new_stats |> Map.keys() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
        )

      Enum.each(removed_sensor_ids, fn sensor_id ->
        :ets.match_delete(:bio_novelty_scores, {{sensor_id, :_}, :_, :_})
      end)

      Logger.debug("[Bio.NoveltyDetector] Cleaned up #{removed} stale stat entries")
    end

    Process.send_after(self(), :cleanup_stale_stats, @cleanup_interval)
    {:noreply, %{state | sensor_stats: new_stats}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp extract_values(batch) do
    batch
    |> Enum.flat_map(fn
      %{payload: payload} when is_map(payload) -> extract_from_payload(payload)
      %{"payload" => payload} when is_map(payload) -> extract_from_payload(payload)
      _ -> []
    end)
  end

  defp extract_from_payload(payload) do
    cond do
      is_number(payload[:value]) -> [payload[:value]]
      is_number(payload["value"]) -> [payload["value"]]
      is_number(payload[:level]) -> [payload[:level]]
      is_number(payload["level"]) -> [payload["level"]]
      is_number(payload[:temperature]) -> [payload[:temperature]]
      is_number(payload["temperature"]) -> [payload["temperature"]]
      is_number(payload[:humidity]) -> [payload[:humidity]]
      is_number(payload["humidity"]) -> [payload["humidity"]]
      is_number(payload[:pressure]) -> [payload[:pressure]]
      is_number(payload["pressure"]) -> [payload["pressure"]]
      true -> []
    end
  end

  defp process_values(stats, values) do
    Enum.reduce(values, {stats, 0.0}, fn value, {s, max_z} ->
      z_score =
        if s.count > 1 do
          stddev = :math.sqrt(s.m2 / (s.count - 1))
          if stddev > 0.001, do: abs(value - s.mean) / stddev, else: 0.0
        else
          0.0
        end

      count = s.count + 1
      delta = value - s.mean
      mean = s.mean + delta / count
      delta2 = value - mean
      m2 = s.m2 + delta * delta2

      new_stats = %{s | mean: mean, m2: m2, count: count}
      {new_stats, max(max_z, z_score)}
    end)
  end

  defp handle_novelty_detected(sensor_id, attribute_id, z_score, novelty_score, stats, state) do
    now = System.system_time(:millisecond)

    should_fire =
      case stats.last_novelty do
        nil -> true
        last -> now - last > @debounce_ms
      end

    if should_fire do
      Logger.warning(
        "[Bio.NoveltyDetector] Anomaly: #{sensor_id}/#{attribute_id} " <>
          "z=#{Float.round(z_score, 2)}, score=#{Float.round(novelty_score, 2)}"
      )

      boost_duration = calculate_boost_duration(z_score)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "bio:novelty:#{sensor_id}",
        {:novelty_detected,
         %{
           sensor_id: sensor_id,
           attribute_id: attribute_id,
           z_score: z_score,
           novelty_score: novelty_score,
           boost_duration: boost_duration,
           timestamp: now
         }}
      )

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "bio:novelty:global",
        {:novelty_detected, sensor_id, attribute_id, z_score}
      )

      updated_stats = %{stats | last_novelty: now}
      key = {sensor_id, attribute_id}
      updated_sensor_stats = Map.put(state.sensor_stats, key, updated_stats)

      event = %{
        sensor_id: sensor_id,
        attribute_id: attribute_id,
        z_score: z_score,
        novelty_score: novelty_score,
        timestamp: now
      }

      events = Enum.take([event | state.novelty_events], 100)

      %{state | sensor_stats: updated_sensor_stats, novelty_events: events}
    else
      state
    end
  end

  defp calculate_boost_duration(z_score) do
    base = 10_000
    extra = min(z_score - @novelty_threshold, 10) * 5_000
    trunc(base + extra)
  end

  defp sigmoid(x), do: 1.0 / (1.0 + :math.exp(-x))
end
