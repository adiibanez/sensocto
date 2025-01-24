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

  # Public API
  def start_link(%{:sensor_id => sensor_id} = config) do
    Logger.info("start_link #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple(sensor_id))
  end

  # GenServer Callbacks
  @impl true
  def init(%{:sensor_id => sensor_id} = config) do
    Logger.info("init #{inspect(config)}")

    Process.send_after(
     self(),
     :get_data,
     500
    )

    Process.send_after(
     self(),
     :connect_phoenix,
    0
    )


    # case GenServer.call(self(), :connect_phoenix) do
    #  {:ok, state} -> Logger.info("Connected to Phoenix #{inspect(state)}");
    #  {:error} -> Logger.error("Failed to connect to Phoenix #{inspect(config)}")
    # end
    {:ok, config |> Map.put(:phoenix_channel, nil)}
  end

  def handle_info(:process_queue, state) do
    Logger.info("handle_info:process_queue")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  def handle_info({:process_queue, delay}, state) do
    Logger.info("handle_info:process_queue delayed #{delay} ms")
    Process.sleep(delay)
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end


  @impl true
  def handle_cast(
        :process_queue,
        %{:messages_queue => [head | tail], :phoenix_channel => phoenix_channel} = state
      ) do
    Logger.info("Got message, HEAD: #{inspect(head)} TAIL: #{Enum.count(tail)}")

    Process.send_after(
      self(),
      {:push_message, head},
      0
    )
    {:noreply, state |> Map.put(:messages_queue, tail)}
  end

  @impl true
  def handle_cast(:process_queue, %{:messages_queue => []} = state) do
    Logger.info("Empty queue, get new data")

    Process.send_after(
     self(),
     :get_data,
     0
    )

    {:noreply, state}
  end

  def handle_cast(:process_queue, %{:messages_queue => {:error, _}} = state) do
    Logger.info("Faulty queue, get data")

    Process.send_after(
      self(),
      :get_data,
      0
    )

    {:noreply, state |> Map.put(:updating_data, true)}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:messages_queue => [head | tail], :phoenix_channel => nil} = state
      ) do

    Logger.info("Have messages but no phoenix : #{head} TAIL: #{tail}")

    Process.send(
      self(),
      :connect_phoenix
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :process_queue,
        state
      ) do
    Logger.info("Default process_queue queue #{inspect(state)}")

    Process.send_after(
      self(),
      :process_queue,
      500
    )

    {:noreply, state}
  end

  def handle_info(:connect_phoenix, state) do
    # case  do
    #  :noreply -> {:noreply, state}
    #  :error -> Logger.info("Problem processing #{inspect(message)}")
    # end
    GenServer.cast(self(), :connect_phoenix)
    # Process.send(self(), :process_queue)
    {:noreply, state}
  end

  def handle_cast(:connect_phoenix, config) do
    Logger.info("Connect to phoenix, #{inspect(config)}")

    case PhoenixClient.Socket.start_link(@socket_opts) do
      {:ok, socket} ->
        wait_until_connected(socket)

        uuid = Enum.random(@uuid_attributes)
        topic = "sensor_data:" <> config[:sensor_id]

        IO.puts("Connecting ... #{topic}")

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
            IO.puts("Joined channel successfully for sensor #{config[:sensor_id]}")
            # Schedule the first message
            # schedule_send_message(sensor_id, channel, uuid, config)

            {:noreply,
             config
             |> Map.put(:phoenix_socket, socket)
             |> Map.put(:phoenix_channel, channel)
             |> IO.inspect()}

          {:error, reason} ->
            IO.puts("Failed to join channel: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        IO.puts("Failed to connect to socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_info({:push_message, message}, state) do
    # case  do
    #  :noreply -> {:noreply, state}
    #  :error -> Logger.info("Problem processing #{inspect(message)}")
    # end
    #{delay_s, _} = Float.parse("#{message.delay}")

    #Logger.info("Going to sleep for #{delay_s * 1000} ms")
    #{delay_ms, _} = Integer.parse("#{delay_s * 1000}")

    parent = self()
    GenServer.cast(parent, {:push_message, message})

    #GenServer.cast(self(), {:push_message, message})
    # Process.send(self(), :process_queue)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:push_message, message}, state) do
    Logger.debug(
      "handle_cast :push_message #{inspect(message)}, #{inspect(state[:phoenix_channel])}"
    )

    if state[:phoenix_channel] != nil do
      {delay_s, _} = Float.parse("#{message.delay}")

      delay_ms_tmp = round(delay_s * 1000.0)

      Logger.info("Going to sleep for #{delay_s} s tmp: #{delay_ms_tmp}")
      {delay_ms, _} = Integer.parse("#{delay_ms_tmp}")

      Logger.debug("delay_ms: #{delay_s} #{delay_ms}")
      #Process.sleep(delay_ms)

      Logger.info("Pushing message to channel #{inspect(message.delay)}")

      phoenix_message = %{
        "payload" => message.payload,
        "timestamp" => :os.system_time(:milli_seconds),
        "uuid" => state[:sensor_type]
      }

      # {:ok, response} = PhoenixClient.Channel.push(state[:phoenix_channel], "measurement", message)
      # Logger.debug("Push response #{inspect(response)}")
      #Process.sleep(delay_ms)

      PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", phoenix_message)

      #parent = self()


      # tasks = [
      #   #Task.async(fn -> PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", message) end),
      #   #Task.async(fn -> take_shower(10) end),
      #   #Task.async(fn -> call_mum() end),
      # ]

      # Task.yield_many(tasks)
      # |> Enum.map(fn {task, result} ->
      #   case result do
      #     nil ->
      #       Task.shutdown(task, :brutal_kill)
      #       exit(:timeout)
      #     {:exit, reason} ->
      #       exit(reason)
      #     {:ok, result} ->
      #       Process.send_after(
      #   parent,
      #   :process_queue,
      #   delay_ms
      # )
      #   end
      # end)

#       Task.start_link(fn ->
#         #{:ok, response} =
#           PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", message)
#           #Process.sleep(delay_ms)

#           Process.send_after(
#         parent,
#         :process_queue,
#         delay_ms * 10
#       )

# #        send(parent, :work_is_done)
#       end)

      # receive do
      #   :work_is_done -> :ok
      # after
      #   # Optional timeout
      #   30_000 -> :timeout
      # end

      #PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", phoenix_message)

      Logger.debug(
        "going to send delayed :process_queue  #{inspect(delay_ms_tmp)}"
      )

      Process.send_after(
        self(),
        {:process_queue, delay_ms_tmp},
        delay_ms_tmp
      )

      {:noreply, state}
    else
      {:error, "No phoenix channel"}
    end
  end


  @impl true
  def handle_call({:push_message, message}, from, state) do
    Logger.debug(
      "handle_call :push_message #{inspect(message)}, #{inspect(state[:phoenix_channel])}"
    )

    if state[:phoenix_channel] != nil do
      {delay_s, _} = Float.parse("#{message.delay}")

      Logger.info("Going to sleep for #{delay_s * 1000} ms")
      {delay_ms, _} = Integer.parse("#{delay_s * 1000}")
      Process.sleep(delay_ms)

      Logger.info("Pushing message to channel #{inspect(message.delay)}")

      phoenix_message = %{
        "payload" => message.payload,
        "timestamp" => :os.system_time(:milli_seconds),
        "uuid" => state[:sensor_type]
      }

      # {:ok, response} = PhoenixClient.Channel.push(state[:phoenix_channel], "measurement", message)
      # Logger.debug("Push response #{inspect(response)}")
      #Process.sleep(delay_ms)

      parent = self()


      tasks = [
        Task.async(fn -> PhoenixClient.Channel.push(state[:phoenix_channel], "measurement", message) end),
        #Task.async(fn -> take_shower(10) end),
        #Task.async(fn -> call_mum() end),
      ]

      Task.yield_many(tasks)
      |> Enum.map(fn {task, result} ->
        case result do
          nil ->
            Task.shutdown(task, :brutal_kill)
            exit(:timeout)
          {:exit, reason} ->
            exit(reason)
          {:ok, result} ->
            Process.send_after(
        parent,
        :process_queue,
        delay_ms
      )
        end
      end)

#       Task.start_link(fn ->
#         #{:ok, response} =
#           PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", message)
#           #Process.sleep(delay_ms)

#           Process.send_after(
#         parent,
#         :process_queue,
#         delay_ms * 10
#       )

# #        send(parent, :work_is_done)
#       end)

      # receive do
      #   :work_is_done -> :ok
      # after
      #   # Optional timeout
      #   30_000 -> :timeout
      # end

      #PhoenixClient.Channel.push_async(state[:phoenix_channel], "measurement", phoenix_message)

      # Process.send_after(
      #   self(),
      #   :process_queue,
      #   0
      # )

      {:reply, state}
    else
      {:error, "No phoenix channel"}
    end
  end


  def handle_info(:get_data, state) do
    Logger.info(":get_data info received")

    case Map.get(state, :updating_data) do
      true -> {:noreply, state}
      _ -> GenServer.cast(self(), :get_data)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:get_data, state) do
    Logger.info(":get_data cast received")

    {:ok, data} = get_data(state)
    Logger.info("got data: #{Enum.count(data)}")
    newstate = Map.put(state, :messages_queue, data)
    Process.send_after(self(), :process_queue, 500)
    {:noreply, newstate |> Map.put(:updating_data, false)}

    # with
    #  {:ok, data} <- get_data(state),
    #  newstate <- Map.put(:messages_queue, data),
    #  _ <- Process.send_after(self(),:process_queue,500),
    #  do: {:noreply, newstate}
  end

  defp get_data(config) do
    # |> Map.put(:dummy_data, true)
    case BiosenseData.fetch_sensor_data(config) do
      data ->
        data

      _ ->
        {:error, "No data"}
    end
  end

  def handle_info(%Message{event: message, payload: payload}, state) do
    Logger.info("Incoming Phoenix Message: #{message} #{inspect(payload)}")
    {:noreply, state}
  end

  # Logger.info("Incoming Message: #{message} #{inspect(payload)}")
  ## def handle_info(%Message{event: message, payload: payload}, state) do
  #   {:noreply, state}
  # end

  defp wait_until_connected(socket) do
    unless PhoenixClient.Socket.connected?(socket) do
      Process.sleep(100)
      wait_until_connected(socket)
    end
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
