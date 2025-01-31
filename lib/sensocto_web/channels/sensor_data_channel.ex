defmodule SensoctoWeb.SensorDataChannel do
  # alias Sensocto.Broadway.Counter
  use SensoctoWeb, :channel
  require Logger
  # alias Sensocto.Broadway.BufferingProducer
  # alias Sensocto.DeviceSupervisor
  # alias Sensocto.Sensors.SensorAttributeAgent
  # alias Sensocto.Sensors.SensorSupervisor
  alias Sensocto.SimpleSensor
  alias SensoctoWeb.Sensocto.Presence

  def init(args) do
    Logger.info("Channel init #{inspect(args)}")
  end

  # Store the device ID in the socket's assigns when joining the channel
  @impl true

  def join(
        "sensor_data:" <> sensor_id,
        %{
          "connector_id" => _connector_id,
          "connector_name" => _connector_name,
          "sensor_id" => sensor_id,
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

      case Sensocto.SensorsDynamicSupervisor.add_sensor(
             sensor_id,
             Sensocto.Utils.string_keys_to_atom_keys(params)
           ) do
        {:ok, pid} when is_pid(pid) ->
          Logger.debug("Added sensor #{sensor_id}")

        {:ok, :already_started} ->
          Logger.debug("Sensor already started #{sensor_id}")

        {:error, reason} ->
          Logger.debug("error adding sensor: #{inspect(reason)}")
          # {:error, reason}
      end

      {
        :ok,
        socket
        |> assign(:sensor_id, sensor_id)
        # |> assign(:sensor_params, params)
      }
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  # @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
  #        {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurement",
        %{"payload" => payload, "timestamp" => timestamp, "uuid" => uuid} =
          _sensor_measurement_data,
        socket
      ) do
    # :telemetry.execute(
    #   [:sensocto, :sensors, :messages, :measurement],
    #   %{count: 1},
    #   %{sensor_id: socket.assigns.sensor_id}
    # )

    # sensor_id: socket.assigns.sensor_id
    ## :telemetry.execute([:sensocto, :sensors, :messages, :measurement], %{value: 1}, %{
    # })

    # :telemetry.span(
    #   [:sensocto, :sensors, :messages],
    #   %{measurement: 1},
    #   fn ->
    with :ok <-
           SimpleSensor.put_attribute(socket.assigns.sensor_id, %{
             :id => uuid,
             :timestamp => timestamp,
             :payload => payload
           }) do
      Logger.debug(
        "SimpleSensor data sent sensor_id: #{socket.assigns.sensor_id}, uuuid: #{uuid}, timestamp: #{timestamp}, payload: #{payload}"
      )

      :ok
    else
      {:error, _} ->
        Logger.info(
          "SimpleSensor data error for sensor: #{socket.assigns.sensor_id},  uuid: #{uuid}"
        )

        :error
    end

    {:noreply, socket}
    # end
    # )
  end

  @impl true
  # @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
  #        {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurement",
        message,
        socket
      ) do
    Logger.debug("Unknown measurement #{inspect(message)}")
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

  @impl true
  @spec handle_info(:after_join | :disconnect, any()) :: {:noreply, any()}
  def handle_info(:disconnect, socket) do
    # Explicitly remove a sensor from presence when it disconnects

    Logger.debug("DISCONNECT #{inspect(socket.assigns)}")
    disconnect_sensor_supervisor(socket.assigns.sensor_id)
    Presence.untrack(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id)
    # push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    Logger.debug("after join")

    Presence.track(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id, %{
      sensor_id: socket.assigns.sensor_id,
      online_at: System.system_time(:millisecond)
    })

    # push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(payload) do
    if Map.has_key?(payload, "bearer_token") do
      true
    else
      false
    end
  end

  @impl true
  @spec terminate(any(), Phoenix.Socket.t()) :: :ok
  def terminate(reason, socket) do
    case socket.assigns.sensor_id do
      sensor_id when is_binary(sensor_id) ->
        Logger.debug("Channel terminated for sensor: #{sensor_id}, #{inspect(reason)}")
        disconnect_sensor_supervisor(socket.assigns.sensor_id)
        Presence.untrack(socket.channel_pid, "sensordata:all", socket.assigns.sensor_id)

      _ ->
        Logger.debug("Channel terminated for connection without sensor_id #{inspect(reason)}")
    end

    push(socket, "presence_state", Presence.list(socket))

    :ok
  end

  defp disconnect_sensor_supervisor(sensor_id) do
    case Sensocto.SensorsDynamicSupervisor.remove_sensor(sensor_id) do
      :ok ->
        Logger.debug("Removed sensor #{sensor_id}")

      :error ->
        Logger.debug("error removing sensor #{sensor_id}")
        # {:error, reason}
    end
  end
end
