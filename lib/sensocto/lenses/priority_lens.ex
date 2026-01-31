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

  # Quality level configurations
  # Philosophy: Default to maximum throughput. Throttling is a last resort.
  @quality_configs %{
    # Maximum throughput - flush as fast as possible (~60fps)
    high: %{flush_interval_ms: 16, max_sensors: :unlimited, mode: :batch},
    # Still realtime, slightly batched (~20fps)
    medium: %{flush_interval_ms: 50, max_sensors: :unlimited, mode: :batch},
    # First level of throttling - only when there's real backpressure
    low: %{flush_interval_ms: 100, max_sensors: 20, mode: :batch},
    # Emergency mode - significant throttling
    minimal: %{flush_interval_ms: 200, max_sensors: 5, mode: :batch}
  }

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
  def set_quality(socket_id, quality) when quality in [:high, :medium, :low, :minimal] do
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

    # Register with router
    Sensocto.Lenses.Router.register_lens(self())

    # Schedule periodic dead socket cleanup
    schedule_gc()

    Logger.info("PriorityLens started with ETS buffering")

    {:ok, %{}}
  end

  @impl true
  def handle_call(
        {:register_socket, socket_id, sensor_ids, quality, focused_sensor},
        {caller_pid, _},
        state
      ) do
    topic = topic_for_socket(socket_id)
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

    Logger.debug("PriorityLens: registered socket #{socket_id} with quality #{quality}")

    {:reply, {:ok, topic}, state}
  end

  @impl true
  def handle_cast({:unregister_socket, socket_id}, state) do
    case :ets.lookup(@sockets_table, socket_id) do
      [{^socket_id, socket_state}] ->
        # Cancel timer
        if socket_state.timer_ref, do: Process.cancel_timer(socket_state.timer_ref)

        # Clean up all ETS entries for this socket
        :ets.match_delete(@buffer_table, {{socket_id, :_, :_}, :_})
        :ets.match_delete(@digest_table, {{socket_id, :_, :_}, :_})
        :ets.delete(@sockets_table, socket_id)

        Logger.debug("PriorityLens: unregistered socket #{socket_id}")

      [] ->
        :ok
    end

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
        updated = %{socket_state | sensor_ids: MapSet.new(sensor_ids)}
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

    # Get all registered sockets and buffer for interested ones
    :ets.tab2list(@sockets_table)
    |> Enum.each(fn {socket_id, socket_state} ->
      if should_receive?(socket_state, sensor_id) do
        buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement)
      end
    end)

    {:noreply, state}
  end

  # Batch measurements from router
  @impl true
  def handle_info({:router_measurements_batch, sensor_id, measurements}, state) do
    :ets.tab2list(@sockets_table)
    |> Enum.each(fn {socket_id, socket_state} ->
      if should_receive?(socket_state, sensor_id) do
        Enum.each(measurements, fn measurement ->
          attribute_id = Map.get(measurement, :attribute_id)
          buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement)
        end)
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

    if dead_count > 0 do
      Logger.debug(
        "PriorityLens: cleaned up #{dead_count} socket(s) for dead process #{inspect(dead_pid)}"
      )
    end

    {:noreply, state}
  end

  # Periodic cleanup of orphaned sockets (fallback for edge cases)
  @impl true
  def handle_info(:gc_dead_sockets, state) do
    dead_count = gc_dead_sockets()

    if dead_count > 0 do
      Logger.info("PriorityLens: GC cleaned up #{dead_count} orphaned socket(s)")
    end

    schedule_gc()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Sensocto.Lenses.Router.unregister_lens(self())
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp should_receive?(socket_state, sensor_id) do
    socket_state.focused_sensor == sensor_id or
      MapSet.member?(socket_state.sensor_ids, sensor_id)
  end

  defp buffer_measurement(socket_id, socket_state, sensor_id, attribute_id, measurement) do
    config = @quality_configs[socket_state.quality]
    key = {socket_id, sensor_id, attribute_id}

    case config.mode do
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
    end
  end

  defp flush_batch(socket_id, socket_state) do
    # Use match to get all entries for this socket
    pattern = {{socket_id, :_, :_}, :_}
    entries = :ets.match_object(@buffer_table, pattern)

    if length(entries) > 0 do
      batch =
        entries
        |> Enum.reduce(%{}, fn {{_sid, sensor_id, attribute_id}, measurement}, acc ->
          sensor_data = Map.get(acc, sensor_id, %{})
          updated_sensor = Map.put(sensor_data, attribute_id, measurement)
          Map.put(acc, sensor_id, updated_sensor)
        end)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        socket_state.topic,
        {:lens_batch, batch}
      )

      # Clear buffer entries for this socket
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
