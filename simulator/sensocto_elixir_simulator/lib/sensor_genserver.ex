defmodule Sensocto.Simulator.SensorGenServer do
  use GenServer
  require Logger
  alias PhoenixClient.{Socket, Channel, Message}

  defmodule State do
    defstruct [
      :sensor_id,
      :sensor_name,
      :connector_id,
      :phoenix_socket,
      :phoenix_channel,
      :phoenix_retries,
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
      phoenix_retries: 0,
      phoenix_channel: nil,
      attributes: attributes,
      supervisor: supervisor
    }

    {:ok, state, {:continue, :join_channel}}
  end

  @impl true
  def handle_continue(
        :join_channel,
        %{
          :connector_id => connector_id,
          :sensor_id => sensor_id,
          :sensor_name => sensor_name,
          :phoenix_retries => phoenix_retries,
          :phoenix_socket => phoenix_socket
        } = state
      ) do
    topic = "sensocto:sensor:#{sensor_id}"

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
      connector_name: connector_id,
      batch_size: 1,
      connector_id: connector_id,
      connector_name: connector_id,
      attributes: join_attributes,
      sensor_id: sensor_id,
      sensor_name: sensor_name,
      sensor_type: "heartrate",
      bearer_token: "fake",
      sampling_rate: 1
    }

    case Channel.join(phoenix_socket, topic, join_meta) do
      {:ok, _response, channel} ->
        new_state =
          state
          |> Map.put(:phoenix_channel, channel)
          |> Map.put(:phoenix_retries, 0)

        {:noreply, new_state, {:continue, {:setup_attributes, state.attributes}}}

      {:error, reason} ->
        Logger.error("Failed to join channel: #{inspect(reason)}")
        Process.send_after(self(), :retry_join, 1000) # phoenix_retries *
        {:noreply, state |> Map.put(:phoenix_retries, phoenix_retries + 1)}
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

      Channel.push_async(
        state.phoenix_channel,
        "measurement",
        %{
          "attribute_id" => attribute_id,
          "timestamp" => first["timestamp"],
          "payload" => first["payload"]
        }
      )
    else
      Channel.push_async(
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

  def handle_info(%Message{event: message, payload: payload}, %{:sensor_id => sensor_id} = state)
      when message in ["phx_error", "phx_close"] do
    Logger.info("Sensor #{sensor_id} handle_info: #{message}")
    {:noreply, state, {:continue, :join_channel}}
  end

  def handle_info(:retry_join, %{:sensor_id => sensor_id} = state) do
    Logger.info("Sensor #{sensor_id} retry join_channel")
    {:noreply, state, {:continue, :join_channel}}
  end

  def handle_info(%Message{} = msg, %{:sensor_id => sensor_id} = state) do
    Logger.info("Sensor #{sensor_id} handle_info PHX catchall:  #{inspect(msg)}")
    {:noreply, state}
  end

  # def handle_info(msg, %{:sensor_id => sensor_id} = state) do
  #   Logger.info("#{sensor_id} handle_info:catch all: #{inspect(msg)}")
  #   {:noreply, state}
  # end

  defp via_tuple(identifier),
    do: {:via, Registry, {Sensocto.Registry, "#{__MODULE__}_#{identifier}"}}
end
