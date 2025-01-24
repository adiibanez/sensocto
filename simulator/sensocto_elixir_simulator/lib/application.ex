defmodule Sensocto.Simulator.Application do
  use Application
  require Logger

  @configs [
    %{
      batch_size: 1,
      connector_id: "1111111",
      connector_name: "SensoctoSim",
      sampling_rate: 10,
      sensor_type: "heartrate",
      duration: 10,
      sampling_rate: 1,
      heart_rate: 60,
      respiratory_rate: 15,
      scr_number: 5,
      burst_number: 5,
      sensor_type: "heartrate"
    },
    %{
      batch_size: 1,
      connector_id: "22222",
      connector_name: "SensoctoSim",
      sampling_rate: 10,
      sensor_type: "heartrate",
      duration: 10,
      sampling_rate: 1,
      heart_rate: 150,
      respiratory_rate: 30,
      scr_number: 5,
      burst_number: 5,
      sensor_type: "heartrate"
    },
    %{
      batch_size: 1,
      connector_id: "22222",
      connector_name: "SensoctoSim",
      sampling_rate: 10,
      sensor_type: "ecg",
      duration: 10,
      sampling_rate: 10,
      heart_rate: 150,
      respiratory_rate: 30,
      scr_number: 5,
      burst_number: 5,
      sensor_type: "ecg"
    },
    %{
      batch_size: 1,
      connector_id: "22222",
      connector_name: "SensoctoSim",
      sampling_rate: 10,
      sensor_type: "ecg",
      duration: 10,
      sampling_rate: 10,
      heart_rate: 150,
      respiratory_rate: 30,
      scr_number: 5,
      burst_number: 5,
      sensor_type: "ecg"
    }
  ]

  def start(_type, _args) do
    IO.puts("Start simulator")

    children = [
      SensorSimulatorSupervisor,
      {Registry, keys: :unique, name: SensorSimulatorRegistry}
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
    processes_running = Enum.count(SensorSimulatorSupervisor.get_children())
    IO.inspect(SensorSimulatorSupervisor.get_children())

    IO.puts("keep: #{keep_running}, running: #{processes_running}")

    if processes_running < keep_running do
      IO.puts("start servers")

      sensor_numbers = 1..keep_running

      Enum.each(sensor_numbers, fn number ->
        # Convert the number to a sensor name string (e.g., "sensor1", "sensor2", ...)

        # config = Enum.random(@configs)
        # sensor_name = config['sensor_name']

        sensor_name = "SensoctoSimEx_#{number}"

        new_config = getconfig_for_device(sensor_name, config)
        Logger.debug("New config #{inspect(new_config)}")

        # Start the sensor by calling start_sensor on the SensorSupervisor
        case SensorSimulatorSupervisor.start_sensor(new_config || Enum.random(@configs)) do
          {:ok, pid} -> IO.puts("started #{sensor_name}")
          {:error, _} -> IO.puts("failed to start #{sensor_name}")
        end

        Process.sleep(:rand.uniform(ramp_up_delay))
      end)

      SensorSimulatorSupervisor.get_children()
    else
      IO.puts("keep or stop servers")

      Enum.take(SensorSimulatorSupervisor.get_children(), processes_running - keep_running)
      |> Enum.each(fn {_, pid, _, _type} ->
        IO.inspect(pid)
        DynamicSupervisor.terminate_child(SensorSimulatorSupervisor, pid)
        Process.sleep(:rand.uniform(ramp_down_delay))
      end)

      SensorSimulatorSupervisor.get_children()
    end
  end


  defp getconfig_for_device(device_name, config) do

    merge_config = %{
      :device_name => device_name,
      :sensor_id => device_name,
      :sensor_name => device_name,
      :duration => 20
    }

    case config do
      nil -> Map.merge(merge_config, Enum.random(@configs))
      config -> Map.merge(merge_config, config)
      config
      |> Map.put(:sensor_id, "#{device_name}:#{config[:sensor_type]}")
      |> Map.put(:sampling_rate, 1)

    end


  end

  defp config_from_device_name(device_name) do
    %{
      device_name: "#{device_name}",
      batch_size: 1,
      connector_id: "22222",
      connector_name: "SensoctoSim",
      sampling_rate: 1,
      sensor_id: "#{device_name}",
      sensor_name: "#{device_name}",
      sensor_type: "heartrate",
      duration: 60,
      sampling_rate: 1,
      heart_rate: 150,
      respiratory_rate: 30,
      scr_number: 5,
      burst_number: 5,
      sensor_type: "heartrate"
    }
  end

end
