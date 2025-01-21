defmodule Sensocto.Device do
  use GenServer
  require Logger

  # def start_link(child_spec) do
  # GenServer.start_link(__MODULE__, child_spec)
  # GenServer.start_link(__MODULE__, %{}, name: child_spec.name)
  # end

  # def start_link(device_id) do
  #  GenServer.start_link(__MODULE__, device_id, name: via_tuple(device_id))
  # end

  # Accepts a tuple {:via, Sensocto.Registry, device_id} for registration
  def start_link({:via, registry, device_id}) do
    GenServer.start_link(__MODULE__, %{}, name: {:via, registry, device_id})
  end

  # defp via_tuple(device_id) do
  #  {:global, {:sensocto_device, device_id}}
  # {:via, Sensocto.Registry, device_id}
  # end

  @impl true
  def init(device_id) do
    {:ok, %{id: device_id, state: :idle}}
  end

  @impl true
  def handle_cast(:connect, state) do
    Logger.debug("connect")
    {:noreply, %{state | state: :connected}}
  end

  @impl true
  def handle_cast(:disconnect, state) do
    {:noreply, %{state | state: :idle}}
  end

  @impl true
  def handle_cast({:sensor_data, data}, state) do
    # Process sensor data here
    Logger.info("Received sensor data: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:inspect_state, _from, state) do
    Logger.debug("Inspect state 1")
    {:reply, state, state}
  end
end
