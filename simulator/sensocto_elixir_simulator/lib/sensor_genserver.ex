defmodule Sensocto.Simulator.SensorGenServer do
  use GenServer
  require Logger

  defmodule State do
    defstruct [
      :sensor_id,
      :sensor_name,
      :connector_id,
      :phoenix_socket,
      :phoenix_channel,
      :attributes,
      :supervisor
    ]
  end

  def start_link(%{sensor_id: sensor_id, connector_id: connector_id} = config) do
    Logger.info("Sensor start_link #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple("#{connector_id}_#{sensor_id}"))
  end

  @impl true
  def init(
        %{
          sensor_id: sensor_id,
          sensor_name: sensor_name,
          connector_id: connector_id,
          phoenix_socket: phoenix_socket,
          attributes: attributes
        } = state
      ) do
    Logger.info("Starting sensor #{inspect(state)}")
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sensor_id: sensor_id,
      sensor_name: sensor_name,
      connector_id: connector_id,
      phoenix_socket: phoenix_socket,
      phoenix_channel: nil,
      attributes: attributes,
      supervisor: supervisor
    }

    {:ok, state, {:continue, :join_channel}}
  end

  @impl true
  def handle_continue(:join_channel, state) do
    topic = "sensor_data:#{state.sensor_id}"

    join_attributes =
      Enum.map(state.attributes, fn {attribute_id, attribute} ->
        %{
          attribute_id => %{
            "attribute_id" => attribute_id,
            "sampling_rate" => attribute["sampling_rate"],
            "attribute_type" => attribute["sensor_type"]
          }
        }
      end)
      |> Enum.reduce(%{}, fn item, acc ->
        # Extract the key and value from the item
        key = Map.keys(item) |> List.first()
        value = Map.get(item, key)

        # Put the key and value into the accumulator map
        Map.put(acc, key, value)
      end)

    # join_attributes = %{"test": 123}

    join_meta = %{
      device_name: state.connector_id,
      batch_size: 1,
      connector_id: state.connector_id,
      connector_name: state.connector_id,
      attributes: join_attributes,
      sensor_id: state.sensor_id,
      sensor_name: state.sensor_name,
      sensor_type: "heartrate",
      bearer_token: "fake",
      sampling_rate: 1
    }

    case PhoenixClient.Channel.join(state.phoenix_socket, topic, join_meta) do
      {:ok, _response, channel} ->
        new_state = %{state | phoenix_channel: channel}
        {:noreply, new_state, {:continue, {:setup_attributes, state.attributes}}}

      {:error, reason} ->
        Logger.error("Failed to join channel: #{inspect(reason)}")
        Process.send_after(self(), :retry_join, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_continue({:setup_attributes, attributes}, state) do
    Logger.info("Setup attributes #{inspect(attributes)}")

    new_state =
      Enum.reduce(attributes, state, fn {attr_id, attr_config}, acc ->
        start_attribute(acc, attr_id, attr_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:push_batch, attribute_id, messages}, state) do
    Logger.debug("Received batch of #{length(messages)} messages for attribute #{attribute_id}")
    Logger.debug("Messages: #{inspect(messages)}")

    if length(messages) == 1 do
      first = List.first(messages)

      PhoenixClient.Channel.push_async(
        state.phoenix_channel,
        "measurement",
        %{
          "attribute_id" => attribute_id,
          "timestamp" => first["timestamp"],
          "payload" => first["payload"]
        }
      )
    else
      PhoenixClient.Channel.push_async(
        state.phoenix_channel,
        "measurements_batch",
        messages
      )
    end

    {:noreply, state}
  end

  defp start_attribute(state, attribute_id, config) do
    config = Sensocto.Utils.string_keys_to_atom_keys(config)

    attr_config =
      Map.merge(config, %{
        attribute_id: attribute_id,
        sensor_id: state.sensor_id,
        connector_id: state.connector_id,
        sensor_pid: self()
      })

    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.AttributeGenServer, attr_config}
         ) do
      {:ok, pid} ->
        Logger.info("Started attribute #{attribute_id} #{inspect(attr_config)}")
        %{state | attributes: Map.put(state.attributes, attribute_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start attribute #{attribute_id}: #{inspect(reason)}")
        state
    end
  end

  def handle_info(%PhoenixClient.Message{} = msg, state) do
    Logger.debug("Sensor #{state.sensor_id} handle_info PHX catchall:  #{inspect(msg)}")
    {:noreply, state}
  end

  # def handle_info(msg, %{:sensor_id => sensor_id} = state) do
  #   Logger.info("#{sensor_id} handle_info:catch all: #{inspect(msg)}")
  #   {:noreply, state}
  # end

  defp via_tuple(identifier),
    do: {:via, Registry, {Sensocto.Registry, "#{__MODULE__}_#{identifier}"}}
end
