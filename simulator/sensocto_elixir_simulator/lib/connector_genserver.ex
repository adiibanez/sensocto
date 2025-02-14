defmodule Sensocto.Simulator.ConnectorGenServer do
  use GenServer
  require Logger

  alias PhoenixClient.{Socket, Channel, Message}

  @socket_opts [
    url: "ws://localhost:4000/socket/websocket"
    # url: "wss://sensocto.fly.dev/socket/websocket"
    # url: "ws://192.168.1.195:4000/socket/websocket"
    # url: "wss://sensocto.ddns.net/socket/websocket"
    # https://sensocto.ddns.net/
  ]


  defmodule State do
    defstruct [:connector_id, :connector_name, :attributes, :supervisor, :phx_join_meta, :phoenix_connected, :phoenix_socket, :phoenix_channel]
  end

  def start_link(config) when is_map(config) do
    # Convert string keys to atoms for the essential fields
    config = %{
      connector_id: config["connector_id"],
      connector_name: config["connector_name"],
      attributes: config["attributes"] || %{}
    }

    GenServer.start_link(__MODULE__, config, name: via_tuple(config.connector_id))
  end

  @impl true
  def init(config) do
    Logger.info("Initializing connector: #{inspect(config)}")
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      connector_id: config.connector_id,
      connector_name: config.connector_name,
      attributes: %{},
      supervisor: supervisor,
      phoenix_connected: false,
      phoenix_channel: nil,
      phoenix_socket: nil,
      phx_join_meta: %{
          device_name: config.connector_name,
          batch_size: 1,
          connector_id: config.connector_id,
          connector_name: config.connector_name,
          sampling_rate: 1,
          sensor_id: config.connector_id,
          sensor_name: config.connector_name,
          sensor_type: "",#config.sensor_type,
          bearer_token: "fake"
        }
    }

    Process.send_after(self(), :connect_phoenix, 0)

    {:ok, state, {:continue, {:setup_attributes, config.attributes}}}
  end

  @impl true
  def handle_info({:push_batch, attribute_id, messages}, state) do
    Logger.info("#{state.connector_id} handle_info :push_batch #{inspect(messages)}")

    case Enum.count(messages) do
        1 ->
          PhoenixClient.Channel.push_async(
            state.phoenix_channel,
            "measurement",
            Enum.at(messages, 0)
          )

        _ ->
          PhoenixClient.Channel.push_async(
            state.phoenix_channel,
            "measurements_batch",
            messages
          )
      end

    {:noreply, state}
  end

  @impl true
  def handle_continue({:setup_attributes, attributes}, state) do
    new_state =
      Enum.reduce(attributes, state, fn {id, attr_config}, acc ->
        # Convert string keys to atoms and add attribute_id if not present
        attr_config = Map.new(attr_config, fn {k, v} -> {String.to_atom(k), v} end)

        attr_config =
          attr_config
          #  |> Map.put(:attribute_id, id)
          |> Map.put(:connector_pid, self())

        #  |> Map.put(:connector_name, state.connector_name)

        Logger.info("Connector attr config: #{inspect(attr_config)}")

        start_attribute(acc, attr_config)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_config, new_config}, state) do
    # Handle configuration updates
    {:noreply, state}
  end

  defp start_attribute(state, attr_config) do
    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.AttributeGenServer, attr_config}
         ) do
      {:ok, pid} ->
        %{state | attributes: Map.put(state.attributes, attr_config.attribute_id, attr_config)}

      {:error, reason} ->
        Logger.error("Failed to start attribute #{attr_config.attribute_id}: #{inspect(reason)}")
        state
    end
  end


def handle_info(:connect_phoenix, %{:connector_id => connector_id} = state) do
    Logger.info("#{connector_id} handle_info:connect_phoenix")
    GenServer.cast(self(), :connect_phoenix)
    {:noreply, state}
  end

  def handle_cast(:connect_phoenix, %{:connector_id => connector_id} = state) do
    Logger.info("#{connector_id} Connect to phoenix")

    parent = self()

    case PhoenixClient.Socket.start_link(@socket_opts) do
      {:ok, socket} ->
        wait_until_connected(socket, 0, parent)

        topic = "sensor_data:#{state.connector_id}"

        Logger.info("#{connector_id} Connecting ... #{topic}")

        case PhoenixClient.Channel.join(socket, topic, state.phx_join_meta) do
          {:ok, _response, channel} ->
            Logger.info(
              "#{connector_id} Joined channel successfully #{topic}"
            )

            Process.send_after(
              parent,
              :process_queue,
              100
            )

            {:noreply,
             state
             |> Map.put(:phoenix_socket, socket)
             |> Map.put(:phoenix_channel, channel)
             |> Map.put(:phoenix_connected, true)}

          {:error, reason} ->
            Logger.warning("#{connector_id} Failed to join channel: #{topic} #{inspect(reason)}")

            Process.send_after(
              self(),
              :connect_phoenix,
              0
            )

            {:noreply, state |> Map.put(:phoenix_connected, false)}
            # {:stop, reason}
        end

      {:error, reason} ->
        Logger.warning("#{connector_id} Failed to connect to socket: #{inspect(reason)}")

        Process.send_after(
          self(),
          :connect_phoenix,
          0
        )

        {:noreply, state |> Map.put(:phoenix_connected, false)}
        # {:stop, reason}
    end
  end


def handle_info(%Message{event: message, payload: payload}, %{:connector_id => connector_id} = state)
      when message in ["phx_error", "phx_close"] do
    Logger.info("#{connector_id} handle_info: #{message}")

    Process.send_after(
      self(),
      :connect_phoenix,
      0
    )

    {:noreply, state}
  end

  def handle_info(%Message{event: message, payload: payload}, %{:connector_id => connector_id} = state) do
    Logger.info("#{connector_id} Incoming Phoenix Message: #{message} #{inspect(payload)}")
    {:noreply, state}
  end

  def handle_info(msg, %{:connector_id => connector_id} = state) do
    Logger.info("#{connector_id} handle_info:catch all: #{inspect(msg)}")
    {:noreply, state}
  end


  defp wait_until_connected(socket, retries \\ 0, pid) do
    Logger.info("wait_until_connected #{retries} #{inspect(pid)}")

    if !(PhoenixClient.Socket.connected?(socket) or retries > 10) do
      Logger.info("Wait 500ms until connected #{retries} #{inspect(pid)}")
      Process.sleep(1000 * retries)
      wait_until_connected(socket, retries + 1, pid)
    end

    Logger.info("send another :process_queue #{retries} #{inspect(pid)}")

    Process.send_after(
      self(),
      :process_queue,
      0
    )
  end

  defp via_tuple(connector_id), do: {:via, Registry, {Sensocto.Registry, connector_id}}
end
