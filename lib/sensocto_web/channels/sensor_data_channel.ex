defmodule SensoctoWeb.SensorDataChannel do
  # alias Sensocto.Broadway.Counter
  use SensoctoWeb, :channel
  require Logger
  # alias Sensocto.Broadway.BufferingProducer
  alias Sensocto.DeviceSupervisor
  alias SensoctoWeb.Sensocto.Presence

  # Store the device ID in the socket's assigns when joining the channel
  @impl true
  def join("sensor_data:" <> sensor_id, params, socket) do
    if authorized?(params) do
      send(self(), :after_join)
      Logger.debug("socket join #{sensor_id}", params)

      DeviceSupervisor.add_device(sensor_id)

      socket = assign(socket, :sensor_id, sensor_id)

      {:ok,
       socket
       |> assign(:sensor_id, sensor_id)}

      # {:ok,
      # socket
      # |> assign(:user_type, payload["type"])
      # |> assign(:user_id, payload["device_id"])
      # |> assign(:device_description, payload["device_description"])}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  @spec handle_info(:after_join | :disconnect, any()) :: {:noreply, any()}
  def handle_info(:disconnect, socket) do
    # Explicitly remove a sensor from presence when it disconnects
    DeviceSupervisor.remove_device(socket.assigns.sensor_id)
    Presence.untrack(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id)
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    Logger.debug("after join")

    Presence.track(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id, %{
      sensor_id: socket.assigns.sensor_id,
      online_at: System.system_time(:millisecond)
    })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
          {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in("discovery", payload, socket) do
    # Logger.debug inspect(payload)

    broadcast!(socket, "discovery", %{
      payload:
        Map.merge(payload, %{
          "device_id" => socket.assigns.user_id,
          "device_description" => socket.assigns.device_description
        })
    })

    {:noreply, socket}
  end

  def handle_in("disconnect", payload, socket) do
    Logger.info("Disconnect", payload)
    Presence.untrack(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id)
    DeviceSupervisor.remove_device(socket.assigns.sensor_id)

    # Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal:disconnected:{payload["device_id"]}", {:measurement, payload})
    {:noreply, socket}
  end

  @impl true
  # @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
  #        {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurement",
        %{
          "payload" => _payload,
          "timestamp" => _timestamp,
          "uuid" => _uuid
        } = sensor_data,
        socket
      ) do
    # Logger.debug inspect(sensor_data)
    # Broadway.Producer.produce(Counter, payload)
    # Logger.debug(socket.assigns.sensor_id)

    # GenServer.call(Sensocto.Broadway.BufferingProducer, {:new_message, payload})
    # GenServer.cast({:via, GenStage.Supervisor, Sensocto.Broadway.BufferingProducer}, {:new_message, payload})

    ~S"""
    case Sensocto.Broadway.Counter2.get_producer_pid() do
      {:ok, producer_pid} ->
        GenStage.cast(producer_pid, {:new_message, payload})
        {:noreply, socket}
      :error ->
        {:reply, {:error, "Producer not found"}, socket}
    end
    """

    # updated_payload = Map.put(payload, "sensor_id", "#{socket.assigns.sensor_id}:#{payload["uuid"]}")
    # IO.inspect(updated_payload)
    # Logger.debug("sensor_id: #{socket.assigns.sensor_id} payload.sensor_id: #{payload["uuid"]}")
    # PubSub.broadcast(:my_pubsub, "user:123", {:user_update, %{id: 123, name: "Shane"}})
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "measurement",
      {:measurement,
       sensor_data
       |> Map.put("sensor_id", "#{socket.assigns.sensor_id}")}
    )

    # Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")

    {:noreply, socket}
  end

  def handle_in("ping", payload, socket) do
    Logger.debug(inspect(payload))
    {:reply, {:ok, payload}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (sensor_data:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
