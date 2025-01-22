defmodule SensoctoWeb.SensorDataChannel do
  # alias Sensocto.Broadway.Counter
  use SensoctoWeb, :channel
  require Logger
  # alias Sensocto.Broadway.BufferingProducer
  alias Sensocto.DeviceSupervisor
  alias SensoctoWeb.Sensocto.Presence

  # Store the device ID in the socket's assigns when joining the channel
  @impl true
  def join(
        "sensor_data:" <> sensor_id,
        %{
          "connector_id" => _connector_id,
          "connector_name" => _connector_name,
          "sensor_id" => _sensor_id,
          "sensor_name" => _sensor_name,
          "sensor_type" => _sensor_type,
          "sampling_rate" => _sampling_rate,
          "bearer_token" => _bearer_token,
          "batch_size" => _batch_size
        } = params,
        socket
      ) do
    if authorized?(params) do
      send(self(), :after_join)
      Logger.debug("socket join #{sensor_id}", params)
      IO.inspect(params)

      DeviceSupervisor.add_device(sensor_id)

      """

      %{
      "batch_size" => 1,
      "connector_id" => "00000000-0000-0000-0000-82305b3f150e",
      "connector_name" => "Vicumulator1",
      "sampling_rate" => 10,
      "sensor_id" => "Vicumulator1:heartrate",
      "sensor_name" => "Movesense 007",
      "sensor_type" => "heartrate"
      }
      """

      {:ok,
       socket =
         assign(socket, :sensor_id, sensor_id)
         |> assign(:sensor_params, params)}
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

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "measurement",
      {:measurement,
       sensor_data
       |> Map.put("sensor_params", socket.assigns.sensor_params)
       |> Map.put("sensor_id", "#{socket.assigns.sensor_id}")}
    )

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
