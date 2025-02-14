defmodule Sensocto.Simulator.Application do
  use Application
  require Logger
  require Config

  def start(_type, _args) do
    IO.puts("Start simulator")

    children = [
      # SensorSimulatorSupervisor,
      # %{id: :test, start: {Sensocto.BiosenseData.GenServer, :start_link, [1]}},
      %{id: :data_server_1, start: {Sensocto.BiosenseData.GenServer, :start_link, [1]}},
      %{id: :data_server_2, start: {Sensocto.BiosenseData.GenServer, :start_link, [2]}},
      %{id: :data_server_3, start: {Sensocto.BiosenseData.GenServer, :start_link, [3]}},
      %{id: :data_server_4, start: {Sensocto.BiosenseData.GenServer, :start_link, [4]}},
      %{id: :data_server_5, start: {Sensocto.BiosenseData.GenServer, :start_link, [5]}},
      # {Sensocto.BiosenseData.GenServer, [1], id: "biosense_data_server_1"},
      # {Sensocto.BiosenseData.GenServer, [2], id: "biosense_data_server_2"},
      # {Sensocto.BiosenseData.GenServer, [3], id: "biosense_data_server_3"},
      # {Sensocto.BiosenseData.GenServer, [4], id: "biosense_data_server_4"},
      # {Sensocto.BiosenseData.GenServer, [5], id: "biosense_data_server_5"},
      {Registry, keys: :unique, name: Sensocto.RegistryWorkers},
      {Registry, keys: :unique, name: SensorSimulatorRegistry},
      {Registry, keys: :unique, name: Sensocto.Registry},
      Sensocto.Simulator.Manager.ManagerSupervisor,
      {Sensocto.Simulator.Manager, "config/simulators.yaml"}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sensocto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def ensure_running_count(keep_running, ramp_up_delay, ramp_down_delay) do
    ensure_running_count(keep_running, ramp_up_delay, ramp_down_delay, nil)
  end

  def ensure_running_count(keep_running, ramp_up_delay, ramp_down_delay, config \\ nil) do
    sensor_type = get_in(config, [:sensor_type]) || "heartrate"
    current_children = SensorSimulatorSupervisor.get_children()

    # Get only the sensors of requested type
    current_type_sensors =
      current_children
      |> Enum.filter(fn {id, _pid, _type, _modules} ->
        String.ends_with?(to_string(id), ":#{sensor_type}")
      end)
      |> Enum.sort_by(fn {id, _pid, _type, _modules} -> to_string(id) end)

    processes_running = length(current_type_sensors)
    Logger.info("Current count for #{sensor_type}: #{processes_running}, target: #{keep_running}")

    # First stop excess sensors if needed
    result =
      if processes_running > keep_running do
        Logger.info(
          "Reducing #{sensor_type} sensors from #{processes_running} to #{keep_running}"
        )

        case stop_excess_sensors(current_type_sensors, keep_running, ramp_down_delay) do
          :ok -> {:ok, :stopped}
          error -> error
        end
      else
        :ok
      end

    # Then start new sensors if needed and previous operation was successful
    result =
      case result do
        :ok when processes_running < keep_running ->
          to_start = keep_running - processes_running

          Logger.info(
            "Increasing #{sensor_type} sensors from #{processes_running} to #{keep_running}"
          )

          start_additional_sensors(to_start, sensor_type, ramp_up_delay, config)

        other ->
          other
      end

    # Allow changes to propagate
    Process.sleep(100)
    {result, SensorSimulatorSupervisor.get_children()}
  end

  defp start_additional_sensors(count, sensor_type, ramp_up_delay, config) do
    Logger.info("Starting #{count} #{sensor_type} sensors")

    # Get current max sensor number for this type
    max_number =
      SensorSimulatorSupervisor.get_children()
      |> Enum.map(fn {id, _pid, _type, _modules} ->
        case Regex.run(~r/SensoctoSimEx_(\d+):#{sensor_type}/, to_string(id)) do
          [_, num] -> String.to_integer(num)
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    # Start new sensors with incremented numbers
    Enum.map(1..count, fn i ->
      number = max_number + i
      device_name = "SensoctoSimEx_#{number}"

      device_config = getconfig_for_device(device_name, config)

      case SensorSimulatorSupervisor.start_sensor(device_config) do
        {:ok, _pid} = result ->
          Logger.info("Started sensor #{device_name}")
          Process.sleep(ramp_up_delay)
          result

        {:error, reason} = error ->
          Logger.error("Failed to start sensor #{device_name}: #{inspect(reason)}")
          error
      end
    end)
  end

  defp stop_excess_sensors(current_sensors, keep_running, ramp_down_delay) do
    current_sensors
    # Keep first keep_running sensors, drop the rest
    |> Enum.drop(keep_running)
    |> tap(fn to_stop -> Logger.info("Stopping #{length(to_stop)} sensors") end)
    |> Enum.each(fn {id, pid, _type, _modules} ->
      Logger.info("Stopping sensor #{inspect(id)}")

      case DynamicSupervisor.terminate_child(SensorSimulatorSupervisor, pid) do
        :ok ->
          Logger.info("Successfully stopped #{inspect(id)}")
          Process.sleep(ramp_down_delay)

        {:error, reason} ->
          Logger.error("Failed to stop #{inspect(id)}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp getconfig_for_device(device_name, config) do
    IO.inspect(config, label: "config")

    merge_config = %{
      device_name: device_name,
      sensor_id: device_name,
      sensor_name: device_name,
      batch_size: 1,
      connector_id: "22222",
      connector_name: "SensoctoSim",
      sensor_type: "heartrate",
      duration: 30,
      sampling_rate: 1,
      heart_rate: 100,
      respiratory_rate: 30,
      scr_number: 5,
      burst_number: 5,
      batch_size: 100,
      batch_window: 500
    }

    IO.inspect(merge_config, label: "merge config")

    case config do
      nil ->
        merge_config
        |> IO.inspect(label: "result config")

      config ->
        Map.merge(merge_config, config)
        |> Map.put(:sensor_id, "#{device_name}:#{config[:sensor_type]}")
        |> IO.inspect(label: "result config")

        # |> Map.put(:sampling_rate, 20)
    end
  end
end
