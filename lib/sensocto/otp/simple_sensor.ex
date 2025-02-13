defmodule Sensocto.SimpleSensor do
  use GenServer
  require Logger
  alias Sensocto.AttributeStore
  alias Sensocto.SimpleSensorRegistry

  # Add interval for mps calculation
  # 1 second
  @mps_interval 1_000

  def start_link(%{:sensor_id => sensor_id} = configuration) do
    Logger.debug("SimpleSensor start_link: #{inspect(configuration)}")
    GenServer.start_link(__MODULE__, configuration, name: via_tuple(sensor_id))
  end

  @impl true
  @spec init(map()) :: {:ok, %{:message_timestamps => [], optional(any()) => any()}}
  def init(state) do
    Logger.debug("SimpleSensor state: #{inspect(state)}")
    # Initialize message counter and schedule mps calculation
    state =
      Map.merge(state, %{message_timestamps: []})
      |> Map.put(:mps_interval, 5000)

    schedule_mps_calculation()
    {:ok, state}
  end

  def get_state(sensor_id) do
    case Registry.lookup(SimpleSensorRegistry, sensor_id) do
      [{pid, _}] ->
        Logger.debug("Client: get_state #{inspect(pid)} #{inspect(sensor_id)}")
        GenServer.call(pid, :get_state)

      [] ->
        Logger.debug("Client: get_state No sensor_found #{inspect(sensor_id)}")

      _ ->
        Logger.debug("Client: get_state ERROR #{inspect(sensor_id)}")
    end
  end

  # client
  def put_attribute(sensor_id, attribute) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          # Logger.debug("Client: put_attribute #{inspect(pid)} #{inspect(attribute)}")
          GenServer.cast(pid, {:put_attribute, attribute})

        _ ->
          Logger.debug("Client: put_attribute ERROR #{inspect(attribute)}")
          {:error, "Whatever"}
      end
    rescue
      _e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def put_batch_attributes(sensor_id, attributes) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          # Logger.debug("Client: put_attribute #{inspect(pid)} #{inspect(attribute)}")
          GenServer.cast(pid, {:put_batch_attributes, attributes})

        _ ->
          Logger.debug("Client: put_batch_attribute ERROR #{length(attributes)}")
          {:error, "Whatever"}
      end
    rescue
      _e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def clear_attribute(sensor_id, attribute_id) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          # Logger.debug("Client: clear_attribute #{inspect(pid)} #{inspect(attribute_id)}")
          GenServer.cast(pid, {:clear_attribute, attribute_id})

        _ ->
          Logger.debug("Client: clear_attribute ERROR #{inspect(attribute_id)}")
      end
    rescue
      _e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def get_attribute(sensor_id, attribute_id, limit) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          # Logger.debug("Client: Get attribute #{sensor_id}, #{attribute_id}, limit: #{limit}")
          GenServer.call(pid, {:get_attribute, attribute_id, limit})

        _ ->
          Logger.debug("Client: Get attributes ERROR for id: #{inspect(sensor_id)}")
          :error
      end
    rescue
      _e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  def get_attribute(sensor_id, attribute_id, from \\ 0, to \\ :infinity, limit \\ :infinity) do
    try do
      case Registry.lookup(SimpleSensorRegistry, sensor_id) do
        [{pid, _}] ->
          GenServer.call(pid, {:get_attribute, attribute_id, from, to, limit})

        _ ->
          Logger.debug("Client: Get attribute ERROR for id: #{inspect(sensor_id)}")
          :error
      end
    rescue
      _e ->
        Logger.error(inspect(__STACKTRACE__))
    end
  end

  # server
  @impl true
  def handle_call(:get_state, _from, %{sensor_id: sensor_id} = state) do
    sensor_state = %{
      metadata: state |> Map.delete(:message_timestamps) |> Map.delete(:mps_interval),
      attributes:
        AttributeStore.get_attributes(sensor_id, 1)
        |> Enum.map(fn x -> cleanup(x) end)
        |> Enum.into(%{})
      #        |> dbg()
    }

    # Logger.debug("Sensor state: #{inspect(sensor_state)}")

    {:reply, sensor_state, state}
  end

  def cleanup(entry) do
    case entry do
      {attribute_id, [entry]} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}

      {attribute_id, %{}} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}
    end
  end

  @impl true
  def handle_call({:get_attribute, attribute_id, limit}, _from, %{sensor_id: sensor_id} = state) do
    {:ok, attributes} = AttributeStore.get_attribute(sensor_id, attribute_id, limit)

    Logger.debug(
      "Server: :get_attribute (attribute_id, limit)  #{attribute_id}  with limit #{limit}  from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_call(
        {:get_attribute, attribute_id, from, to, limit},
        _from,
        %{sensor_id: sensor_id} = state
      ) do
    {:ok, attributes} =
      AttributeStore.get_attribute(sensor_id, attribute_id, from, to, limit)

    Logger.debug(
      "Server: :get_attribute (attribute_id, from, to, limit)  #{attribute_id} from: #{from} to: #{to} limit: #{limit} from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_cast(
        {:put_attribute,
         %{:attribute_id => attribute_id, :payload => payload, :timestamp => timestamp} =
           attribute},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :put_attribute #{inspect(attribute)} state: #{inspect(state)}")

    AttributeStore.put_attribute(sensor_id, attribute_id, timestamp, payload)

    now = System.system_time(:millisecond)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "measurement:#{sensor_id}",
      {
        :measurement,
        attribute
        |> Map.put(:sensor_id, sensor_id)
      }
    )

    {:noreply,
     state
     |> Map.update!(:message_timestamps, &[now | &1])}
  end

  @impl true
  def handle_cast(
        {:put_batch_attributes, attributes},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :put_batch_attributes #{length(attributes)} state: #{inspect(state)}")

    broadcast_messages_list =
      Enum.map(attributes, fn attribute ->
        AttributeStore.put_attribute(
          sensor_id,
          attribute.attribute_id,
          attribute.timestamp,
          attribute.payload
        )

        attribute
        |> Map.put(:sensor_id, sensor_id)
      end)

    now = System.system_time(:millisecond)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "measurements_batch:#{sensor_id}",
      {
        :measurements_batch,
        {sensor_id, broadcast_messages_list}
      }
    )

    {:noreply,
     state
     |> Map.update!(:message_timestamps, &[now | &1])}
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

  @impl true
  def handle_info(
        :calculate_mps,
        %{sensor_id: sensor_id, message_timestamps: timestamps, mps_interval: mps_interval} =
          state
      ) do
    now = System.system_time(:millisecond)
    interval_ago = now - mps_interval

    # Filter timestamps within the interval
    recent_timestamps = Enum.filter(timestamps, fn timestamp -> timestamp >= interval_ago end)
    mps = length(recent_timestamps) / (mps_interval / 1000)

    Logger.debug("Server: :calculate_mps #{inspect(mps)}")

    # Emit telemetry event with MPS
    :telemetry.execute(
      [:sensocto, :sensors, :messages, :mps],
      %{value: mps},
      %{sensor_id: sensor_id}
    )

    # Schedule next calculation
    schedule_mps_calculation()
    {:noreply, %{state | message_timestamps: recent_timestamps}}
  end

  defp schedule_mps_calculation do
    Process.send_after(self(), :calculate_mps, @mps_interval)
  end

  defp schedule_mps_calculation do
    Process.send_after(self(), :calculate_mps, @mps_interval)
  end

  defp via_tuple(sensor_id) do
    # Sensocto.RegistryUtils.via_dynamic_registry(SimpleSensorRegistry, sensor_id)
    {:via, Registry, {SimpleSensorRegistry, sensor_id}}
  end
end
