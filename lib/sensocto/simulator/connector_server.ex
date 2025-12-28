defmodule Sensocto.Simulator.ConnectorServer do
  @moduledoc """
  Manages a simulated connector and its sensors.
  Instead of WebSocket connections, directly creates sensors via SensorsDynamicSupervisor.
  """

  use GenServer
  require Logger

  defmodule State do
    defstruct [
      :connector_id,
      :connector_name,
      :sensors_config,
      :sensor_pids,
      :supervisor
    ]
  end

  def start_link(config) when is_map(config) do
    config = %{
      connector_id: config["connector_id"],
      connector_name: config["connector_name"] || "Sim_#{config["connector_id"]}",
      sensors: config["sensors"] || %{}
    }

    Logger.info("ConnectorServer start_link: #{config.connector_id}")

    GenServer.start_link(__MODULE__, config, name: via_tuple(config.connector_id))
  end

  @impl true
  def init(config) do
    # Trap exits so terminate/2 is called when process is stopped
    Process.flag(:trap_exit, true)

    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      connector_id: config.connector_id,
      connector_name: config.connector_name,
      sensors_config: config.sensors,
      sensor_pids: %{},
      supervisor: supervisor
    }

    {:ok, state, {:continue, :setup_sensors}}
  end

  @impl true
  def handle_continue(:setup_sensors, %{sensors_config: sensors} = state) do
    Logger.info("Setting up #{map_size(sensors)} sensors for connector #{state.connector_id}")

    new_state =
      Enum.reduce(sensors, state, fn {sensor_id, sensor_config}, acc ->
        start_sensor(acc, sensor_id, sensor_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_config, new_config}, state) do
    Logger.info("Updating connector config: #{state.connector_id}")
    # TODO: Implement config update logic (stop/start changed sensors)
    {:noreply, state}
  end

  @impl true
  def handle_info({:sensor_stopped, sensor_id}, state) do
    Logger.info("Sensor stopped: #{sensor_id}")
    new_pids = Map.delete(state.sensor_pids, sensor_id)
    {:noreply, %{state | sensor_pids: new_pids}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ConnectorServer terminating: #{state.connector_id}, reason: #{inspect(reason)}")

    # Explicitly terminate all sensor children to ensure their terminate callbacks run
    if state.supervisor do
      DynamicSupervisor.which_children(state.supervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        if is_pid(pid) and Process.alive?(pid) do
          DynamicSupervisor.terminate_child(state.supervisor, pid)
        end
      end)
    end

    :ok
  end

  defp start_sensor(state, sensor_id, sensor_config) do
    sensor_config = string_keys_to_atom_keys(sensor_config)

    # Add "Sim_" prefix to sensor name as per requirement
    sensor_name = sensor_config[:sensor_name] || sensor_id
    prefixed_sensor_name = "Sim_#{sensor_name}"

    config = Map.merge(sensor_config, %{
      sensor_id: sensor_id,
      sensor_name: prefixed_sensor_name,
      connector_id: state.connector_id,
      connector_name: state.connector_name,
      connector_pid: self()
    })

    Logger.info("Starting simulator sensor: #{sensor_id} (#{prefixed_sensor_name})")

    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.SensorServer, config}
         ) do
      {:ok, pid} ->
        Logger.info("Started simulator sensor #{sensor_id}")
        %{state | sensor_pids: Map.put(state.sensor_pids, sensor_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start sensor #{sensor_id}: #{inspect(reason)}")
        state
    end
  end

  defp via_tuple(connector_id) do
    {:via, Registry, {Sensocto.Simulator.Registry, "connector_#{connector_id}"}}
  end

  defp string_keys_to_atom_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), string_keys_to_atom_keys(v)}
      {k, v} -> {k, string_keys_to_atom_keys(v)}
    end)
  end

  defp string_keys_to_atom_keys(value), do: value
end
