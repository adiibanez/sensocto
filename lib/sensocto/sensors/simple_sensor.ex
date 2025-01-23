defmodule Sensocto.SimpleSensor do
  use GenServer
  require Logger
  alias Sensocto.{AttributeStore, SimpleSensorRegistry}

  # defstruct [:attribute_store_pid]

  def start_link(%{:sensor_id => sensor_id} = configuration) do
    Logger.debug("SimpleSensor start_link: #{inspect(configuration)}")
    # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
    GenServer.start_link(__MODULE__, configuration, name: via_tuple(sensor_id))
  end

  @impl true
  def init(state) do
    Logger.debug("SimpleSensor state: #{inspect(state)}")
    {:ok, state}
  end

  # client
  def put_attribute(sensor_id, attribute) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          Logger.debug("Client: put_attribute #{inspect(pid)} #{inspect(attribute)}")
          GenServer.cast(pid, {:put_attribute, attribute})

        _ ->
          Logger.debug("Client: put_attribute ERROR #{inspect(attribute)}")
      end
    rescue
      e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def clear_attribute(sensor_id, attribute_id) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          Logger.debug("Client: clear_attribute #{inspect(pid)} #{inspect(attribute_id)}")
          GenServer.cast(pid, {:clear_attribute, attribute_id})

        _ ->
          Logger.debug("Client: clear_attribute ERROR #{inspect(attribute_id)}")
      end
    rescue
      e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def get_attribute(sensor_id, attribute_id, limit) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          Logger.debug("Client: Get attribute #{sensor_id}, #{attribute_id}, limit: #{limit}")
          GenServer.call(pid, {:get_attribute, attribute_id, limit})

        _ ->
          Logger.debug("Client: Get attributes ERROR for id: #{inspect(sensor_id)}")
          :error
      end
    rescue
      e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def get_attribute(sensor_id, attribute_id, from_timestamp, to_timestamp) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          Logger.debug(
            "Client: Get attribute #{sensor_id}, #{attribute_id}, from: #{from_timestamp} to: #{to_timestamp}"
          )

          GenServer.call(pid, {:get_attribute, attribute_id, from_timestamp, to_timestamp})

        _ ->
          Logger.debug("Client: Get attributes ERROR for id: #{inspect(sensor_id)}")
          :error
      end
    rescue
      e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def get_attributes(sensor_id) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          Logger.debug("Client: Get attributes #{inspect(pid)}")
          GenServer.call(pid, :get_attributes)

        _ ->
          Logger.debug("Client: Get attributes ERROR for id: #{inspect(sensor_id)}")
          :error
      end
    rescue
      e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  # server
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:get_attribute, attribute_id, limit}, _from, %{sensor_id: sensor_id} = state) do
    attributes = AttributeStore.get_attribute(sensor_id, attribute_id, limit)

    Logger.debug(
      "Server: :get_attribute  #{attribute_id}  with limit #{limit}  from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_call(
        {:get_attribute, attribute_id, from_timestamp, to_timestamp},
        _from,
        %{sensor_id: sensor_id} = state
      ) do
    attributes =
      AttributeStore.get_attribute(sensor_id, attribute_id, from_timestamp, to_timestamp)

    Logger.debug(
      "Server: :get_attribute  #{attribute_id} from: #{from_timestamp} to: #{to_timestamp} from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_call(:get_attributes, _from, %{sensor_id: sensor_id} = state) do
    Logger.debug("{__MODULE__}:SRV :get_attributes  #{inspect(state)}")
    attributes = AttributeStore.get_attributes(sensor_id)
    # Logger.debug("Server: :get_attributes #{inspect(attributes)}")
    {:reply, attributes, state}
  end

  @impl true
  def handle_cast(
        {:put_attribute,
         %{:id => attribute_id, :payload => payload, :timestamp => timestamp} = attribute},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :put_attribute #{inspect(attribute)} state: #{inspect(state)}")
    AttributeStore.put_attribute(sensor_id, attribute_id, timestamp, payload)
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:clear_attribute, attribute_id},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :clear_attribute #{sensor_id}:#{attribute_id} state: #{inspect(state)}")
    AttributeStore.remove_attribute(sensor_id, attribute_id)
    {:noreply, state}
  end

  defp via_tuple(sensor_id) do
    {:via, Registry, {SimpleSensorRegistry, sensor_id}}
  end
end
