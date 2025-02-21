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

  def join(
        "sensocto:lvntest:" <> connector_id,
        params,
        socket
      ) do
    Logger.debug("JOIN LVN test connector #{connector_id} : #{inspect(params)}")

    {:ok, socket}
  end

  # Store the device ID in the socket's assigns when joining the channel
  @impl true
  @spec join(<<_::32, _::_*8>>, map(), Phoenix.Socket.t()) ::
          {:ok, Phoenix.Socket.t()} | {:error, %{reason: String.t()}}
  def join(
        "sensocto:connector:" <> connector_id,
        %{
          "connector_id" => connector_id,
          "connector_name" => _connector_name,
          "connector_type" => _connector_typ,
          "features" => _features,
          "bearer_token" => _bearer_token
        } = params,
        socket
      ) do
    Logger.debug("JOIN connector #{connector_id} : #{inspect(params)}")

    {:ok, socket}

    # if authorized?(params) do
    #   send(self(), :after_join)

    #   Logger.debug("socket join #{sensor_id}", params)

    #   case Sensocto.SensorsDynamicSupervisor.add_sensor(
    #          sensor_id,
    #          Sensocto.Utils.string_keys_to_atom_keys(params)
    #        ) do
    #     {:ok, pid} when is_pid(pid) ->
    #       Logger.debug("Added sensor #{sensor_id}")

    #     {:ok, :already_started} ->
    #       Logger.debug("Sensor already started #{sensor_id}")

    #     {:error, reason} ->
    #       Logger.debug("error adding sensor: #{inspect(reason)}")
    #       # {:error, reason}
    #   end

    #   {
    #     :ok,
    #     socket
    #     |> assign(:sensor_id, sensor_id)
    #     # |> assign(:sensor_params, params)
    #   }
    # else
    #   {:error, %{reason: "unauthorized"}}
    # end
  end

  # Store the device ID in the socket's assigns when joining the channel
  @impl true
  @spec join(<<_::32, _::_*8>>, map(), Phoenix.Socket.t()) ::
          {:ok, Phoenix.Socket.t()} | {:error, %{reason: String.t()}}
  def join(
        "sensocto:sensor:" <> sensor_id,
        %{
          "connector_id" => connector_id,
          "connector_name" => _connector_name,
          "sensor_id" => sensor_id,
          "sensor_name" => _sensor_name,
          "attributes" => _attributes,
          "sensor_type" => _sensor_type,
          "sampling_rate" => _sampling_rate,
          "bearer_token" => _bearer_token,
          "batch_size" => _batch_size
        } = params,
        socket
      ) do
    Logger.debug("JOIN sensor #{connector_id} : #{sensor_id}")

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

  def handle_in(
        "update_attributes",
        %{"action" => action, "attribute_id" => attribute_id, "metadata" => metadata},
        socket
      ) do
    Logger.debug(
      "update attributes action #{inspect(action)}, attribute_id: #{inspect(attribute_id)}, metadata: #{inspect(metadata)}"
    )

    with :ok <-
           SimpleSensor.update_attribute_registry(
             socket.assigns.sensor_id,
             String.to_atom(action),
             String.to_atom(attribute_id),
             Sensocto.Utils.string_keys_to_atom_keys(metadata)
           ) do
      Logger.debug(
        "SimpleSensor update_attribute_registry sensor_id: #{socket.assigns.sensor_id}, action: #{action}, attribute_id:  #{attribute_id}, metadata: #{inspect(metadata)}}"
      )
    else
      {:error, _} ->
        Logger.info(
          "SimpleSensor update_attribute_registry error for sensor: #{socket.assigns.sensor_id},  attribute_id: #{attribute_id}"
        )
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
          {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurement",
        %{"payload" => _payload, "timestamp" => _timestamp, "attribute_id" => attribute_id} =
          sensor_measurement_data,
        socket
      ) do
    Logger.debug("SINGLE: #{inspect(sensor_measurement_data)}")

    with :ok <-
           SimpleSensor.put_attribute(
             socket.assigns.sensor_id,
             Sensocto.Utils.string_keys_to_atom_keys(sensor_measurement_data)
           ) do
      Logger.debug(
        "SimpleSensor data sent sensor_id: #{socket.assigns.sensor_id}, SINGLE: #{inspect(sensor_measurement_data)}}"
      )
    else
      {:error, _} ->
        Logger.info(
          "SimpleSensor data error for sensor: #{socket.assigns.sensor_id},  attribute_id: #{attribute_id}"
        )
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
          {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurements_batch",
        measurements_list,
        socket
      )
      when is_list(measurements_list) do
    if Enum.all?(measurements_list, fn item ->
         is_map(item) and
           Map.has_key?(item, "attribute_id") and
           Map.has_key?(item, "payload") and
           Map.has_key?(item, "timestamp")
       end) do
      Logger.debug("BATCH: #{length(measurements_list)}")

      atom_key_map = Enum.map(measurements_list, &Sensocto.Utils.string_keys_to_atom_keys/1)

      with :ok <-
             SimpleSensor.put_batch_attributes(socket.assigns.sensor_id, atom_key_map) do
        Logger.debug(
          "SimpleSensor data sent sensor_id: #{socket.assigns.sensor_id}, BATCH: #{length(atom_key_map)}"
        )
      else
        {:error, _} ->
          Logger.info(
            "SimpleSensor data error for sensor: #{socket.assigns.sensor_id}, BATCH: #{length(atom_key_map)}"
          )
      end

      {:noreply, socket}
    else
      Logger.debug("Invalid batch of measurements #{inspect(measurements_list)}")
      {:noreply, socket}
    end
  end

  @impl true
  @spec handle_in(<<_::32, _::_*8>>, any(), any()) ::
          {:noreply, Phoenix.Socket.t()} | {:reply, {:ok, any()}, any()}
  def handle_in(
        "measurement",
        message,
        socket
      ) do
    Logger.info("Unknown measurement, ignoring #{inspect(message)}")
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

  def handle_in(event, payload, socket) do
    Logger.debug("CATCHALL: #{event} #{inspect(payload)}")
    {:noreply, socket}
  end

  @impl true
  @spec handle_info(:after_join | :disconnect, any()) :: {:noreply, any()}
  def handle_info(:disconnect, socket) do
    # Explicitly remove a sensor from presence when it disconnects

    Logger.debug("DISCONNECT #{inspect(socket.assigns)}")
    disconnect_sensor_supervisor(socket.assigns.sensor_id)
    Presence.untrack(socket.channel_pid, "presence:all", socket.assigns.sensor_id)
    # push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    Logger.debug("after join")

    Presence.track(socket.channel_pid, "presence:all", socket.assigns.sensor_id, %{
      sensor_id: socket.assigns.sensor_id,
      online_at: System.system_time(:millisecond)
    })

    # push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{"sensor_id" => sensor_id} = params) do
    if Map.has_key?(params, "bearer_token") do
      true
    else
      Logger.debug("Unauthorized request #{sensor_id}")
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
        Presence.untrack(socket.channel_pid, "presence:all", socket.assigns.sensor_id)

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
