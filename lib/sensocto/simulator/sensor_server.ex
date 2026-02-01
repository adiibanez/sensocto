defmodule Sensocto.Simulator.SensorServer do
  @moduledoc """
  Manages a simulated sensor.
  Creates a real SimpleSensor via SensorsDynamicSupervisor and manages attribute data generation.
  """

  use GenServer
  require Logger
  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.SimpleSensor
  alias Sensocto.Types.SafeKeys
  alias SensoctoWeb.Sensocto.Presence

  defmodule State do
    defstruct [
      :sensor_id,
      :sensor_name,
      :connector_id,
      :connector_name,
      :connector_pid,
      :room_id,
      :attributes_config,
      :attribute_pids,
      :supervisor,
      :real_sensor_started,
      # Tracks if sensor is currently in the room (for auto-reconnect)
      :room_connected
    ]
  end

  # Check room connection every 5 seconds
  @room_check_interval 5_000

  def start_link(%{sensor_id: sensor_id, connector_id: connector_id} = config) do
    Logger.debug("SensorServer start_link: #{connector_id}/#{sensor_id}")
    GenServer.start_link(__MODULE__, config, name: via_tuple("#{connector_id}_#{sensor_id}"))
  end

  @impl true
  def init(config) do
    # Trap exits so terminate/2 is called when process is stopped
    Process.flag(:trap_exit, true)

    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sensor_id: config.sensor_id,
      sensor_name: config.sensor_name,
      connector_id: config.connector_id,
      connector_name: config.connector_name,
      connector_pid: config[:connector_pid],
      room_id: config[:room_id],
      attributes_config: config[:attributes] || %{},
      attribute_pids: %{},
      supervisor: supervisor,
      real_sensor_started: false,
      room_connected: false
    }

    # Subscribe to room events if room_id is specified
    if config[:room_id] do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{config[:room_id]}")
    end

    {:ok, state, {:continue, :create_real_sensor}}
  end

  @impl true
  def handle_continue(:create_real_sensor, state) do
    # Build attributes map for the real sensor
    attributes =
      Enum.reduce(state.attributes_config, %{}, fn {attr_id, attr_config}, acc ->
        attr_config = string_keys_to_atom_keys(attr_config)

        Map.put(acc, attr_id, %{
          attribute_id: attr_id,
          sampling_rate: attr_config[:sampling_rate] || 1,
          attribute_type: attr_config[:sensor_type] || "simulator"
        })
      end)

    # Configuration for the real SimpleSensor
    sensor_config = %{
      sensor_id: state.sensor_id,
      sensor_name: state.sensor_name,
      sensor_type: "simulator",
      connector_id: state.connector_id,
      connector_name: state.connector_name,
      sampling_rate: 1,
      batch_size: 1,
      attributes: attributes
    }

    case SensorsDynamicSupervisor.add_sensor(state.sensor_id, sensor_config) do
      {:ok, _} ->
        Logger.debug("Created real sensor for simulator: #{state.sensor_id}")

        # Track presence so LiveViews see the new sensor immediately
        Presence.track(self(), "presence:all", state.sensor_id, %{
          sensor_id: state.sensor_id,
          online_at: System.system_time(:millisecond),
          source: :simulator
        })

        # Add sensor to room if room_id is specified
        room_connected =
          if state.room_id do
            case Sensocto.RoomStore.add_sensor(state.room_id, state.sensor_id) do
              :ok ->
                Logger.debug("Added sensor #{state.sensor_id} to room #{state.room_id}")
                # Schedule periodic room connection check
                Process.send_after(self(), :check_room_connection, @room_check_interval)
                true

              {:error, reason} ->
                Logger.warning(
                  "Failed to add sensor #{state.sensor_id} to room #{state.room_id}: #{inspect(reason)}"
                )

                # Still schedule checks to retry connection
                Process.send_after(self(), :check_room_connection, @room_check_interval)
                false
            end
          else
            false
          end

        new_state = %{state | real_sensor_started: true, room_connected: room_connected}
        {:noreply, new_state, {:continue, :setup_attributes}}

      {:error, reason} ->
        Logger.error("Failed to create real sensor #{state.sensor_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:setup_attributes, state) do
    Logger.debug(
      "Setting up #{map_size(state.attributes_config)} attributes for sensor #{state.sensor_id}"
    )

    new_state =
      Enum.reduce(state.attributes_config, state, fn {attr_id, attr_config}, acc ->
        start_attribute(acc, attr_id, attr_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:push_batch, attribute_id, messages}, state) do
    Logger.debug(
      "Pushing batch of #{length(messages)} messages for #{state.sensor_id}/#{attribute_id}"
    )

    # Convert messages to format expected by SimpleSensor
    formatted_messages =
      Enum.map(messages, fn msg ->
        %{
          attribute_id: attribute_id,
          timestamp: msg["timestamp"] || msg[:timestamp],
          payload: msg["payload"] || msg[:payload]
        }
      end)

    cond do
      not state.real_sensor_started ->
        Logger.warning("Real sensor not started yet for #{state.sensor_id}")
        {:noreply, state}

      not SimpleSensor.alive?(state.sensor_id) ->
        # SimpleSensor is dead - log warning and attempt to re-create it
        Logger.warning(
          "SensorServer #{state.sensor_id}: SimpleSensor is not alive, scheduling restart"
        )

        # Mark as not started and schedule recreation
        Process.send_after(self(), :recreate_simple_sensor, 1_000)
        {:noreply, %{state | real_sensor_started: false}}

      true ->
        SimpleSensor.put_batch_attributes(state.sensor_id, formatted_messages)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:recreate_simple_sensor, %{real_sensor_started: false} = state) do
    Logger.debug("SensorServer #{state.sensor_id}: Attempting to recreate SimpleSensor")
    {:noreply, state, {:continue, :create_real_sensor}}
  end

  @impl true
  def handle_info(:recreate_simple_sensor, state) do
    # Already recreated
    {:noreply, state}
  end

  # Periodic room connection check - reconnects if sensor was removed from room
  @impl true
  def handle_info(:check_room_connection, %{room_id: nil} = state) do
    # No room assigned, nothing to check
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_room_connection, %{real_sensor_started: false} = state) do
    # Sensor not started yet, check again later
    Process.send_after(self(), :check_room_connection, @room_check_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_room_connection, state) do
    # Check if sensor is still in the room
    in_room = sensor_in_room?(state.room_id, state.sensor_id)

    new_state =
      cond do
        in_room and state.room_connected ->
          # Still connected, all good
          state

        in_room and not state.room_connected ->
          # Just reconnected (maybe room was recreated)
          Logger.debug("SensorServer #{state.sensor_id}: Reconnected to room #{state.room_id}")

          %{state | room_connected: true}

        not in_room and state.room_connected ->
          # Disconnected from room, try to reconnect
          Logger.warning(
            "SensorServer #{state.sensor_id}: Disconnected from room #{state.room_id}, attempting reconnect"
          )

          case Sensocto.RoomStore.add_sensor(state.room_id, state.sensor_id) do
            :ok ->
              Logger.debug(
                "SensorServer #{state.sensor_id}: Successfully reconnected to room #{state.room_id}"
              )

              %{state | room_connected: true}

            {:error, reason} ->
              Logger.warning(
                "SensorServer #{state.sensor_id}: Failed to reconnect to room #{state.room_id}: #{inspect(reason)}"
              )

              %{state | room_connected: false}
          end

        not in_room and not state.room_connected ->
          # Not connected, try to connect
          case Sensocto.RoomStore.add_sensor(state.room_id, state.sensor_id) do
            :ok ->
              Logger.debug("SensorServer #{state.sensor_id}: Connected to room #{state.room_id}")

              %{state | room_connected: true}

            {:error, _reason} ->
              # Still not connected, will retry
              state
          end
      end

    # Schedule next check
    Process.send_after(self(), :check_room_connection, @room_check_interval)
    {:noreply, new_state}
  end

  # Handle room sensor removal events (from PubSub)
  @impl true
  def handle_info({:sensor_removed, sensor_id}, %{sensor_id: sensor_id} = state) do
    Logger.warning(
      "SensorServer #{state.sensor_id}: Received sensor_removed event, will reconnect on next check"
    )

    {:noreply, %{state | room_connected: false}}
  end

  @impl true
  def handle_info({:sensor_removed, _other_sensor_id}, state) do
    # Ignore removal of other sensors
    {:noreply, state}
  end

  # Handle room deletion - sensor can no longer reconnect to this room
  @impl true
  def handle_info({:room_deleted, room_id}, %{room_id: room_id} = state) do
    Logger.warning(
      "SensorServer #{state.sensor_id}: Room #{room_id} was deleted, clearing room assignment"
    )

    {:noreply, %{state | room_connected: false}}
  end

  @impl true
  def handle_info({:room_deleted, _other_room_id}, state) do
    {:noreply, state}
  end

  # Catch-all for other PubSub messages from room topic
  @impl true
  def handle_info({room_event, _data}, state)
      when room_event in [:room_updated, :sensor_added, :presence_changed] do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("SensorServer terminating: #{state.sensor_id}, reason: #{inspect(reason)}")

    # Untrack presence so LiveViews see the sensor leave immediately
    if state.real_sensor_started do
      Presence.untrack(self(), "presence:all", state.sensor_id)
    end

    # Remove sensor from room if it was assigned
    # Use Map.get for backwards compatibility with old processes that may not have room_id
    room_id = Map.get(state, :room_id)

    if room_id && state.real_sensor_started do
      Sensocto.RoomStore.remove_sensor(room_id, state.sensor_id)
    end

    # Remove the real sensor when simulator sensor stops
    if state.real_sensor_started do
      SensorsDynamicSupervisor.remove_sensor(state.sensor_id)
    end

    # Notify connector
    if state.connector_pid do
      send(state.connector_pid, {:sensor_stopped, state.sensor_id})
    end

    :ok
  end

  defp start_attribute(state, attribute_id, config) do
    config = string_keys_to_atom_keys(config)

    attr_config =
      Map.merge(config, %{
        attribute_id: attribute_id,
        sensor_id: state.sensor_id,
        connector_id: state.connector_id,
        sensor_pid: self()
      })

    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.AttributeServer, attr_config}
         ) do
      {:ok, pid} ->
        Logger.debug("Started attribute #{attribute_id} for sensor #{state.sensor_id}")
        %{state | attribute_pids: Map.put(state.attribute_pids, attribute_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start attribute #{attribute_id}: #{inspect(reason)}")
        state
    end
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sensocto.Simulator.Registry, "sensor_#{identifier}"}}
  end

  # Check if sensor is currently in the room
  defp sensor_in_room?(room_id, sensor_id) do
    case Sensocto.RoomStore.get_room(room_id) do
      {:ok, room} ->
        MapSet.member?(room.sensor_ids || MapSet.new(), sensor_id)

      {:error, _} ->
        false
    end
  end

  # Safe conversion using SafeKeys whitelist to prevent atom exhaustion
  defp string_keys_to_atom_keys(map) when is_map(map) do
    {:ok, converted} = SafeKeys.safe_keys_to_atoms(map)
    # Recursively process nested maps that may have been kept as strings
    Map.new(converted, fn
      {k, v} when is_map(v) -> {k, string_keys_to_atom_keys(v)}
      {k, v} -> {k, v}
    end)
  end

  defp string_keys_to_atom_keys(value), do: value
end
