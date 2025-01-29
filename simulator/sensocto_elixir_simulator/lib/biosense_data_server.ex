defmodule Sensocto.BiosenseData.GenServer do
  use GenServer
  require Logger
  alias Sensocto.BiosenseData

  def start_link(init_arg) do
    worker_name = "biosense_data_server_#{init_arg}"
    Logger.info("start_link #{inspect(init_arg)}, worker_name: #{worker_name}")
    GenServer.start_link(__MODULE__, init_arg, name: :"#{worker_name}")

    # GenServer.start_link(__MODULE__, init_arg, name: via_tuple(worker_name)) # , name: :biosense_data_server
  end

  @impl true
  def init(state \\ %{}) do
    Logger.info("init #{inspect(state)}")
    {:ok, state}
  end

  @impl true
  def handle_info(:hello_world, state) do
    Logger.info("Hello world")
  end

  @impl true
  def handle_info({:get_data, caller_pid, config}, state) do
    # Logger.info("#{__MODULE__} handle_info :get_data #{inspect(config)}")

    case GenServer.cast(self(), {:get_data, caller_pid, config}) do
      :ok ->
        # Logger.debug("#{__MODULE__} handle_info :get_data #{inspect(config)}")
        {:noreply, state}

      :error ->
        Logger.error("#{__MODULE__} handle_info :get_data error #{inspect(config)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:get_data, caller_pid, config}, state) do
    # Logger.info("#{__MODULE__} handle_cast :get_data #{inspect(config)}")
    case BiosenseData.fetch_sensor_data(config) do
      {:ok, data} ->
        Logger.debug("#{__MODULE__} handle_cast :get_data #{config.duration} #{Enum.count(data)}")
        Process.send_after(caller_pid, {:get_data_result, data}, 0)
        {:noreply, state}
        # :error ->
        #  Logger.error("#{__MODULE__} handle_cast :get_data error #{inspect(config)}")
        #  {:noreply, state}
    end

    {:noreply, state}
  end

  # defp via_tuple(worker_name), do: {:via, Registry, {Sensocto.RegistryWorkers, worker_name}}
end
