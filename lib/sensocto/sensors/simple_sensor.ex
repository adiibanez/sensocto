defmodule Sensocto.SimpleSensor do
  use GenServer

  # defstruct [:attribute_store_pid]

  # def start_link({:via, registry, device_id}) do
  #  GenServer.start_link(__MODULE__, %{}, name: {:via, registry, device_id})
  # end

  # def start_link([%{:sensor_id => sensor_id} = configuration]) do
  #  IO.puts("SimpleSensor start_link1: #{inspect(configuration)}")
  #  # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
  #  GenServer.start_link(__MODULE__, configuration, name: via_tuple(sensor_id))
  # end

  def start_link(%{:sensor_id => sensor_id} = configuration) do
    IO.puts("SimpleSensor start_link2: #{inspect(configuration)}")
    # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
    GenServer.start_link(__MODULE__, configuration, name: via_tuple(sensor_id))
  end

  # def start_link(test, args) do
  #  IO.puts("SimpleSensor start_link3: #{inspect(args)}")
  #  # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
  #  GenServer.start_link(__MODULE__, args, name: via_tuple("sensor_XY"))
  # end

  @impl true
  def init(state) do
    IO.puts("SimpleSensor state: #{inspect(state)}")
    {:ok, state}
  end

  def child_spec_disabled(init_arg) do
    %{
      start: {__MODULE__, :start_link, init_arg}
    }
  end

  # client
  def set_attribute(sensor_id, attribute) do
    IO.puts("test")
    [{pid, _}] = Registry.lookup(Sensocto.SimpleSensorRegistry, sensor_id)
    IO.puts("Client: Set_attribute #{inspect(pid)} #{inspect(attribute)}")
    GenServer.cast(pid, {:set_attribute, attribute})

    # case Registry.lookup(SimpleSensorRegistry, sensor_id) do
    #      [{pid, _}] ->
    #           IO.puts("Client: Set_attribute #{inspect(pid)} #{inspect(attribute)}")
    #          GenServer.cast(pid, {:set_attribute, attribute})
    #     _ ->
    #        IO.puts("Client: Set_attribute ERROR #{inspect(attribute)}")
    #     end
  end

  def get_attributes(sensor_id) do
    [{pid, _}] = Registry.lookup(Sensocto.SimpleSensorRegistry, sensor_id)
    IO.puts("Client: Get attributes #{inspect(pid)}")
    GenServer.call(pid, :get_attributes)
  end

  # server

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_attributes, _from, state) do
    IO.puts("sensor_id #{state.sensor_id}")
    attributes = Sensocto.AttributeStore.get_attributes(state.sensor_id)
    IO.puts("Server: :get_attributes #{inspect(attributes)}")
    {:reply, attributes, state}
  end

  @impl true
  def handle_cast({:set_attribute, %{:id => attribute_id, :value => value} = attribute}, state) do
    IO.puts("Server: :set_attribute #{inspect(attribute)} state: #{inspect(state)}")
    # IO.puts("Server: :set_attribute registered_name #{inspect(sensor_id)}")
    Sensocto.AttributeStore.put_attribute(state.sensor_id, attribute_id, value)
    {:noreply, state}
  end

  defp via_tuple(sensor_id) do
    {:via, Registry, {Sensocto.SimpleSensorRegistry, sensor_id}}
  end
end
