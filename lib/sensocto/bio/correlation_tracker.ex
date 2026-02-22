defmodule Sensocto.Bio.CorrelationTracker do
  @moduledoc """
  Hebbian correlation learning for sensor co-access patterns.

  Tracks which sensors are accessed together and strengthens their association
  over time. When a sensor is accessed, its correlated peers can be pre-boosted
  for faster data delivery.

  ## Biological Inspiration

  Hebbian learning ("neurons that fire together wire together") is the basis
  for associative memory. We apply the same principle: sensors viewed together
  build stronger correlations, which decay over time without reinforcement.

  ## Usage

      # Record co-access when user views sensors together
      CorrelationTracker.record_co_access(["sensor_a", "sensor_b", "sensor_c"])

      # Get correlated sensors for pre-boosting
      CorrelationTracker.get_correlated("sensor_a")
      # => [{"sensor_b", 0.85}, {"sensor_c", 0.62}]

      # Get correlation strength between two sensors
      CorrelationTracker.get_strength("sensor_a", "sensor_b")
      # => 0.85
  """

  use GenServer
  require Logger

  @decay_interval :timer.hours(1)
  @decay_rate 0.95
  @learning_rate 0.1
  @min_strength 0.05
  @max_strength 1.0
  @correlation_threshold 0.3

  defstruct correlations: %{},
            access_log: [],
            last_decay: nil

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record that a set of sensors were accessed together.
  Strengthens pairwise correlations between all sensors in the group.
  """
  def record_co_access(sensor_ids) when is_list(sensor_ids) and length(sensor_ids) > 1 do
    GenServer.cast(__MODULE__, {:record_co_access, sensor_ids})
  end

  def record_co_access(_), do: :ok

  @doc """
  Get sensors correlated with the given sensor, sorted by strength.
  Returns `[{sensor_id, strength}]` where strength >= threshold.
  """
  def get_correlated(sensor_id) do
    GenServer.call(__MODULE__, {:get_correlated, sensor_id})
  end

  @doc """
  Get correlation strength between two sensors.
  Returns 0.0 if no correlation exists.
  """
  def get_strength(sensor_a, sensor_b) do
    GenServer.call(__MODULE__, {:get_strength, sensor_a, sensor_b})
  end

  @doc """
  Get all correlations for monitoring/debugging.
  """
  def get_all_correlations do
    GenServer.call(__MODULE__, :get_all_correlations)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Process.send_after(self(), :decay, @decay_interval)
    Logger.info("Bio.CorrelationTracker started")
    {:ok, %__MODULE__{last_decay: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:record_co_access, sensor_ids}, state) do
    # Generate all unique pairs and strengthen their correlations
    pairs = for a <- sensor_ids, b <- sensor_ids, a < b, do: {a, b}

    new_correlations =
      Enum.reduce(pairs, state.correlations, fn {a, b}, corrs ->
        key = correlation_key(a, b)
        current = Map.get(corrs, key, 0.0)
        # Hebbian update: strengthen by learning rate, capped at max
        new_strength = min(current + @learning_rate * (1.0 - current), @max_strength)
        Map.put(corrs, key, new_strength)
      end)

    # Keep recent access log for analytics (last 1000 entries)
    access_entry = {DateTime.utc_now(), sensor_ids}
    access_log = [access_entry | Enum.take(state.access_log, 999)]

    {:noreply, %{state | correlations: new_correlations, access_log: access_log}}
  end

  @impl true
  def handle_call({:get_correlated, sensor_id}, _from, state) do
    correlated =
      state.correlations
      |> Enum.filter(fn {key, strength} ->
        strength >= @correlation_threshold and involves_sensor?(key, sensor_id)
      end)
      |> Enum.map(fn {key, strength} ->
        other = other_sensor(key, sensor_id)
        {other, strength}
      end)
      |> Enum.sort_by(fn {_, strength} -> -strength end)

    {:reply, correlated, state}
  end

  @impl true
  def handle_call({:get_strength, sensor_a, sensor_b}, _from, state) do
    key = correlation_key(sensor_a, sensor_b)
    strength = Map.get(state.correlations, key, 0.0)
    {:reply, strength, state}
  end

  @impl true
  def handle_call(:get_all_correlations, _from, state) do
    {:reply, state.correlations, state}
  end

  @impl true
  def handle_info(:decay, state) do
    # Apply exponential decay to all correlations
    new_correlations =
      state.correlations
      |> Enum.map(fn {key, strength} -> {key, strength * @decay_rate} end)
      |> Enum.reject(fn {_key, strength} -> strength < @min_strength end)
      |> Map.new()

    decayed_count = map_size(state.correlations) - map_size(new_correlations)

    if decayed_count > 0 do
      Logger.debug(
        "[Bio.CorrelationTracker] Decay cycle: #{decayed_count} correlations pruned, #{map_size(new_correlations)} remaining"
      )
    end

    Process.send_after(self(), :decay, @decay_interval)

    {:noreply, %{state | correlations: new_correlations, last_decay: DateTime.utc_now()}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Canonical key: always sorted so {a,b} == {b,a}
  defp correlation_key(a, b) when a < b, do: {a, b}
  defp correlation_key(a, b), do: {b, a}

  defp involves_sensor?({a, b}, sensor_id), do: a == sensor_id or b == sensor_id

  defp other_sensor({a, b}, sensor_id) do
    if a == sensor_id, do: b, else: a
  end
end
