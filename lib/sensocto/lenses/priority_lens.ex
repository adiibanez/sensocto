defmodule Sensocto.Lenses.PriorityLens do
  @moduledoc """
  Adaptive data lens using ETS for zero-copy buffering per socket.

  Each connected socket registers with the PriorityLens, specifying which
  sensors it cares about and its current quality level. Uses ETS tables
  for efficient buffering without copying data on every message.

  ## Philosophy

  Default to maximum throughput (raw/realtime data). Throttling is a last
  resort when server load becomes a problem - the system should keep trying
  to send as much realtime data as possible.

  ## Quality Levels

  - `:high` - ~60fps, full sensor set, maximum throughput
  - `:medium` - ~20fps, full sensor set, slight batching
  - `:low` - ~10fps, limited sensors (first level of throttling)
  - `:minimal` - ~5fps, few sensors (emergency mode)

  ## Topics

  Per-socket: `"lens:priority:{socket_id}"` - personalized stream

  ## Design (KISS with ETS)

  - Single ETS table for all socket buffers
  - Key: `{socket_id, sensor_id, attribute_id}`
  - Socket registration stored in separate ETS table
  - Flush reads relevant entries, broadcasts, clears per-socket

  ## Usage

  ```elixir
  # In LiveView mount
  socket_id = socket.id
  Sensocto.Lenses.PriorityLens.register_socket(socket_id, sensor_ids)
  Phoenix.PubSub.subscribe(Sensocto.PubSub, "lens:priority:\#{socket_id}")

  # Handle quality change
  Sensocto.Lenses.PriorityLens.set_quality(socket_id, :medium)

  # In terminate
  Sensocto.Lenses.PriorityLens.unregister_socket(socket_id)
  ```
  """

  use GenServer
  require Logger

  @buffer_table :priority_lens_buffers
  @sockets_table :priority_lens_sockets
  @digest_table :priority_lens_digests
  # Reverse index: sensor_id → MapSet of socket_ids (for O(1) lookup)
  @sensor_subs_table :priority_lens_sensor_subscriptions

  # Quality level configurations
  # Philosophy: Default to maximum throughput. Throttling is a last resort.
  @quality_configs %{
    # High throughput - ~30fps, sustainable for large sensor counts
    high: %{flush_interval_ms: 32, max_sensors: :unlimited, mode: :batch},
    # Still realtime, batched (~20fps)
    medium: %{flush_interval_ms: 50, max_sensors: :unlimited, mode: :batch},
    # First level of throttling - only when there's real backpressure
    low: %{flush_interval_ms: 100, max_sensors: 20, mode: :batch},
    # Emergency mode - significant throttling
    minimal: %{flush_interval_ms: 200, max_sensors: 5, mode: :batch},
    # Paused - stop sending data entirely (critical backpressure)
    paused: %{flush_interval_ms: :infinity, max_sensors: 0, mode: :paused}
  }

  # NOTE: Removed preemptive sensor-count-based throttling.
  # System now starts at requested quality regardless of sensor count.
  # Degradation only occurs based on actual backpressure (mailbox depth).

  # High-frequency attributes that need all samples preserved
  @high_frequency_attributes ~w(ecg)

  # Dead socket cleanup interval (1 minute)
  @gc_interval_ms :timer.minutes(1)

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a socket to receive priority-filtered data.
  Returns the topic to subscribe to.
  """
  def register_socket(socket_id, sensor_ids, opts \\ []) do
    quality = Keyword.get(opts, :quality, :high)
    focused_sensor = Keyword.get(opts, :focused_sensor)
    GenServer.call(__MODULE__, {:register_socket, socket_id, sensor_ids, quality, focused_sensor})
  end

  @doc """
  Unregister a socket.
  """
  def unregister_socket(socket_id) do
    GenServer.cast(__MODULE__, {:unregister_socket, socket_id})
  end

  @doc """
  Update the quality level for a socket.
  """
  def set_quality(socket_id, quality)
      when quality in [:high, :medium, :low, :minimal, :paused] do
    GenServer.cast(__MODULE__, {:set_quality, socket_id, quality})
  end

  @doc """
  Update the sensor list for a socket.
  """
  def set_sensors(socket_id, sensor_ids) do
    GenServer.cast(__MODULE__, {:set_sensors, socket_id, sensor_ids})
  end

  @doc """
  Set the focused sensor (gets priority even at low quality).
  """
  def set_focused_sensor(socket_id, sensor_id) do
    GenServer.cast(__MODULE__, {:set_focused_sensor, socket_id, sensor_id})
  end

  @doc """
  Get current state for a socket (for debugging).
  """
  def get_socket_state(socket_id) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, state}] -> state
      [] -> nil
    end
  end

  @doc """
  Get the topic for a socket.
  """
  def topic_for_socket(socket_id) do
    "lens:priority:#{socket_id}"
  end

  @doc """
  Select appropriate quality level based on sensor count.

  DEPRECATED: Now always returns :high. The system handles any sensor count
  at maximum quality, degrading only when actual backpressure is detected.
  Kept for API compatibility.
  """
  def quality_for_sensor_count(_sensor_count) do
    :high
  end

  # Quality levels in order from highest to lowest throughput
  @quality_order [:high, :medium, :low, :minimal, :paused]

  @doc """
  Returns the more conservative (lower throughput) of two quality levels.
  """
  def min_quality(q1, q2) do
    idx1 = Enum.find_index(@quality_order, &(&1 == q1)) || 0
    idx2 = Enum.find_index(@quality_order, &(&1 == q2)) || 0
    Enum.at(@quality_order, max(idx1, idx2))
  end

  @doc """
  Get aggregate stats for monitoring. Direct ETS reads, no GenServer call.
  Returns quality distribution, socket count, and sensor subscription counts.
  """
  def get_stats do
    try do
      socket_data = :ets.tab2list(@sockets_table)

      quality_distribution =
        Enum.reduce(socket_data, %{high: 0, medium: 0, low: 0, minimal: 0, paused: 0}, fn {_id,
                                                                                           state},
                                                                                          acc ->
          Map.update(acc, state.quality, 1, &(&1 + 1))
        end)

      total_sensor_subscriptions =
        Enum.reduce(socket_data, 0, fn {_id, state}, acc ->
          acc + MapSet.size(state.sensor_ids)
        end)

      paused_count = quality_distribution[:paused] || 0
      degraded_count = (quality_distribution[:low] || 0) + (quality_distribution[:minimal] || 0)

      %{
        socket_count: length(socket_data),
        quality_distribution: quality_distribution,
        total_sensor_subscriptions: total_sensor_subscriptions,
        paused_count: paused_count,
        degraded_count: degraded_count,
        healthy: paused_count == 0 and degraded_count == 0
      }
    rescue
      ArgumentError ->
        %{
          socket_count: 0,
          quality_distribution: %{high: 0, medium: 0, low: 0, minimal: 0, paused: 0},
          total_sensor_subscriptions: 0,
          paused_count: 0,
          degraded_count: 0,
          healthy: true
        }
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables
    # Buffer: {socket_id, sensor_id, attribute_id} => measurement or [measurements] for ECG
    :ets.new(@buffer_table, [:set, :public, :named_table, read_concurrency: true])

    # Sockets: socket_id => %{sensor_ids: MapSet, quality: atom, focused_sensor: string, timer_ref: ref}
    :ets.new(@sockets_table, [:set, :public, :named_table, read_concurrency: true])

    # Digests: {socket_id, sensor_id, attribute_id} => %{count, sum, min, max, latest, latest_timestamp}
    :ets.new(@digest_table, [:set, :public, :named_table, read_concurrency: true])

    # Reverse index: sensor_id => MapSet of socket_ids for O(1) lookup
    :ets.new(@sensor_subs_table, [:set, :public, :named_table, read_concurrency: true])

    # Don't register with Router yet - demand-driven.
    # Register only when the first socket connects, unregister when the last disconnects.
    # This prevents the entire data:global pipeline from running when no one is viewing.

    # Schedule periodic dead socket cleanup
    schedule_gc()

    Logger.info("PriorityLens started (demand-driven, not yet registered with Router)")

    {:ok, %{registered_with_router: false}}
  end

  @impl true
  def handle_call(
        {:register_socket, socket_id, sensor_ids, requested_quality, focused_sensor},
        {caller_pid, _},
        state
      ) do
    topic = topic_for_socket(socket_id)

    # Use requested quality directly - no preemptive throttling based on sensor count.
    # System handles any number of sensors at high quality, degrading only on actual backpressure.
    quality = requested_quality

    config = @quality_configs[quality]

    # Schedule flush timer
    timer_ref = schedule_flush(socket_id, config.flush_interval_ms)

    # Monitor the caller (LiveView process) to auto-cleanup on crash
    monitor_ref = Process.monitor(caller_pid)

    socket_state = %{
      sensor_ids: MapSet.new(sensor_ids),
      quality: quality,
      focused_sensor: focused_sensor,
      timer_ref: timer_ref,
      topic: topic,
      owner_pid: caller_pid,
      monitor_ref: monitor_ref
    }

    :ets.insert(@sockets_table, {socket_id, socket_state})

    # Update reverse index: sensor_id -> socket_ids
    update_sensor_subscriptions(socket_id, MapSet.new(), MapSet.new(sensor_ids))

    # Register with Router on first socket (demand-driven)
    state = maybe_register_with_router(state)

    Logger.debug("PriorityLens: registered socket #{socket_id} with quality #{quality}")

    {:reply, {:ok, topic}, state}
  end

  @impl true
  def handle_cast({:unregister_socket, socket_id}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        # Cancel timer
        if socket_state.timer_ref, do: Process.cancel_timer(socket_state.timer_ref)

        # Clean up reverse index
        update_sensor_subscriptions(socket_id, socket_state.sensor_ids, MapSet.new())

        # Clean up all ETS entries for this socket
        :ets.match_delete(@buffer_table, {{socket_id, :_, :_}, :_})
        :ets.match_delete(@digest_table, {{socket_id, :_, :_}, :_})
        :ets.delete(@sockets_table, socket_id)

        Logger.debug("PriorityLens: unregistered socket #{socket_id}")

      [] ->
        :ok
    end

    # Unregister from Router if no more sockets (demand-driven)
    state = maybe_unregister_from_router(state)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_quality, socket_id, quality}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        # Cancel old timer
        if socket_state.timer_ref, do: Process.cancel_timer(socket_state.timer_ref)

        config = @quality_configs[quality]
        new_timer = schedule_flush(socket_id, config.flush_interval_ms)

        updated = %{socket_state | quality: quality, timer_ref: new_timer}
        :ets.insert(@sockets_table, {socket_id, updated})

        Logger.debug("PriorityLens: socket #{socket_id} quality changed to #{quality}")

      [] ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_sensors, socket_id, sensor_ids}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        old_sensors = socket_state.sensor_ids
        new_sensors = MapSet.new(sensor_ids)

        # Update reverse index
        update_sensor_subscriptions(socket_id, old_sensors, new_sensors)

        updated = %{socket_state | sensor_ids: new_sensors}
        :ets.insert(@sockets_table, {socket_id, updated})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_focused_sensor, socket_id, sensor_id}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        updated = %{socket_state | focused_sensor: sensor_id}
        :ets.insert(@sockets_table, {socket_id, updated})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # Single measurement from router - write to ETS for interested sockets
  @impl true
  def handle_info({:router_measurement, sensor_id, measurement}, state) do
    attribute_id = Map.get(measurement, :attribute_id)

    # O(1) lookup of interested sockets via reverse index
    get_sockets_for_sensor(sensor_id)
    |> Enum.each(fn socket_id ->
      case :ets.lookup(@sockets_table, socket_id) do
        [{^socket_id, socket_state}] ->
          buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement)

        [] ->
          :ok
      end
    end)

    {:noreply, state}
  end

  # Batch measurements from router
  @impl true
  def handle_info({:router_measurements_batch, sensor_id, measurements}, state) do
    # O(1) lookup of interested sockets via reverse index
    get_sockets_for_sensor(sensor_id)
    |> Enum.each(fn socket_id ->
      case :ets.lookup(@sockets_table, socket_id) do
        [{^socket_id, socket_state}] ->
          Enum.each(measurements, fn measurement ->
            attribute_id = Map.get(measurement, :attribute_id)
            buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement)
          end)

        [] ->
          :ok
      end
    end)

    {:noreply, state}
  end

  # Flush timer for a specific socket
  @impl true
  def handle_info({:flush, socket_id}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        config = @quality_configs[socket_state.quality]
        flush_for_socket(socket_id, socket_state, config)

        # Reschedule
        new_timer = schedule_flush(socket_id, config.flush_interval_ms)
        updated = %{socket_state | timer_ref: new_timer}
        :ets.insert(@sockets_table, {socket_id, updated})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # Handle LiveView process death - auto-cleanup socket state
  @impl true
  def handle_info({:DOWN, _ref, :process, dead_pid, _reason}, state) do
    # Find and clean up any sockets owned by the dead process
    dead_count = cleanup_sockets_for_pid(dead_pid)

    # Unregister from Router if no more sockets
    state =
      if dead_count > 0 do
        Logger.debug(
          "PriorityLens: cleaned up #{dead_count} socket(s) for dead process #{inspect(dead_pid)}"
        )

        maybe_unregister_from_router(state)
      else
        state
      end

    {:noreply, state}
  end

  # Periodic cleanup of orphaned sockets (fallback for edge cases)
  @impl true
  def handle_info(:gc_dead_sockets, state) do
    dead_count = gc_dead_sockets()

    state =
      if dead_count > 0 do
        Logger.info("PriorityLens: GC cleaned up #{dead_count} orphaned socket(s)")
        maybe_unregister_from_router(state)
      else
        state
      end

    schedule_gc()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.registered_with_router do
      Sensocto.Lenses.Router.unregister_lens(self())
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Get all socket_ids subscribed to a sensor (O(1) lookup)
  defp get_sockets_for_sensor(sensor_id) do
    case :ets.lookup(@sensor_subs_table, sensor_id) do
      [{^sensor_id, socket_ids}] -> MapSet.to_list(socket_ids)
      [] -> []
    end
  end

  # Update the reverse index when a socket's sensor subscriptions change
  defp update_sensor_subscriptions(socket_id, old_sensors, new_sensors) do
    # Remove socket from sensors it's no longer subscribed to
    removed = MapSet.difference(old_sensors, new_sensors)

    Enum.each(removed, fn sensor_id ->
      case :ets.lookup(@sensor_subs_table, sensor_id) do
        [{^sensor_id, socket_ids}] ->
          updated = MapSet.delete(socket_ids, socket_id)

          if MapSet.size(updated) == 0 do
            :ets.delete(@sensor_subs_table, sensor_id)
          else
            :ets.insert(@sensor_subs_table, {sensor_id, updated})
          end

        [] ->
          :ok
      end
    end)

    # Add socket to sensors it's newly subscribed to
    added = MapSet.difference(new_sensors, old_sensors)

    Enum.each(added, fn sensor_id ->
      case :ets.lookup(@sensor_subs_table, sensor_id) do
        [{^sensor_id, socket_ids}] ->
          updated = MapSet.put(socket_ids, socket_id)
          :ets.insert(@sensor_subs_table, {sensor_id, updated})

        [] ->
          :ets.insert(@sensor_subs_table, {sensor_id, MapSet.new([socket_id])})
      end
    end)
  end

  defp buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement) do
    config = @quality_configs[socket_state.quality]
    key = {socket_id, sensor_id, attribute_id}

    case config.mode do
      :paused ->
        # Don't buffer anything when paused - save CPU and memory
        :ok

      :batch ->
        # For high-frequency attributes, accumulate in a list
        if attribute_id in @high_frequency_attributes do
          case :ets.lookup(@buffer_table, key) do
            [{^key, existing}] when is_list(existing) ->
              :ets.insert(@buffer_table, {key, existing ++ [measurement]})

            [{^key, existing}] ->
              :ets.insert(@buffer_table, {key, [existing, measurement]})

            [] ->
              :ets.insert(@buffer_table, {key, [measurement]})
          end
        else
          # Keep latest only
          :ets.insert(@buffer_table, {key, measurement})
        end

      :digest ->
        accumulate_for_digest(key, measurement)
    end
  end

  defp accumulate_for_digest(key, measurement) do
    payload = measurement.payload
    timestamp = measurement.timestamp || 0

    current =
      case :ets.lookup(@digest_table, key) do
        [{^key, acc}] -> acc
        [] -> %{count: 0, sum: 0, min: nil, max: nil, latest: nil, latest_timestamp: 0}
      end

    {new_sum, new_min, new_max} =
      if is_number(payload) do
        {
          current.sum + payload,
          if(current.min, do: min(current.min, payload), else: payload),
          if(current.max, do: max(current.max, payload), else: payload)
        }
      else
        {current.sum, current.min, current.max}
      end

    updated =
      if timestamp >= current.latest_timestamp do
        %{
          count: current.count + 1,
          sum: new_sum,
          min: new_min,
          max: new_max,
          latest: payload,
          latest_timestamp: timestamp
        }
      else
        %{current | count: current.count + 1, sum: new_sum, min: new_min, max: new_max}
      end

    :ets.insert(@digest_table, {key, updated})
  end

  defp flush_for_socket(socket_id, socket_state, config) do
    case config.mode do
      :batch -> flush_batch(socket_id, socket_state)
      :digest -> flush_digest(socket_id, socket_state)
      # Paused mode - don't send any data, just clear buffers to prevent memory buildup
      :paused -> clear_buffers_for_socket(socket_id)
    end
  end

  # Clear buffers without sending - used in paused mode
  defp clear_buffers_for_socket(socket_id) do
    pattern = {{socket_id, :_, :_}, :_}
    :ets.match_delete(@buffer_table, pattern)
    :ets.match_delete(@digest_table, pattern)
  end

  defp flush_batch(socket_id, socket_state) do
    config = @quality_configs[socket_state.quality]
    max_sensors = config.max_sensors

    # Use match to get all entries for this socket
    pattern = {{socket_id, :_, :_}, :_}
    entries = :ets.match_object(@buffer_table, pattern)

    if length(entries) > 0 do
      # Group by sensor_id first
      by_sensor =
        entries
        |> Enum.group_by(fn {{_sid, sensor_id, _attr_id}, _m} -> sensor_id end)

      # Apply max_sensors limit (focused sensor always included)
      sensors_to_include =
        case max_sensors do
          :unlimited ->
            Map.keys(by_sensor)

          limit when is_integer(limit) ->
            focused = socket_state.focused_sensor
            all_sensors = Map.keys(by_sensor)

            # Always include focused sensor if present
            {focused_list, other_sensors} =
              if focused && focused in all_sensors do
                {[focused], List.delete(all_sensors, focused)}
              else
                {[], all_sensors}
              end

            # Take remaining slots from other sensors
            remaining_slots = max(0, limit - length(focused_list))
            focused_list ++ Enum.take(other_sensors, remaining_slots)
        end

      # Build batch only with allowed sensors
      batch =
        sensors_to_include
        |> Enum.reduce(%{}, fn sensor_id, acc ->
          sensor_entries = Map.get(by_sensor, sensor_id, [])

          sensor_data =
            Enum.reduce(sensor_entries, %{}, fn {{_sid, _s_id, attr_id}, measurement}, s_acc ->
              Map.put(s_acc, attr_id, measurement)
            end)

          Map.put(acc, sensor_id, sensor_data)
        end)

      if map_size(batch) > 0 do
        Phoenix.PubSub.broadcast(
          Sensocto.PubSub,
          socket_state.topic,
          {:lens_batch, batch}
        )
      end

      # Clear ALL buffer entries for this socket (including dropped sensors)
      :ets.match_delete(@buffer_table, pattern)
    end
  end

  defp flush_digest(socket_id, socket_state) do
    pattern = {{socket_id, :_, :_}, :_}
    entries = :ets.match_object(@digest_table, pattern)

    if length(entries) > 0 do
      digests =
        entries
        |> Enum.reduce(%{}, fn {{_sid, sensor_id, attribute_id}, acc}, result ->
          avg = if acc.count > 0 and is_number(acc.sum), do: acc.sum / acc.count, else: nil

          attr_digest = %{
            count: acc.count,
            avg: avg,
            min: acc.min,
            max: acc.max,
            latest: acc.latest
          }

          sensor_data = Map.get(result, sensor_id, %{})
          updated_sensor = Map.put(sensor_data, attribute_id, attr_digest)
          Map.put(result, sensor_id, updated_sensor)
        end)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        socket_state.topic,
        {:lens_digest, digests}
      )

      # Clear digest entries for this socket
      :ets.match_delete(@digest_table, pattern)
    end
  end

  # Register with Router if not already registered and there are sockets
  defp maybe_register_with_router(%{registered_with_router: true} = state), do: state

  defp maybe_register_with_router(state) do
    if :ets.info(@sockets_table, :size) > 0 do
      Sensocto.Lenses.Router.register_lens(self())
      Logger.info("PriorityLens: registered with Router (first socket connected)")
      %{state | registered_with_router: true}
    else
      state
    end
  end

  # Unregister from Router if registered and no more sockets
  defp maybe_unregister_from_router(%{registered_with_router: false} = state), do: state

  defp maybe_unregister_from_router(state) do
    if :ets.info(@sockets_table, :size) == 0 do
      Sensocto.Lenses.Router.unregister_lens(self())
      Logger.info("PriorityLens: unregistered from Router (no more sockets)")
      %{state | registered_with_router: false}
    else
      state
    end
  end

  defp schedule_flush(_socket_id, :infinity) do
    # Paused mode - don't schedule any flush
    nil
  end

  defp schedule_flush(socket_id, interval_ms) do
    Process.send_after(self(), {:flush, socket_id}, interval_ms)
  end

  defp schedule_gc do
    Process.send_after(self(), :gc_dead_sockets, @gc_interval_ms)
  end

  # Clean up all sockets owned by a specific PID (called on :DOWN)
  defp cleanup_sockets_for_pid(dead_pid) do
    :ets.tab2list(@sockets_table)
    |> Enum.reduce(0, fn {socket_id, socket_state}, count ->
      if Map.get(socket_state, :owner_pid) == dead_pid do
        cleanup_socket(socket_id, socket_state)
        count + 1
      else
        count
      end
    end)
  end

  # Periodic GC: clean up sockets whose owner process is no longer alive
  # This is a fallback for edge cases where :DOWN message might be missed
  defp gc_dead_sockets do
    :ets.tab2list(@sockets_table)
    |> Enum.reduce(0, fn {socket_id, socket_state}, count ->
      owner_pid = Map.get(socket_state, :owner_pid)

      # Check if owner process is still alive
      if owner_pid && not Process.alive?(owner_pid) do
        cleanup_socket(socket_id, socket_state)
        count + 1
      else
        count
      end
    end)
  end

  # Helper to clean up a single socket's state
  defp cleanup_socket(socket_id, socket_state) do
    if socket_state.timer_ref, do: Process.cancel_timer(socket_state.timer_ref)

    if Map.get(socket_state, :monitor_ref),
      do: Process.demonitor(socket_state.monitor_ref, [:flush])

    :ets.match_delete(@buffer_table, {{socket_id, :_, :_}, :_})
    :ets.match_delete(@digest_table, {{socket_id, :_, :_}, :_})
    :ets.delete(@sockets_table, socket_id)
  end
end
