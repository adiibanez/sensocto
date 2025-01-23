defmodule Sensocto.SensorSimulatorGenServer do
  use GenServer
  require Logger
  alias PhoenixClient.{Socket, Channel, Message}
  alias NimbleCSV.RFC4180, as: CSV

  @socket_opts [
    # url: "ws://localhost:4000/socket/websocket"
    url: "wss://sensocto.fly.dev/socket/websocket"
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
    GenServer.start_link(__MODULE__, config, name: via_tuple(sensor_id))
  end


  # client



  # GenServer Callbacks
  @impl true
  def init(%{:sensor_id => sensor_id} = config) do

    case PhoenixClient.Socket.start_link(@socket_opts) do
      {:ok, socket} ->
        wait_until_connected(socket)

        uuid = Enum.random(@uuid_attributes)
        topic = "sensor_data:" <> sensor_id

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
            IO.puts("Joined channel successfully for sensor #{sensor_id}")
            # Schedule the first message
           schedule_send_message(sensor_id, channel, uuid, config)
            {:ok, config}

          {:error, reason} ->
            IO.puts("Failed to join channel: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        IO.puts("Failed to connect to socket: #{inspect(reason)}")
        {:stop, reason}

    end
    {:ok, config}
  end

  @impl true
    def handle_info({:send_message, sensor_id, channel, uuid, config}, state) do
         case fetch_sensor_data(sensor_id, config) do
          {:ok, data} ->
             new_state = Map.update(state, :queue, data, &(&1))
             IO.inspect(new_state)
             schedule_process_queue(sensor_id, channel, uuid)
            {:noreply, new_state}
          _ ->
            schedule_send_message(sensor_id, channel, uuid, config)
             {:noreply, state}
        end
    end

  @impl true
  def handle_info({:process_queue, sensor_id, channel, uuid}, state) do
      process_queue(state, channel, uuid)
  end

  @impl true
  def handle_info({:push_message, channel, message}, state) do
    if state.config[:phoenix_channel] do
      PhoenixClient.Channel.push_async(channel, "measurement", message)
        {:noreply, state}
      else
        {:noreply, state}
    end
  end

  def handle_info(%Message{event: _message, payload: _payload}, state) do
    # IO.puts("Incoming Message: #{message} #{inspect(payload)}")
    {:noreply, state}
  end

  # A helper function to interact with the GenServer
  def get_data(sensor_id) do
    GenServer.call(via_tuple(sensor_id), :get_data)
  end

  # Private Functions
 defp process_queue(state, channel, uuid) do
       case state.queue do
           [] ->
                :noop
             [head | tail] ->
               %{timestamp: timestamp, delay: delay, value: value} = head
               message = %{
                "payload" => value,
                "timestamp" => timestamp,
                 "uuid" => uuid
                }
                  if state[:phoenix_channel] do
                     Process.send_after(self(),  {:push_message, channel, message}, delay * 1000)
                   end
               new_state = Map.update(state, :queue, tail, &(&1))

               {delay_s, _} = Float.parse("#{delay}")

                Process.send_after(self(),  {:process_queue, state.sensor_id, channel, uuid},  (round(delay_s) * 1000))
            {:noreply, new_state}
         end
  end
  defp wait_until_connected(socket) do
    unless PhoenixClient.Socket.connected?(socket) do
      Process.sleep(100)
      wait_until_connected(socket)
    end
  end

  defp schedule_send_message(sensor_id, channel, uuid, config) do
    Process.send_after(
      self(),
      {:send_message, sensor_id, channel, uuid, config},
      :rand.uniform(@interval)
    )
  end

   def schedule_process_queue(sensor_id, channel, uuid) do
      Process.send_after(
       self(),
      {:process_queue, sensor_id, channel, uuid},
      10
      )
  end
  def fetch_sensor_data(sensor_id, config) do
    duration =  config[:duration]
   sampling_rate = config[:sampling_rate]
   heart_rate = config[:heart_rate]
    respiratory_rate = config[:respiratory_rate]
     scr_number = config[:scr_number]
    burst_number = config[:burst_number]
    sensor_type = config[:sensor_type]
   try do
        System.cmd("python3", [
        "../sensocto-simulator.py",
        "--mode",
           "csv",
        "--sensor_id",
         sensor_id,
        "--sensor_type",
         sensor_type,
         "--duration",
        "#{duration}",
         "--sampling_rate",
        "#{sampling_rate}",
          "--heart_rate",
        "#{heart_rate}",
          "--respiratory_rate",
        "#{respiratory_rate}",
         "--scr_number",
        "#{scr_number}",
        "--burst_number",
        "#{burst_number}"
     ])
    |>  (fn {output, 0} ->
        output
          |> String.trim()
           |> CSV.parse_string()
          |>  Enum.drop(1)
         |> Enum.map(fn item ->
           %{
             timestamp: String.to_integer(Enum.at(item, 0)),
             delay: String.to_float(Enum.at(item, 1)),
             value: String.to_float(Enum.at(item, 2))
           }
         end)
          |>  (fn data ->
            {:ok, data}
           end).()
      {output, status} ->
         IO.puts("Error executing python script")
          IO.inspect(output)
         IO.inspect(status)
        :error
      end).()
      rescue
           e ->
          IO.puts("Error executing python script")
          IO.inspect(e)
         :error
    end
   end

  defp generate_random_sensor_id do

    #:crypto.strong_rand_bytes(8)
    #|> Base.encode64()
    # Shorten for simplicity
    #|> binary_part(0, 8)

    uuid_fragment = Enum.take(String.split(UUID.uuid1(), "-"), 1) |> List.last()
    "Sim:" <> uuid_fragment

  end

  defp via_tuple(sensor_id), do: {:via, Registry, {SensorSimulatorRegistry, sensor_id}}
end
