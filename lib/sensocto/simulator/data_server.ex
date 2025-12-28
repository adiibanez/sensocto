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
    Logger.info("Starting DataServer: #{worker_name}")
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
    case DataGenerator.fetch_sensor_data(config) do
      {:ok, data} ->
        Logger.debug("DataServer #{state.worker_id}: Generated #{length(data)} data points")
        send(caller_pid, {:get_data_result, data})

      {:error, reason} ->
        Logger.error("DataServer #{state.worker_id}: Error generating data: #{inspect(reason)}")
        # Send empty list on error so the attribute doesn't get stuck
        send(caller_pid, {:get_data_result, []})
    end

    {:noreply, state}
  end
end
