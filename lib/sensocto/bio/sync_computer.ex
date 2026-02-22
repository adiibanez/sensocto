defmodule Sensocto.Bio.SyncComputer do
  @moduledoc """
  Kuramoto phase synchronization computer for breathing and HRV sensors.

  Demand-driven: only subscribes to sensor data and computes sync when there
  are active viewers (via `register_viewer/0` / `unregister_viewer/0`).
  When no viewers are present, the system is idle to conserve resources on
  constrained environments like shared-CPU Fly.dev instances.

  Subscribes to per-sensor `data:{sensor_id}` PubSub topics (which always
  broadcast, bypassing attention gating) to compute sync even for sensors
  that no individual viewer has focused.

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

  # Minimum buffer lengths for RSA (need both signals with enough data)
  @rsa_min_buffer 10

  # Minimum interval between PubSub broadcasts per sync type (ms)
  # Prevents flooding MIDI output — sync values change slowly anyway
  @broadcast_throttle_ms 200

  defstruct tracked_sensors: MapSet.new(),
            phase_buffers: %{breathing: %{}, hrv: %{}},
            smoothed: %{breathing: 0.0, hrv: 0.0, rsa: 0.0},
            last_broadcast: %{},
            pending_checks: MapSet.new(),
            viewer_count: 0,
            # Track viewer PIDs to auto-cleanup on crash and prevent double-registration
            viewer_pids: %{},
            active: false

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_sync(group) when group in [:breathing, :hrv, :rsa] do
    GenServer.call(__MODULE__, {:get_sync, group})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def tracked_sensor_count do
    GenServer.call(__MODULE__, :tracked_sensor_count)
  end

  @doc """
  Register a viewer. When viewer count goes from 0 to 1, the SyncComputer
  activates: discovers sensors and subscribes to their data topics.
  """
  def register_viewer do
    GenServer.call(__MODULE__, :register_viewer)
  end

  @doc """
  Unregister a viewer. When viewer count drops to 0, the SyncComputer
  deactivates: unsubscribes from all sensor data topics to conserve resources.
  Buffers and smoothed values are preserved for fast reactivation.
  """
  def unregister_viewer do
    GenServer.cast(__MODULE__, {:unregister_viewer, self()})
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    # Always listen for sensor discovery events (low frequency)
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "discovery:sensors")

    # Don't discover/subscribe to sensors yet — demand-driven.
    # Wait for register_viewer to activate.

    Logger.info("[Bio.SyncComputer] Started (demand-driven, idle until viewers register)")
    {:ok, %__MODULE__{}}
  end

  # --- GenServer Calls ---

  @impl true
  def handle_call(:register_viewer, {caller_pid, _}, state) do
    if Map.has_key?(state.viewer_pids, caller_pid) do
      # Already registered — idempotent, don't increment count
      {:reply, :ok, state}
    else
      ref = Process.monitor(caller_pid)
      new_pids = Map.put(state.viewer_pids, caller_pid, ref)
      new_count = map_size(new_pids)

      state =
        if state.viewer_count == 0 do
          Logger.info("[Bio.SyncComputer] Activating (first viewer registered)")
          activate(state)
        else
          state
        end

      {:reply, :ok, %{state | viewer_count: new_count, viewer_pids: new_pids}}
    end
  end

  def handle_call({:get_sync, group}, _from, state) do
    {:reply, Map.get(state.smoothed, group, 0.0), state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:tracked_sensor_count, _from, state) do
    {:reply, MapSet.size(state.tracked_sensors), state}
  end

  # --- Viewer Management (cast) ---

  @impl true
  def handle_cast({:unregister_viewer, caller_pid}, state) do
    {:noreply, remove_viewer(state, caller_pid)}
  end

  # --- Sensor Discovery ---

  @impl true
  def handle_info(:discover_existing_sensors, state) do
    # Only discover if active
    if not state.active do
      {:noreply, state}
    else
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
  end

  @impl true
  def handle_info({:sensor_registered, sensor_id, _view_state, _node}, state) do
    # Only track new sensors if active
    if not state.active do
      {:noreply, state}
    else
      pending = MapSet.put(state.pending_checks, sensor_id)
      # Delay to let attributes auto-register on first data
      Process.send_after(self(), :check_pending, @attribute_discovery_delay_ms)
      {:noreply, %{state | pending_checks: pending}}
    end
  end

  @impl true
  def handle_info({:sensor_unregistered, sensor_id, _node}, state) do
    state =
      if MapSet.member?(state.tracked_sensors, sensor_id) do
        Logger.debug("[Bio.SyncComputer] Sensor unregistered: #{sensor_id}")

        if state.active do
          Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")
        end

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
    # Skip if not active
    if not state.active do
      {:noreply, state}
    else
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
        |> maybe_compute_rsa()
        |> then(&{:noreply, &1})

      attr_id in @hrv_attrs ->
        value = extract_sync_value(measurement.payload)

        state
        |> append_to_buffer(:hrv, measurement.sensor_id, [value], @hrv_phase_buffer_size)
        |> maybe_compute_sync(:hrv, @hrv_min_buffer)
        |> maybe_compute_rsa()
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
      |> maybe_compute_rsa()

    {:noreply, state}
  end

  # --- Periodic Cleanup ---

  @impl true
  def handle_info(:cleanup_stale_sensors, state) do
    state =
      if state.active do
        stale =
          state.tracked_sensors
          |> Enum.reject(fn sensor_id ->
            try do
              Sensocto.SimpleSensor.alive?(sensor_id)
            catch
              :exit, _ -> false
            end
          end)

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
      else
        state
      end

    breathing_count = map_size(state.phase_buffers.breathing)
    hrv_count = map_size(state.phase_buffers.hrv)

    Logger.info(
      "[Bio.SyncComputer] Status: #{MapSet.size(state.tracked_sensors)} sensors tracked " <>
        "(#{breathing_count} breathing, #{hrv_count} HRV), " <>
        "sync: breathing=#{round(state.smoothed.breathing * 100)}%, hrv=#{round(state.smoothed.hrv * 100)}%, rsa=#{round(Map.get(state.smoothed, :rsa, 0.0) * 100)}%, " <>
        "viewers: #{state.viewer_count}, active: #{state.active}"
    )

    Process.send_after(self(), :cleanup_stale_sensors, @cleanup_interval)
    {:noreply, state}
  end

  # Auto-cleanup when a viewer process dies
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_viewer(state, pid)}
  end

  # Catch-all for unknown messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Viewer Cleanup ---

  defp remove_viewer(state, pid) do
    case Map.pop(state.viewer_pids, pid) do
      {nil, _} ->
        state

      {ref, new_pids} ->
        Process.demonitor(ref, [:flush])
        new_count = map_size(new_pids)

        state =
          if new_count == 0 and state.viewer_count > 0 do
            Logger.info("[Bio.SyncComputer] Deactivating (no more viewers)")
            deactivate(state)
          else
            state
          end

        %{state | viewer_count: new_count, viewer_pids: new_pids}
    end
  end

  # --- Activation / Deactivation ---

  defp activate(state) do
    # Discover and subscribe to sensors
    Process.send_after(self(), :discover_existing_sensors, 200)

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_stale_sensors, @cleanup_interval)

    %{state | active: true}
  end

  defp deactivate(state) do
    # Unsubscribe from all tracked sensor data topics
    Enum.each(state.tracked_sensors, fn sensor_id ->
      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")
    end)

    Logger.info(
      "[Bio.SyncComputer] Unsubscribed from #{MapSet.size(state.tracked_sensors)} sensor topics"
    )

    # Keep tracked_sensors and buffers for fast reactivation
    # (if a viewer comes back quickly, we don't lose the buffer state)
    %{state | active: false}
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
      combined = :lists.append(buffer, values)

      new_buffer =
        case length(combined) - buffer_size do
          excess when excess > 0 -> Enum.drop(combined, excess)
          _ -> combined
        end

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

      now = System.system_time(:millisecond)

      AttributeStoreTiered.put_attribute(
        "__composite_sync",
        sync_attr_id,
        now,
        sync_value
      )

      state = maybe_broadcast_sync(state, sync_attr_id, sync_value, now)
      %{state | smoothed: Map.put(state.smoothed, group, smoothed)}
    else
      state
    end
  end

  # Compute Respiratory Sinus Arrhythmia (RSA) as the phase-locking value
  # between each sensor's breathing and HRV signals. RSA measures vagal tone --
  # how strongly the parasympathetic nervous system couples breathing to heart rate.
  # PLV = |mean(e^(i*(theta_breathing - theta_hrv)))| per sensor, then averaged.
  defp maybe_compute_rsa(state) do
    breathing_buffers = state.phase_buffers.breathing
    hrv_buffers = state.phase_buffers.hrv

    # Find sensors that have both breathing and HRV buffers with enough data
    rsa_values =
      breathing_buffers
      |> Enum.flat_map(fn {sensor_id, breathing_buf} ->
        case Map.get(hrv_buffers, sensor_id) do
          nil ->
            []

          hrv_buf
          when length(hrv_buf) >= @rsa_min_buffer and
                 length(breathing_buf) >= @rsa_min_buffer ->
            breathing_phase = estimate_phase(breathing_buf)
            hrv_phase = estimate_phase(hrv_buf)

            if breathing_phase && hrv_phase do
              # PLV for a single time point: phase difference consistency
              # For instantaneous phases, this is the magnitude of e^(i*delta)
              # which is always 1.0. Instead, compute PLV over the buffer:
              # use multiple phase estimates from sliding windows.
              [{sensor_id, compute_buffer_plv(breathing_buf, hrv_buf)}]
            else
              []
            end

          _ ->
            []
        end
      end)

    if rsa_values != [] do
      mean_rsa = Enum.sum(Enum.map(rsa_values, &elem(&1, 1))) / length(rsa_values)

      prev = state.smoothed.rsa

      smoothed =
        if prev == 0.0,
          do: mean_rsa,
          else: (1.0 - @smoothing_alpha) * prev + @smoothing_alpha * mean_rsa

      rsa_pct = round(smoothed * 100)

      now = System.system_time(:millisecond)

      AttributeStoreTiered.put_attribute(
        "__composite_sync",
        "rsa_coherence",
        now,
        rsa_pct
      )

      state = maybe_broadcast_sync(state, "rsa_coherence", rsa_pct, now)
      %{state | smoothed: Map.put(state.smoothed, :rsa, smoothed)}
    else
      state
    end
  end

  # Compute PLV between two signal buffers by estimating phase at multiple
  # overlapping windows and measuring the consistency of their phase difference.
  defp compute_buffer_plv(buf_a, buf_b) do
    window_size = min(length(buf_a), length(buf_b)) |> min(20)
    steps = max(1, window_size - 5)

    phase_diffs =
      for offset <- 0..(steps - 1) do
        window_a = Enum.slice(buf_a, offset, window_size)
        window_b = Enum.slice(buf_b, offset, window_size)

        phase_a = estimate_phase(window_a)
        phase_b = estimate_phase(window_b)

        if phase_a && phase_b, do: phase_a - phase_b, else: nil
      end
      |> Enum.reject(&is_nil/1)

    if phase_diffs == [] do
      0.0
    else
      n = length(phase_diffs)
      sum_cos = Enum.reduce(phase_diffs, 0.0, fn d, acc -> acc + :math.cos(d) end)
      sum_sin = Enum.reduce(phase_diffs, 0.0, fn d, acc -> acc + :math.sin(d) end)
      :math.sqrt(:math.pow(sum_cos / n, 2) + :math.pow(sum_sin / n, 2))
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

  # Throttled PubSub broadcast — at most once per @broadcast_throttle_ms per attr_id.
  # Prevents flooding MIDI output with 100+ updates/sec when sync changes slowly.
  defp maybe_broadcast_sync(state, attr_id, value, now) do
    last = Map.get(state.last_broadcast, attr_id, 0)

    if now - last >= @broadcast_throttle_ms do
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "sync:updates",
        {:sync_update, attr_id, value, now}
      )

      %{state | last_broadcast: Map.put(state.last_broadcast, attr_id, now)}
    else
      state
    end
  end
end
