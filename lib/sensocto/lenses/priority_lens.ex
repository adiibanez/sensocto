defmodule Sensocto.Lenses.PriorityLens do
  @moduledoc """
  Adaptive data lens that adjusts fidelity based on sensor attention level
  and per-socket client health.

  Each connected socket registers with the PriorityLens, specifying which
  sensors it cares about and its current quality level. The lens then
  delivers appropriately throttled data to each socket.

  ## Quality Levels

  - `:high` - 20Hz throttled, full sensor set
  - `:medium` - 10Hz throttled, limited sensors
  - `:low` - 1s digests (summary stats), few sensors
  - `:minimal` - Alerts only, single focused sensor

  ## Topics

  Per-socket: `"lens:priority:{socket_id}"` - personalized stream

  ## Message Format

  Quality-dependent:
  - `:high/:medium` - `{:lens_batch, batch_data}`
  - `:low` - `{:lens_digest, sensor_id, stats}`
  - `:minimal` - `{:lens_alert, sensor_id, alert}` (not yet implemented)

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

  # Quality level configurations
  @quality_configs %{
    high: %{
      flush_interval_ms: 50,
      max_sensors: :unlimited,
      mode: :batch
    },
    medium: %{
      flush_interval_ms: 100,
      max_sensors: 10,
      mode: :batch
    },
    low: %{
      flush_interval_ms: 1000,
      max_sensors: 5,
      mode: :digest
    },
    minimal: %{
      flush_interval_ms: 2000,
      max_sensors: 1,
      mode: :digest
    }
  }

  # High-frequency attributes that need all samples preserved (not just latest)
  # These are waveform data types that require continuous sampling for proper visualization
  @high_frequency_attributes ~w(ecg)

  defstruct [
    :sockets,
    :buffers,
    :digest_accumulators
  ]

  # Socket registration state
  defmodule SocketState do
    @moduledoc false
    defstruct [
      :socket_id,
      :sensor_ids,
      :quality,
      :focused_sensor,
      :flush_timer,
      :topic
    ]
  end

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a socket to receive priority-filtered data.

  - `socket_id` - Unique identifier for this socket (typically socket.id)
  - `sensor_ids` - List of sensor IDs this socket is interested in
  - `opts` - Options:
    - `:quality` - Initial quality level (default: :high)
    - `:focused_sensor` - Sensor to prioritize (optional)

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
    GenServer.call(__MODULE__, {:get_socket_state, socket_id})
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
    # Register with router
    Sensocto.Lenses.Router.register_lens(self())

    Logger.info("PriorityLens started")

    {:ok,
     %__MODULE__{
       sockets: %{},
       buffers: %{},
       digest_accumulators: %{}
     }}
  end

  @impl true
  def handle_call(
        {:register_socket, socket_id, sensor_ids, quality, focused_sensor},
        _from,
        state
      ) do
    topic = topic_for_socket(socket_id)
    config = @quality_configs[quality]

    socket_state = %SocketState{
      socket_id: socket_id,
      sensor_ids: MapSet.new(sensor_ids),
      quality: quality,
      focused_sensor: focused_sensor,
      flush_timer: schedule_flush(socket_id, config.flush_interval_ms),
      topic: topic
    }

    new_sockets = Map.put(state.sockets, socket_id, socket_state)
    new_buffers = Map.put(state.buffers, socket_id, %{})
    new_accumulators = Map.put(state.digest_accumulators, socket_id, %{})

    Logger.debug("PriorityLens: registered socket #{socket_id} with quality #{quality}")

    {:reply, {:ok, topic},
     %{state | sockets: new_sockets, buffers: new_buffers, digest_accumulators: new_accumulators}}
  end

  @impl true
  def handle_call({:get_socket_state, socket_id}, _from, state) do
    {:reply, Map.get(state.sockets, socket_id), state}
  end

  @impl true
  def handle_cast({:unregister_socket, socket_id}, state) do
    case Map.get(state.sockets, socket_id) do
      nil ->
        {:noreply, state}

      socket_state ->
        # Cancel flush timer
        if socket_state.flush_timer do
          Process.cancel_timer(socket_state.flush_timer)
        end

        new_sockets = Map.delete(state.sockets, socket_id)
        new_buffers = Map.delete(state.buffers, socket_id)
        new_accumulators = Map.delete(state.digest_accumulators, socket_id)

        Logger.debug("PriorityLens: unregistered socket #{socket_id}")

        {:noreply,
         %{
           state
           | sockets: new_sockets,
             buffers: new_buffers,
             digest_accumulators: new_accumulators
         }}
    end
  end

  @impl true
  def handle_cast({:set_quality, socket_id, quality}, state) do
    case Map.get(state.sockets, socket_id) do
      nil ->
        {:noreply, state}

      socket_state ->
        # Cancel old timer
        if socket_state.flush_timer do
          Process.cancel_timer(socket_state.flush_timer)
        end

        config = @quality_configs[quality]
        new_timer = schedule_flush(socket_id, config.flush_interval_ms)

        updated_socket = %{socket_state | quality: quality, flush_timer: new_timer}
        new_sockets = Map.put(state.sockets, socket_id, updated_socket)

        Logger.debug("PriorityLens: socket #{socket_id} quality changed to #{quality}")

        {:noreply, %{state | sockets: new_sockets}}
    end
  end

  @impl true
  def handle_cast({:set_sensors, socket_id, sensor_ids}, state) do
    case Map.get(state.sockets, socket_id) do
      nil ->
        {:noreply, state}

      socket_state ->
        updated_socket = %{socket_state | sensor_ids: MapSet.new(sensor_ids)}
        new_sockets = Map.put(state.sockets, socket_id, updated_socket)

        {:noreply, %{state | sockets: new_sockets}}
    end
  end

  @impl true
  def handle_cast({:set_focused_sensor, socket_id, sensor_id}, state) do
    case Map.get(state.sockets, socket_id) do
      nil ->
        {:noreply, state}

      socket_state ->
        updated_socket = %{socket_state | focused_sensor: sensor_id}
        new_sockets = Map.put(state.sockets, socket_id, updated_socket)

        {:noreply, %{state | sockets: new_sockets}}
    end
  end

  # Single measurement from router
  @impl true
  def handle_info({:router_measurement, sensor_id, measurement}, state) do
    attribute_id = Map.get(measurement, :attribute_id)

    # Buffer for each interested socket
    new_state =
      Enum.reduce(state.sockets, state, fn {socket_id, socket_state}, acc_state ->
        if should_receive?(socket_state, sensor_id) do
          buffer_measurement(acc_state, socket_id, sensor_id, attribute_id, measurement)
        else
          acc_state
        end
      end)

    {:noreply, new_state}
  end

  # Batch measurements from router
  @impl true
  def handle_info({:router_measurements_batch, sensor_id, measurements}, state) do
    # Buffer for each interested socket
    new_state =
      Enum.reduce(state.sockets, state, fn {socket_id, socket_state}, acc_state ->
        if should_receive?(socket_state, sensor_id) do
          buffer_batch(acc_state, socket_id, sensor_id, measurements)
        else
          acc_state
        end
      end)

    {:noreply, new_state}
  end

  # Flush timer for a specific socket
  @impl true
  def handle_info({:flush, socket_id}, state) do
    case Map.get(state.sockets, socket_id) do
      nil ->
        {:noreply, state}

      socket_state ->
        config = @quality_configs[socket_state.quality]
        new_state = flush_for_socket(state, socket_id, socket_state, config)

        # Reschedule
        new_timer = schedule_flush(socket_id, config.flush_interval_ms)
        updated_socket = %{socket_state | flush_timer: new_timer}
        new_sockets = Map.put(new_state.sockets, socket_id, updated_socket)

        {:noreply, %{new_state | sockets: new_sockets}}
    end
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
    # Always receive focused sensor
    socket_state.focused_sensor == sensor_id or
      MapSet.member?(socket_state.sensor_ids, sensor_id)
  end

  defp buffer_measurement(state, socket_id, sensor_id, attribute_id, measurement) do
    socket_state = Map.get(state.sockets, socket_id)
    config = @quality_configs[socket_state.quality]

    case config.mode do
      :batch ->
        buffer = Map.get(state.buffers, socket_id, %{})
        sensor_buffer = Map.get(buffer, sensor_id, %{})

        # For high-frequency attributes (like ECG), accumulate all samples in a list
        # For other attributes, just keep the latest value
        updated_sensor_buffer =
          if attribute_id in @high_frequency_attributes do
            existing = Map.get(sensor_buffer, attribute_id, [])
            # Store as list of measurements
            measurements_list =
              case existing do
                list when is_list(list) -> list ++ [measurement]
                single_measurement -> [single_measurement, measurement]
              end

            Map.put(sensor_buffer, attribute_id, measurements_list)
          else
            Map.put(sensor_buffer, attribute_id, measurement)
          end

        new_buffer = Map.put(buffer, sensor_id, updated_sensor_buffer)
        %{state | buffers: Map.put(state.buffers, socket_id, new_buffer)}

      :digest ->
        accumulate_for_digest(state, socket_id, sensor_id, attribute_id, measurement)
    end
  end

  defp buffer_batch(state, socket_id, sensor_id, measurements) do
    Enum.reduce(measurements, state, fn measurement, acc_state ->
      attribute_id = Map.get(measurement, :attribute_id)
      buffer_measurement(acc_state, socket_id, sensor_id, attribute_id, measurement)
    end)
  end

  defp accumulate_for_digest(state, socket_id, sensor_id, attribute_id, measurement) do
    accumulators = Map.get(state.digest_accumulators, socket_id, %{})
    key = {sensor_id, attribute_id}

    current =
      Map.get(accumulators, key, %{
        count: 0,
        sum: 0,
        min: nil,
        max: nil,
        latest: nil,
        latest_timestamp: 0
      })

    payload = measurement.payload
    timestamp = measurement.timestamp || 0

    # Only accumulate numeric payloads
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

    new_accumulators = Map.put(accumulators, key, updated)

    %{
      state
      | digest_accumulators: Map.put(state.digest_accumulators, socket_id, new_accumulators)
    }
  end

  defp flush_for_socket(state, socket_id, socket_state, config) do
    case config.mode do
      :batch ->
        flush_batch(state, socket_id, socket_state)

      :digest ->
        flush_digest(state, socket_id, socket_state)
    end
  end

  defp flush_batch(state, socket_id, socket_state) do
    buffer = Map.get(state.buffers, socket_id, %{})

    if map_size(buffer) > 0 do
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        socket_state.topic,
        {:lens_batch, buffer}
      )
    end

    %{state | buffers: Map.put(state.buffers, socket_id, %{})}
  end

  defp flush_digest(state, socket_id, socket_state) do
    accumulators = Map.get(state.digest_accumulators, socket_id, %{})

    if map_size(accumulators) > 0 do
      # Group by sensor_id
      digests =
        accumulators
        |> Enum.group_by(fn {{sensor_id, _attr_id}, _acc} -> sensor_id end)
        |> Enum.map(fn {sensor_id, entries} ->
          attrs =
            Enum.into(entries, %{}, fn {{_sid, attr_id}, acc} ->
              avg = if acc.count > 0 and is_number(acc.sum), do: acc.sum / acc.count, else: nil

              {attr_id,
               %{
                 count: acc.count,
                 avg: avg,
                 min: acc.min,
                 max: acc.max,
                 latest: acc.latest
               }}
            end)

          {sensor_id, attrs}
        end)
        |> Enum.into(%{})

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        socket_state.topic,
        {:lens_digest, digests}
      )
    end

    %{state | digest_accumulators: Map.put(state.digest_accumulators, socket_id, %{})}
  end

  defp schedule_flush(socket_id, interval_ms) do
    Process.send_after(self(), {:flush, socket_id}, interval_ms)
  end
end
