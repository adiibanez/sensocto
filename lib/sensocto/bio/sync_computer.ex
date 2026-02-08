defmodule Sensocto.Bio.SyncComputer do
  @moduledoc """
  Kuramoto phase synchronization computer for breathing and HRV sensors.

  Runs continuously regardless of viewers, computing phase sync metrics
  and storing them in AttributeStoreTiered for later retrieval.

  Subscribes to per-sensor `data:{sensor_id}` PubSub topics (which always
  broadcast, bypassing attention gating) to ensure sync is computed even
  when no LiveView is watching.

  ## Algorithm

  - Maintains rolling phase buffers per sensor (breathing: 50, HRV: 20)
  - Estimates instantaneous phase from normalized value + derivative direction
  - Computes Kuramoto order parameter: R = |mean(e^(iθ))|
  - Applies exponential smoothing: 0.85 * prev + 0.15 * R
  - Stores as attribute under "__composite_sync" sensor in AttributeStoreTiered
  """

  use GenServer
  require Logger

  alias Sensocto.AttributeStoreTiered

  # Buffer configuration
  @breathing_phase_buffer_size 50
  @hrv_phase_buffer_size 20

  # Minimum buffer length before computing sync
  @breathing_min_buffer 15
  @hrv_min_buffer 8

  # Exponential smoothing factor
  @smoothing_alpha 0.15

  # Delay for attribute discovery after sensor registration (ms)
  @attribute_discovery_delay_ms 2_000

  # Periodic cleanup interval
  @cleanup_interval :timer.minutes(5)

  # Relevant attribute IDs
  @breathing_attrs ["respiration"]
  @hrv_attrs ["hrv"]

  defstruct tracked_sensors: MapSet.new(),
            phase_buffers: %{breathing: %{}, hrv: %{}},
            smoothed: %{breathing: 0.0, hrv: 0.0},
            pending_checks: MapSet.new()

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_sync(group) when group in [:breathing, :hrv] do
    GenServer.call(__MODULE__, {:get_sync, group})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def tracked_sensor_count do
    GenServer.call(__MODULE__, :tracked_sensor_count)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "discovery:sensors")

    # Discover existing sensors (delayed to allow system startup)
    Process.send_after(self(), :discover_existing_sensors, 500)

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_stale_sensors, @cleanup_interval)

    Logger.info("[Bio.SyncComputer] Started")
    {:ok, %__MODULE__{}}
  end

  # --- Sensor Discovery ---

  @impl true
  def handle_info(:discover_existing_sensors, state) do
    sensor_ids =
      try do
        Sensocto.SensorsDynamicSupervisor.get_device_names()
      catch
        :exit, _ -> []
      end

    Logger.info("[Bio.SyncComputer] Discovering #{length(sensor_ids)} existing sensors")
    pending = Enum.reduce(sensor_ids, state.pending_checks, &MapSet.put(&2, &1))
    Process.send_after(self(), :check_pending, @attribute_discovery_delay_ms)
    {:noreply, %{state | pending_checks: pending}}
  end

  @impl true
  def handle_info({:sensor_registered, sensor_id, _view_state, _node}, state) do
    pending = MapSet.put(state.pending_checks, sensor_id)
    # Delay to let attributes auto-register on first data
    Process.send_after(self(), :check_pending, @attribute_discovery_delay_ms)
    {:noreply, %{state | pending_checks: pending}}
  end

  @impl true
  def handle_info({:sensor_unregistered, sensor_id, _node}, state) do
    state =
      if MapSet.member?(state.tracked_sensors, sensor_id) do
        Logger.debug("[Bio.SyncComputer] Sensor unregistered: #{sensor_id}")
        Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")

        %{
          state
          | tracked_sensors: MapSet.delete(state.tracked_sensors, sensor_id),
            phase_buffers: %{
              breathing: Map.delete(state.phase_buffers.breathing, sensor_id),
              hrv: Map.delete(state.phase_buffers.hrv, sensor_id)
            }
        }
      else
        %{state | pending_checks: MapSet.delete(state.pending_checks, sensor_id)}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:sensor_updated, _sensor_id, _view_state, _node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_pending, state) do
    to_check =
      state.pending_checks
      |> MapSet.difference(state.tracked_sensors)
      |> MapSet.to_list()

    if to_check == [] do
      {:noreply, %{state | pending_checks: MapSet.new()}}
    else
      # Check attributes in parallel using Task.async_stream (non-blocking)
      results =
        to_check
        |> Task.async_stream(
          fn sensor_id ->
            has_relevant =
              try do
                case Sensocto.SimpleSensor.get_state(sensor_id, 1) do
                  %{attributes: attrs} when is_map(attrs) ->
                    Enum.any?(Map.keys(attrs), fn key ->
                      key in ["respiration", "hrv"]
                    end)

                  _ ->
                    false
                end
              catch
                :exit, _ -> false
              end

            {sensor_id, has_relevant}
          end,
          max_concurrency: 10,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, {sensor_id, true}} -> [sensor_id]
          _ -> []
        end)

      Enum.each(results, fn sensor_id ->
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      end)

      if results != [] do
        Logger.info(
          "[Bio.SyncComputer] Tracking #{length(results)} sensors: #{Enum.join(results, ", ")}"
        )
      end

      tracked = Enum.reduce(results, state.tracked_sensors, &MapSet.put(&2, &1))
      {:noreply, %{state | tracked_sensors: tracked, pending_checks: MapSet.new()}}
    end
  end

  # --- Measurement Processing ---

  @impl true
  def handle_info({:measurement, %{attribute_id: attr_id} = measurement}, state) do
    cond do
      attr_id in @breathing_attrs ->
        value = extract_sync_value(measurement.payload)

        state
        |> append_to_buffer(
          :breathing,
          measurement.sensor_id,
          [value],
          @breathing_phase_buffer_size
        )
        |> maybe_compute_sync(:breathing, @breathing_min_buffer)
        |> then(&{:noreply, &1})

      attr_id in @hrv_attrs ->
        value = extract_sync_value(measurement.payload)

        state
        |> append_to_buffer(:hrv, measurement.sensor_id, [value], @hrv_phase_buffer_size)
        |> maybe_compute_sync(:hrv, @hrv_min_buffer)
        |> then(&{:noreply, &1})

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:measurements_batch, {_sensor_id, measurements}}, state) do
    state =
      Enum.reduce(measurements, state, fn measurement, acc ->
        attr_id = Map.get(measurement, :attribute_id, "")
        sid = Map.get(measurement, :sensor_id, "")

        cond do
          attr_id in @breathing_attrs ->
            value = extract_sync_value(measurement.payload)
            append_to_buffer(acc, :breathing, sid, [value], @breathing_phase_buffer_size)

          attr_id in @hrv_attrs ->
            value = extract_sync_value(measurement.payload)
            append_to_buffer(acc, :hrv, sid, [value], @hrv_phase_buffer_size)

          true ->
            acc
        end
      end)

    state =
      state
      |> maybe_compute_sync(:breathing, @breathing_min_buffer)
      |> maybe_compute_sync(:hrv, @hrv_min_buffer)

    {:noreply, state}
  end

  # --- Periodic Cleanup ---

  @impl true
  def handle_info(:cleanup_stale_sensors, state) do
    stale =
      state.tracked_sensors
      |> Enum.reject(fn sensor_id ->
        try do
          Sensocto.SimpleSensor.alive?(sensor_id)
        catch
          :exit, _ -> false
        end
      end)

    state =
      if stale != [] do
        Logger.info("[Bio.SyncComputer] Cleaning up #{length(stale)} stale sensors")

        Enum.each(stale, fn sensor_id ->
          Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")
        end)

        stale_set = MapSet.new(stale)

        %{
          state
          | tracked_sensors: MapSet.difference(state.tracked_sensors, stale_set),
            phase_buffers: %{
              breathing: Map.drop(state.phase_buffers.breathing, stale),
              hrv: Map.drop(state.phase_buffers.hrv, stale)
            }
        }
      else
        state
      end

    breathing_count = map_size(state.phase_buffers.breathing)
    hrv_count = map_size(state.phase_buffers.hrv)

    Logger.info(
      "[Bio.SyncComputer] Status: #{MapSet.size(state.tracked_sensors)} sensors tracked " <>
        "(#{breathing_count} breathing, #{hrv_count} HRV), " <>
        "sync: breathing=#{round(state.smoothed.breathing * 100)}%, hrv=#{round(state.smoothed.hrv * 100)}%"
    )

    Process.send_after(self(), :cleanup_stale_sensors, @cleanup_interval)
    {:noreply, state}
  end

  # Catch-all for unknown messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- GenServer Calls ---

  @impl true
  def handle_call({:get_sync, group}, _from, state) do
    {:reply, Map.get(state.smoothed, group, 0.0), state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:tracked_sensor_count, _from, state) do
    {:reply, MapSet.size(state.tracked_sensors), state}
  end

  # --- Private Helpers ---

  defp extract_sync_value(payload) when is_number(payload), do: payload * 1.0

  defp extract_sync_value(payload) when is_map(payload) do
    val = payload["value"] || payload["v"] || payload[:value]
    if is_number(val), do: val * 1.0, else: 0.0
  end

  defp extract_sync_value(_), do: 0.0

  defp append_to_buffer(state, group, sensor_id, values, buffer_size) do
    if values == [] do
      state
    else
      group_buffers = state.phase_buffers[group]
      buffer = Map.get(group_buffers, sensor_id, [])
      new_buffer = Enum.take(buffer ++ values, -buffer_size)
      new_group_buffers = Map.put(group_buffers, sensor_id, new_buffer)
      %{state | phase_buffers: Map.put(state.phase_buffers, group, new_group_buffers)}
    end
  end

  defp maybe_compute_sync(state, group, min_buffer_len) do
    group_buffers = state.phase_buffers[group]

    phases =
      group_buffers
      |> Map.values()
      |> Enum.map(fn buffer ->
        if length(buffer) >= min_buffer_len, do: estimate_phase(buffer), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    if length(phases) >= 2 do
      n = length(phases)
      sum_cos = Enum.reduce(phases, 0.0, fn theta, acc -> acc + :math.cos(theta) end)
      sum_sin = Enum.reduce(phases, 0.0, fn theta, acc -> acc + :math.sin(theta) end)
      r = :math.sqrt(:math.pow(sum_cos / n, 2) + :math.pow(sum_sin / n, 2))

      prev = state.smoothed[group]

      smoothed =
        if prev == 0.0, do: r, else: (1.0 - @smoothing_alpha) * prev + @smoothing_alpha * r

      sync_value = round(smoothed * 100)

      sync_attr_id =
        case group do
          :breathing -> "breathing_sync"
          :hrv -> "hrv_sync"
        end

      AttributeStoreTiered.put_attribute(
        "__composite_sync",
        sync_attr_id,
        System.system_time(:millisecond),
        sync_value
      )

      %{state | smoothed: Map.put(state.smoothed, group, smoothed)}
    else
      state
    end
  end

  # Estimate instantaneous phase from a rolling buffer of sensor values.
  # Uses normalized value + derivative direction to map to [0, 2*pi].
  defp estimate_phase(buffer) do
    n = length(buffer)
    {min_val, max_val} = Enum.min_max(buffer)
    range = max_val - min_val

    if range < 2 do
      nil
    else
      current = List.last(buffer)
      norm = max(0.0, min(1.0, (current - min_val) / range))

      lookback = min(5, n - 1)
      derivative = current - Enum.at(buffer, n - 1 - lookback)

      base_angle = :math.acos(1 - 2 * norm)
      if derivative >= 0, do: base_angle, else: 2 * :math.pi() - base_angle
    end
  end
end
