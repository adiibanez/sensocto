defmodule Sensocto.Simulator.SensorServer do
  @moduledoc """
  Manages a simulated sensor.
  Creates a real SimpleSensor via SensorsDynamicSupervisor and manages attribute data generation.
  """

  use GenServer
  require Logger
  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.SimpleSensor
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
      :real_sensor_started
    ]
  end

  def start_link(%{sensor_id: sensor_id, connector_id: connector_id} = config) do
    Logger.info("SensorServer start_link: #{connector_id}/#{sensor_id}")
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
      real_sensor_started: false
    }

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
        Logger.info("Created real sensor for simulator: #{state.sensor_id}")

        # Track presence so LiveViews see the new sensor immediately
        Presence.track(self(), "presence:all", state.sensor_id, %{
          sensor_id: state.sensor_id,
          online_at: System.system_time(:millisecond),
          source: :simulator
        })

        # Add sensor to room if room_id is specified
        if state.room_id do
          case Sensocto.RoomStore.add_sensor(state.room_id, state.sensor_id) do
            :ok ->
              Logger.info("Added sensor #{state.sensor_id} to room #{state.room_id}")

            {:error, reason} ->
              Logger.warning("Failed to add sensor #{state.sensor_id} to room #{state.room_id}: #{inspect(reason)}")
          end
        end

        new_state = %{state | real_sensor_started: true}
        {:noreply, new_state, {:continue, :setup_attributes}}

      {:error, reason} ->
        Logger.error("Failed to create real sensor #{state.sensor_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:setup_attributes, state) do
    Logger.info("Setting up #{map_size(state.attributes_config)} attributes for sensor #{state.sensor_id}")

    new_state =
      Enum.reduce(state.attributes_config, state, fn {attr_id, attr_config}, acc ->
        start_attribute(acc, attr_id, attr_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:push_batch, attribute_id, messages}, state) do
    Logger.debug("Pushing batch of #{length(messages)} messages for #{state.sensor_id}/#{attribute_id}")

    # Convert messages to format expected by SimpleSensor
    formatted_messages =
      Enum.map(messages, fn msg ->
        %{
          attribute_id: attribute_id,
          timestamp: msg["timestamp"] || msg[:timestamp],
          payload: msg["payload"] || msg[:payload]
        }
      end)

    if state.real_sensor_started do
      SimpleSensor.put_batch_attributes(state.sensor_id, formatted_messages)
    else
      Logger.warning("Real sensor not started yet for #{state.sensor_id}")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SensorServer terminating: #{state.sensor_id}, reason: #{inspect(reason)}")

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

    attr_config = Map.merge(config, %{
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
        Logger.info("Started attribute #{attribute_id} for sensor #{state.sensor_id}")
        %{state | attribute_pids: Map.put(state.attribute_pids, attribute_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start attribute #{attribute_id}: #{inspect(reason)}")
        state
    end
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sensocto.Simulator.Registry, "sensor_#{identifier}"}}
  end

  defp string_keys_to_atom_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), string_keys_to_atom_keys(v)}
      {k, v} -> {k, string_keys_to_atom_keys(v)}
    end)
  end

  defp string_keys_to_atom_keys(value), do: value
end
