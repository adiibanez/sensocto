defmodule Sensocto.Simulator.ConnectorServer do
  @moduledoc """
  Manages a simulated connector and its sensors.
  Instead of WebSocket connections, directly creates sensors via SensorsDynamicSupervisor.
  """

  use GenServer
  require Logger
  alias Sensocto.Types.SafeKeys

  defmodule State do
    defstruct [
      :connector_id,
      :connector_name,
      :room_id,
      :sensors_config,
      :sensor_pids,
      :supervisor
    ]
  end

  def start_link(config) when is_map(config) do
    config = %{
      connector_id: config["connector_id"],
      connector_name: config["connector_name"] || "Sim_#{config["connector_id"]}",
      room_id: config["room_id"],
      sensors: config["sensors"] || %{}
    }

    Logger.debug(
      "ConnectorServer start_link: #{config.connector_id}" <>
        if(config.room_id, do: " (room: #{config.room_id})", else: "")
    )

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
      room_id: config.room_id,
      sensors_config: config.sensors,
      sensor_pids: %{},
      supervisor: supervisor
    }

    {:ok, state, {:continue, :setup_sensors}}
  end

  @impl true
  def handle_continue(:setup_sensors, %{sensors_config: sensors} = state) do
    Logger.debug("Setting up #{map_size(sensors)} sensors for connector #{state.connector_id}")

    new_state =
      Enum.reduce(sensors, state, fn {sensor_id, sensor_config}, acc ->
        start_sensor(acc, sensor_id, sensor_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_config, _new_config}, state) do
    Logger.debug("Updating connector config: #{state.connector_id}")
    # TODO: Implement config update logic (stop/start changed sensors)
    {:noreply, state}
  end

  @impl true
  def handle_info({:sensor_stopped, sensor_id}, state) do
    Logger.debug("Sensor stopped: #{sensor_id}")
    new_pids = Map.delete(state.sensor_pids, sensor_id)
    {:noreply, %{state | sensor_pids: new_pids}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("ConnectorServer terminating: #{state.connector_id}, reason: #{inspect(reason)}")

    # Terminate all sensor children in PARALLEL to avoid exceeding the 5s shutdown timeout.
    # With 10+ sensors terminated sequentially, each taking ~500ms, we'd exceed the timeout
    # and get :killed — causing SensorServer.terminate callbacks to never run.
    if state.supervisor do
      children =
        DynamicSupervisor.which_children(state.supervisor)
        |> Enum.filter(fn {_, pid, _, _} -> is_pid(pid) and Process.alive?(pid) end)

      tasks =
        Enum.map(children, fn {_, pid, _, _} ->
          Task.async(fn ->
            DynamicSupervisor.terminate_child(state.supervisor, pid)
          end)
        end)

      # Wait up to 4s for all sensors to terminate (leaves margin within 5s shutdown)
      Task.yield_many(tasks, 4_000)
      |> Enum.each(fn {task, result} ->
        if result == nil, do: Task.shutdown(task, :brutal_kill)
      end)
    end

    :ok
  end

  defp start_sensor(state, sensor_id, sensor_config) do
    sensor_config = string_keys_to_atom_keys(sensor_config)

    # Add "Sim_" prefix to sensor name as per requirement
    sensor_name = sensor_config[:sensor_name] || sensor_id
    prefixed_sensor_name = "Sim_#{sensor_name}"

    config =
      Map.merge(sensor_config, %{
        sensor_id: sensor_id,
        sensor_name: prefixed_sensor_name,
        connector_id: state.connector_id,
        connector_name: state.connector_name,
        connector_pid: self(),
        room_id: state.room_id
      })

    Logger.debug("Starting simulator sensor: #{sensor_id} (#{prefixed_sensor_name})")

    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.SensorServer, config}
         ) do
      {:ok, pid} ->
        Logger.debug("Started simulator sensor #{sensor_id}")
        %{state | sensor_pids: Map.put(state.sensor_pids, sensor_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start sensor #{sensor_id}: #{inspect(reason)}")
        state
    end
  end

  defp via_tuple(connector_id) do
    {:via, Registry, {Sensocto.Simulator.Registry, "connector_#{connector_id}"}}
  end

  # Whitelist of allowed keys from simulator YAML configs
  # This prevents atom table exhaustion from malicious/large configs
  # Safe conversion using SafeKeys whitelist to prevent atom exhaustion
  defp string_keys_to_atom_keys(map) when is_map(map) do
    {:ok, converted} = SafeKeys.safe_keys_to_atoms(map)
    converted
  end

  defp string_keys_to_atom_keys(value), do: value
end
