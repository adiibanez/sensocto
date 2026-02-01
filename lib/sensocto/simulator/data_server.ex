defmodule Sensocto.Simulator.DataServer do
  @moduledoc """
  GenServer for parallel data generation.
  Multiple instances run in a pool to handle concurrent data requests.
  """

  use GenServer
  require Logger
  alias Sensocto.Simulator.DataGenerator

  def start_link(worker_id) do
    worker_name = :"sim_data_server_#{worker_id}"
    Logger.debug("Starting DataServer: #{worker_name}")
    GenServer.start_link(__MODULE__, worker_id, name: worker_name)
  end

  @impl true
  def init(worker_id) do
    Logger.debug("DataServer #{worker_id} initialized")
    {:ok, %{worker_id: worker_id}}
  end

  @impl true
  def handle_info({:get_data, caller_pid, config}, state) do
    GenServer.cast(self(), {:get_data, caller_pid, config})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:get_data, caller_pid, config}, state) do
    {:ok, data} = DataGenerator.fetch_sensor_data(config)
    Logger.debug("DataServer #{state.worker_id}: Generated #{length(data)} data points")
    send(caller_pid, {:get_data_result, data})

    {:noreply, state}
  end
end
