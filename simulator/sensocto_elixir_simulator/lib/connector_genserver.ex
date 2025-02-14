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
    defstruct [
      :connector_id,
      :connector_name,
      :phoenix_socket,
      :sensors,
      :supervisor
    ]
  end

  def start_link(config) when is_map(config) do
    config = %{
      connector_id: config["connector_id"],
      connector_name: config["connector_name"],
      sensors: config["sensors"] || %{}
    }

    Logger.info("start_link: #{inspect(config)}")

    GenServer.start_link(__MODULE__, config, name: via_tuple(config.connector_id))
  end

  @impl true
  def init(config) do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      connector_id: config.connector_id,
      connector_name: config.connector_name,
      sensors: config.sensors,
      supervisor: supervisor,
      phoenix_socket: nil
    }

    {:ok, state, {:continue, :connect_socket}}
  end

  @impl true
  def handle_continue(:connect_socket, state) do
    case connect_phoenix_socket() do
      {:ok, socket} ->
        new_state = %{state | phoenix_socket: socket}
        {:noreply, new_state, {:continue, {:setup_sensors, state.sensors}}}

      {:error, reason} ->
        Logger.error("Failed to connect socket: #{inspect(reason)}")
        Process.send_after(self(), :retry_connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_continue({:setup_sensors, sensors}, state) do
    Logger.info("Setup sensors #{inspect(sensors)}")

    new_state =
      Enum.reduce(sensors, state, fn {sensor_id, sensor_config}, acc ->
        start_sensor(acc, sensor_id, sensor_config)
      end)

    {:noreply, new_state}
  end

  defp connect_phoenix_socket do
    case PhoenixClient.Socket.start_link(@socket_opts) do
      {:ok, socket} ->
        wait_until_connected(socket, 5, self())
        {:ok, socket}
    end
  end

  defp start_sensor(state, sensor_id, sensor_config) do
    sensor_config = Sensocto.Utils.string_keys_to_atom_keys(sensor_config)

    config =
      Map.merge(sensor_config, %{
        :sensor_id => sensor_id,
        :connector_id => state.connector_id,
        :connector_name => state.connector_name,
        :phoenix_socket => state.phoenix_socket
      })

    Logger.info("Start sensor: #{sensor_id}")
    Logger.info("Sensor config: #{inspect(config)}")

    case DynamicSupervisor.start_child(
           state.supervisor,
           {Sensocto.Simulator.SensorGenServer, config}
         ) do
      {:ok, pid} ->
        Logger.info("Added sensor #{sensor_id}")
        %{state | sensors: Map.put(state.sensors, sensor_id, pid)}

      {:error, reason} ->
        Logger.error("Failed to start sensor #{sensor_id}: #{inspect(reason)}")
        state
    end
  end

  defp wait_until_connected(socket, retries \\ 0, pid) do
    Logger.debug("wait_until_connected #{retries} #{inspect(pid)}")

    if !(PhoenixClient.Socket.connected?(socket) or retries > 10) do
      Logger.debug("Wait 500ms until connected #{retries} #{inspect(pid)}")
      Process.sleep(1000 * retries)
      wait_until_connected(socket, retries + 1, pid)
    end
  end

  def handle_info(%Message{event: message, payload: payload}, %{:sensor_id => sensor_id} = state)
      when message in ["phx_error", "phx_close"] do
    Logger.debug("#{sensor_id} handle_info: #{message}")

    Process.send_after(
      self(),
      :connect_phoenix,
      0
    )

    {:noreply, state}
  end

  def handle_info(%Message{event: message, payload: payload}, %{:sensor_id => sensor_id} = state) do
    Logger.info("#{sensor_id} Incoming Phoenix Message: #{message} #{inspect(payload)}")
    {:noreply, state}
  end

  def handle_info(msg, %{:sensor_id => sensor_id} = state) do
    Logger.info("#{sensor_id} handle_info:catch all: #{inspect(msg)}")
    {:noreply, state}
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sensocto.Registry, "#{__MODULE__}_#{identifier}"}}
  end
end
