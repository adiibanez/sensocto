defmodule Sensocto.SensorSimulatorGenServer do
  use GenServer
  require Logger
  alias PhoenixClient.{Socket, Channel, Message}
  alias Sensocto.BiosenseData

  @socket_opts [
    url: "ws://localhost:4000/socket/websocket"
    # url: "wss://sensocto.fly.dev/socket/websocket"
  ]

  # Max interval in milliseconds for sending messages
  @interval 2000

  # List of UUID attributes to select from
  @uuid_attributes [
    "61d20a90-71a1-11ea-ab12-0800200c9a66",
    "00002a37-0000-1000-8000-00805f9b34fb",
    "feb7cb83-e359-4b57-abc6-628286b7a79b",
    "00002a19-0000-1000-8000-00805f9b34fb"
  ]

  # def update_connected_state(state) do

  #   socket = Map.get(state, :phoenix_socket)

  #   {:ok, state
  #   |> Map.update(:phoenix_connected, PhoenixClient.Socket.connected?(socket))
  # }
  # end

  # Public API
  def start_link(%{:sensor_id => sensor_id} = config) do
    Logger.info("start_link #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple(sensor_id))
  end

  # GenServer Callbacks
  @impl true
  def init(%{:sensor_id => sensor_id} = config) do
    Logger.info("#{sensor_id} init2 #{inspect(config)}")

    # Process.send_after(
    #   self(),
    #   :get_data,
    #   500
    # )

    # Process.send_after(
    #   self(),
    #   :connect_phoenix,
    #   1000
    # )

    Process.send_after(
      self(),
      :process_queue,
      :rand.uniform(2000)
    )

    new_config = %{
      :phoenix_connected => false,
      :phoenix_channel => nil,
      :phx_messages_queue => [],
      :batch_timeout_scheduled => false,
      :messages_queue => [],
      :get_data_updating_data => false
    }

    {
      :ok,
      config
      |> Map.merge(new_config)
      # |> Map.put(:messages_queue, [])}
      # |> Map.put(:get_data_updating_data, false
    }
  end

  @impl true
  def handle_info(:delay_done, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} Delay done")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  @impl true
  def handle_info({:process_queue, delay}, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} handle_info:process_queue delayed #{delay} ms")
    Process.send_after(self(), :delay_done, delay)
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_queue, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} handle_info:process_queue")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  # empty queue handling

  @impl true
  def handle_cast(:process_queue, %{:sensor_id => sensor_id, :messages_queue => []} = state) do
    Logger.info("#{sensor_id} Empty queue, get new data")

    Process.send_after(
      self(),
      :get_data,
      0
    )

    Process.send_after(
      self(),
      :process_queue,
      3000
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:sensor_id => sensor_id, :messages_queue => [], :phoenix_connected => phoenix_connected} = state
      )
      when not phoenix_connected do
    Logger.info("#{sensor_id} No messages, no phoenix")

    Process.send_after(
      self(),
      :get_data,
      0
    )

    Process.send_after(
      self(),
      :connect_phoenix,
      0
    )

    Process.send_after(
      self(),
      :process_queue,
      500
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:sensor_id => sensor_id, :messages_queue => [head | tail], :phoenix_connected => phoenix_connected} = state
      )
      when not phoenix_connected do
    Logger.info("#{sensor_id} Have messages but no phoenix")

    Process.send_after(
      self(),
      :connect_phoenix,
      0
    )

    Process.send_after(
      self(),
      :process_queue,
      500
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:sensor_id => sensor_id, :messages_queue => [head | tail], :phoenix_connected => phoenix_connected} = state
      )
      when phoenix_connected do
    Logger.debug(
      "#{sensor_id} Got message, phoenix_connected: #{state.phoenix_connected} HEAD: #{inspect(head)} TAIL: #{Enum.count(tail)}"
    )

    # fetch new data if only 20% of the duration is left
    if(Enum.count(tail) < state[:sampling_rate] * (state[:duration] * 0.2)) do
      Logger.debug("#{sensor_id} Low on messages, :get_data")

      Process.send_after(
        self(),
        :get_data,
        0
      )
    end

    Process.send_after(
      self(),
      {:push_message, head},
      0
    )

    {:noreply, state |> Map.put(:messages_queue, tail)}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:sensor_id => sensor_id} = state
      ) do
    Logger.info("#{sensor_id} Default process_queue queue #{inspect(state)}")

    Process.send_after(
      self(),
      :process_queue,
      1000
    )

    {:noreply, state}
  end

  def handle_info(:connect_phoenix, %{:sensor_id => sensor_id} = state) do
    Logger.info("#{sensor_id} handle_info:connect_phoenix")
    GenServer.cast(self(), :connect_phoenix)
    {:noreply, state}
  end

  def handle_cast(:connect_phoenix, %{:sensor_id => sensor_id} = config) do
    Logger.info("#{sensor_id} Connect to phoenix")

    parent = self()

    case PhoenixClient.Socket.start_link(@socket_opts) do
      {:ok, socket} ->
        wait_until_connected(socket, 0, parent)

        uuid = Enum.random(@uuid_attributes)
        topic = "sensor_data:" <> config[:sensor_id]

        Logger.debug("#{sensor_id} Connecting ... #{topic}")

        join_meta = %{
          device_name: config[:device_name],
          batch_size: 1,
          connector_id: config[:connector_id],
          connector_name: config[:connector_name],
          sampling_rate: config[:sampling_rate],
          sensor_id: config[:sensor_id],
          sensor_name: config[:sensor_name],
          sensor_type: config[:sensor_type],
          bearer_token: "fake"
        }

        case PhoenixClient.Channel.join(socket, topic, join_meta) do
          {:ok, _response, channel} ->
            Logger.debug("#{sensor_id} Joined channel successfully for sensor #{config[:sensor_id]}")
            # Schedule the first message
            # schedule_send_message(sensor_id, channel, uuid, config)

            Process.send_after(
              parent,
              :process_queue,
              200
            )

            {:noreply,
             config
             |> Map.put(:phoenix_socket, socket)
             |> Map.put(:phoenix_channel, channel)
             |> Map.put(:phoenix_connected, true)}

          {:error, reason} ->
            Logger.warning("#{sensor_id} Failed to join channel: #{inspect(reason)}")

            Process.send_after(
              self(),
              :connect_phoenix,
              0
            )

            {:noreply, config |> Map.put(:phoenix_connected, false)}
            # {:stop, reason}
        end

      {:error, reason} ->
        Logger.warning("#{sensor_id} Failed to connect to socket: #{inspect(reason)}")

        Process.send_after(
          self(),
          :connect_phoenix,
          0
        )

        {:noreply, config |> Map.put(:phoenix_connected, false)}
        # {:stop, reason}
    end
  end

  @impl true
  def handle_info({:push_message, message}, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} handle_info:push_message")
    parent = self()
    GenServer.cast(parent, {:push_message, message})
    {:noreply, state}
  end

  def handle_cast(
        {:push_message, message},
        %{:sensor_id => sensor_id, :phx_messages_queue => phx_messages_queue} = state
      ) do
    new_queue = phx_messages_queue ++ [message]
    batch_size = state[:batch_size] || 10
    batch_timeout = state[:batch_timeout] || 5000

    {delay_s, _} = Float.parse("#{message.delay}")
    delay_ms_tmp = round(delay_s * 1000.0)
    {delay_ms, _} = Integer.parse("#{delay_ms_tmp}")

    Logger.debug("#{sensor_id} push_message, Delay process_queue #{inspect(message.delay)}")

    Process.send_after(
      self(),
      {:process_queue, delay_ms_tmp},
      delay_ms_tmp
    )

    Logger.debug(
      "#{sensor_id} PHX Queue: #{length(new_queue)}, batch_size: #{batch_size}, batch_timeout: #{batch_timeout} batch_timeout_scheduled: #{state[:batch_timeout_scheduled]}"
    )

    if length(new_queue) >= batch_size do
      Logger.debug("#{sensor_id} send_batch, pushing phx-messages to phoenix #{length(new_queue)}")
      send_batch(new_queue, state)
    else
      Logger.debug("#{sensor_id} adding phx-messages to queue #{length(new_queue)}")

      unless state[:batch_timeout_scheduled] do
        Logger.debug("#{sensor_id} Scheduling batch timeout")
        Process.send_after(self(), :batch_timeout, batch_timeout)
      end

      {:noreply,
       state
       |> Map.put(:phx_messages_queue, new_queue)
       |> Map.put(:batch_timeout_scheduled, true)}
    end
  end

  defp send_batch(messages, %{:sensor_id => sensor_id} = state) do
    phoenix_socket = Map.get(state, :phoenix_socket)
    socket_state = PhoenixClient.Socket.connected?(phoenix_socket)

    if state[:phoenix_channel] != nil do
      Logger.info("#{sensor_id} PHX Sending Phoenix Messages: #{length(messages)}, #{inspect(messages)}")

      Enum.each(messages, fn message ->
        phoenix_message = %{
          "payload" => message.payload,
          "timestamp" => :os.system_time(:milli_seconds),
          "uuid" => state[:sensor_type]
        }

        PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", phoenix_message)
      end)

      {:noreply,
       state
       |> Map.put(:phx_messages_queue, [])
       |> Map.put(:phoenix_connected, socket_state)
       |> Map.put(:batch_timeout_scheduled, false)}
    else
      {:noreply, state |> Map.put(:phoenix_connected, false)}
    end
  end

  @impl true
  def handle_info(:batch_timeout, %{:sensor_id => sensor_id} = state) do
    Logger.info("#{sensor_id} batch timeout #{length(state[:phx_messages_queue])}")

    if length(state[:phx_messages_queue]) > 0 do
      send_batch(state[:phx_messages_queue], state)
    else
      {:noreply, state |> Map.put(:batch_timeout_scheduled, false)}
    end
  end

  def handle_info(:get_data, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} handle_info:get_data")
    case Map.get(state, :get_data_updating_data) do
      true -> {:noreply, state}
      _ -> GenServer.cast(self(), :get_data)
    end

    {:noreply, state}
  end

  def handle_info({:get_data_result, data}, %{:sensor_id => sensor_id} = state) do
    Logger.info("#{sensor_id} got data: #{Enum.count(data)}")
    newstate = Map.put(state, :messages_queue, Map.get(state, :messages_queue) ++ data)

    # Process.send_after(self(), :process_queue, 500)
    {:noreply, newstate |> Map.put(:get_data_updating_data, false)}
  end

  @impl true
  def handle_cast(:get_data, %{:sensor_id => sensor_id} = state) do
    Logger.debug("#{sensor_id} :get_data cast received")

    Process.send_after(
      :"biosense_data_server_#{:rand.uniform(4) + 1}",
      {:get_data, self(), state},
      0
    )

    {:noreply, state |> Map.put(:get_data_updating_data, true)}
  end

  def handle_info(%Message{event: message, payload: payload}, %{:sensor_id => sensor_id} = state)
      when message in ["phx_error", "phx_close"] do
    Logger.debug("#{sensor_id} handle_info: #{message}")

    Process.send_after(
      self(),
      :connect_phoenix,
      0
    )

    Process.send_after(
      self(),
      :process_queue,
      1000
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

  # Logger.info("Incoming Message: #{message} #{inspect(payload)}")
  ## def handle_info(%Message{event: message, payload: payload}, state) do
  #   {:noreply, state}
  # end

  defp wait_until_connected(socket, retries \\ 0, pid) do
    Logger.debug("wait_until_connected #{retries} #{inspect(pid)}")

    unless PhoenixClient.Socket.connected?(socket) or retries > 5 do
      Logger.debug("Wait 500ms until connected #{retries} #{inspect(pid)}")
      Process.sleep(500)
      wait_until_connected(socket, retries + 1, pid)
    end

    Logger.debug("send another :connect_phoenix #{retries} #{inspect(pid)}")

    # Process.send_after(
    #  pid,
    #  :connect_phoenix,
    #  0
    # )
  end

  defp generate_random_sensor_id do
    # :crypto.strong_rand_bytes(8)
    # |> Base.encode64()
    # Shorten for simplicity
    # |> binary_part(0, 8)

    uuid_fragment = Enum.take(String.split(UUID.uuid1(), "-"), 1) |> List.last()
    "Sim:" <> uuid_fragment
  end

  defp via_tuple(sensor_id), do: {:via, Registry, {SensorSimulatorRegistry, sensor_id}}
end
