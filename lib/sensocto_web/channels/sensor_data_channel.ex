defmodule SensoctoWeb.SensorDataChannel do
  @moduledoc false
  use SensoctoWeb, :channel
  require Logger

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias Sensocto.Types.SafeKeys
  alias SensoctoWeb.Sensocto.Presence

  def init(args) do
    :logger.set_module_level(SensoctoWeb.SensorDataChannel, :debug)
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

    Logger.debug("ASH params #{inspect(params)}")

    # Use safe key conversion to prevent atom exhaustion attacks
    {:ok, atom_params} = SafeKeys.safe_keys_to_atoms(params)

    request =
      atom_params
      |> Map.delete(:bearer_token)
      |> Map.delete(:attributes)
      |> Map.delete(:batch_size)
      |> Map.delete(:sampling_rate)

    Logger.debug("ASH request #{inspect(request)}")

    # Sensocto.Sensors.SensorManager.validate_sensor(request)

    case Sensocto.Sensors.SensorManager
         |> Ash.Changeset.for_create(:validate_sensor, request)
         |> Ash.create!() do
      {:ok, sensor} ->
        Logger.debug("ASH validated and created sensor: #{inspect(sensor)}")

      # Now 'sensor' contains the newly created sensor resource

      {:error, :bad_request, changeset} ->
        Logger.error("ASH bad request: #{inspect(changeset)}")

      {:error, :unauthorized, reason} ->
        Logger.warning("ASH unauthorized: #{reason}")

      {:error, :not_found} ->
        Logger.warning("ASH resource not found")

      {:error, {:duplicate_record, details}} ->
        Logger.error("ASH duplicate record: #{inspect(details)}")

      {:error, changeset} ->
        Logger.error("ASH changeset error: #{inspect(changeset)}")

      response ->
        Logger.debug("ASH unknown response: #{inspect(response)}")
    end

    # with params do
    #   {:ok, validated} <- Ash.create(Sensocto.Sensors.SensorManager, :validate_sensor, params)
    #   {:ok, sensor} <-
    #     Ash.read(Sensocto.Sensors.SensorManager, :get_sensor, %{sensor_id: sensor_id})
    #   #{:ok, assign(socket, :sensor_id, sensor_id)}
    #   Logger.debug("ASH Sensor #{inspect(sensor)}")
    # end

    if authorized?(params) do
      send(self(), :after_join)

      Logger.debug("socket join #{sensor_id}", params)

      # Use safe key conversion to prevent atom exhaustion attacks
      {:ok, safe_params} = SafeKeys.safe_keys_to_atoms(params)

      # Extract username from bearer token for display purposes
      username = extract_username(params)

      safe_params_with_user =
        if username do
          Map.put(safe_params, :username, username)
        else
          safe_params
        end

      case Sensocto.SensorsDynamicSupervisor.add_sensor(sensor_id, safe_params_with_user) do
        {:ok, pid} when is_pid(pid) ->
          Logger.debug("Added sensor #{sensor_id}")

        {:ok, :already_started} ->
          Logger.debug("Sensor already started #{sensor_id}")

        {:error, reason} ->
          Logger.debug("error adding sensor: #{inspect(reason)}")
          # {:error, reason}
      end

      # Subscribe to attention changes for this sensor (backpressure protocol)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}")

      # Subscribe to system load changes for adaptive backpressure
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:load")

      # Send initial backpressure configuration to connector
      send(self(), :send_backpressure_config)

      {
        :ok,
        socket
        |> assign(:sensor_id, sensor_id)
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

    # Validate action and attribute_id to prevent atom exhaustion
    with {:ok, validated_action} <- SafeKeys.validate_action(action),
         {:ok, validated_attr_id} <- SafeKeys.validate_attribute_id(attribute_id),
         {:ok, safe_metadata} <- SafeKeys.safe_keys_to_atoms(metadata) do
      # Convert validated action to atom (safe since we validated it)
      action_atom = String.to_existing_atom(validated_action)

      SimpleSensor.update_attribute_registry(
        socket.assigns.sensor_id,
        action_atom,
        validated_attr_id,
        safe_metadata
      )

      Logger.debug(
        "SimpleSensor update_attribute_registry sensor_id: #{socket.assigns.sensor_id}, action: #{action}, attribute_id: #{attribute_id}, metadata: #{inspect(metadata)}"
      )

      {:noreply, socket}
    else
      {:error, :invalid_action} ->
        Logger.warning("Invalid action received: #{inspect(action)}")
        {:reply, {:error, %{reason: "invalid_action"}}, socket}

      {:error, :invalid_attribute_id} ->
        Logger.warning("Invalid attribute_id received: #{inspect(attribute_id)}")
        {:reply, {:error, %{reason: "invalid_attribute_id"}}, socket}

      {:error, reason} ->
        Logger.info(
          "SimpleSensor update_attribute_registry error for sensor: #{socket.assigns.sensor_id}, attribute_id: #{attribute_id}, reason: #{inspect(reason)}"
        )

        {:noreply, socket}
    end
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

    # Validate measurement keys before processing
    with {:ok, _} <- SafeKeys.validate_measurement_keys(sensor_measurement_data),
         {:ok, safe_data} <- SafeKeys.safe_keys_to_atoms(sensor_measurement_data) do
      SimpleSensor.put_attribute(socket.assigns.sensor_id, safe_data)

      Logger.debug(
        "SimpleSensor data sent sensor_id: #{socket.assigns.sensor_id}, SINGLE: #{inspect(sensor_measurement_data)}"
      )

      {:noreply, socket}
    else
      {:error, :invalid_attribute_id} ->
        Logger.warning("Invalid attribute_id in measurement: #{inspect(attribute_id)}")
        {:reply, {:error, %{reason: "invalid_attribute_id"}}, socket}

      {:error, {:missing_fields, fields}} ->
        Logger.warning("Missing fields in measurement: #{inspect(fields)}")
        {:reply, {:error, %{reason: "missing_fields", fields: fields}}, socket}

      {:error, reason} ->
        Logger.info(
          "SimpleSensor data error for sensor: #{socket.assigns.sensor_id}, attribute_id: #{attribute_id}, reason: #{inspect(reason)}"
        )

        {:noreply, socket}
    end
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
    # Validate and convert all measurements safely
    validated_results =
      Enum.map(measurements_list, fn item ->
        with {:ok, _} <- SafeKeys.validate_measurement_keys(item),
             {:ok, safe_item} <- SafeKeys.safe_keys_to_atoms(item) do
          {:ok, safe_item}
        else
          error -> error
        end
      end)

    # Check if all validations passed
    {valid, invalid} = Enum.split_with(validated_results, &match?({:ok, _}, &1))

    if Enum.empty?(invalid) do
      safe_measurements = Enum.map(valid, fn {:ok, m} -> m end)

      Logger.debug("BATCH: #{length(safe_measurements)}")

      SimpleSensor.put_batch_attributes(socket.assigns.sensor_id, safe_measurements)

      Logger.debug(
        "SimpleSensor data sent sensor_id: #{socket.assigns.sensor_id}, BATCH: #{length(safe_measurements)}"
      )

      {:noreply, socket}
    else
      Logger.warning(
        "Invalid batch measurements rejected: #{length(invalid)} of #{length(measurements_list)} failed validation"
      )

      {:reply, {:error, %{reason: "invalid_batch", failed_count: length(invalid)}}, socket}
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
    # Note: We no longer remove the sensor here - termination is handled in terminate/2
    # This prevents the dual-termination race condition where both :disconnect and
    # terminate/2 would try to remove the sensor
    Logger.debug(
      "DISCONNECT event received for #{inspect(socket.assigns.sensor_id)} - deferring cleanup to terminate/2"
    )

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

  # Send initial backpressure configuration to connector
  def handle_info(:send_backpressure_config, socket) do
    case Map.get(socket.assigns, :sensor_id) do
      nil ->
        {:noreply, socket}

      sensor_id ->
        config = get_backpressure_config(sensor_id)
        push(socket, "backpressure_config", config)
        Logger.debug("Sent initial backpressure config for #{sensor_id}: #{inspect(config)}")
        {:noreply, socket}
    end
  end

  # Handle attention changes from AttentionTracker - push new backpressure config
  def handle_info({:attention_changed, %{sensor_id: sensor_id, level: new_level}}, socket) do
    if Map.get(socket.assigns, :sensor_id) == sensor_id do
      config = get_backpressure_config(sensor_id)
      push(socket, "backpressure_config", config)

      Logger.info(
        "Attention changed for sensor #{sensor_id} to #{new_level}, pushed backpressure config: #{inspect(config)}"
      )
    end

    {:noreply, socket}
  end

  # Ignore attention changes for attributes (we only care about sensor-level)
  def handle_info({:attention_changed, %{attribute_id: _}}, socket) do
    {:noreply, socket}
  end

  # Handle system load changes - push updated backpressure config to client
  def handle_info({:system_load_changed, %{level: new_level}}, socket) do
    case Map.get(socket.assigns, :sensor_id) do
      nil ->
        {:noreply, socket}

      sensor_id ->
        config = get_backpressure_config(sensor_id)
        push(socket, "backpressure_config", config)

        Logger.debug(
          "System load changed to #{new_level}, pushed backpressure config for #{sensor_id}: paused=#{config.paused}"
        )

        {:noreply, socket}
    end
  end

  # Security: Validate bearer tokens against stored credentials
  # H-003 Fix: Previously only checked if bearer_token key existed, not its validity.
  # Now properly validates JWT tokens using AshAuthentication.
  defp authorized?(%{"sensor_id" => sensor_id} = params) do
    case Map.get(params, "bearer_token") do
      nil ->
        Logger.warning("Authorization failed: missing bearer_token for sensor #{sensor_id}")
        false

      "" ->
        Logger.warning("Authorization failed: empty bearer_token for sensor #{sensor_id}")
        false

      token when is_binary(token) ->
        verify_bearer_token(token, sensor_id)

      _invalid ->
        Logger.warning("Authorization failed: invalid bearer_token type for sensor #{sensor_id}")
        false
    end
  end

  # Verify the bearer token is a valid JWT issued by this application
  defp verify_bearer_token(token, sensor_id) do
    case AshAuthentication.Jwt.verify(token, :sensocto) do
      {:ok, _claims, _resource} ->
        Logger.debug("Authorization successful for sensor #{sensor_id}")
        true

      {:error, reason} ->
        Logger.warning(
          "Authorization failed: invalid bearer_token for sensor #{sensor_id}, reason: #{inspect(reason)}"
        )

        false

      :error ->
        Logger.warning(
          "Authorization failed: invalid bearer_token for sensor #{sensor_id}, reason: :error"
        )

        false
    end
  end

  # Extract username from bearer token for display in composite views
  # Uses the local part of the email (before @) as the username
  defp extract_username(%{"bearer_token" => token}) when is_binary(token) and token != "" do
    case AshAuthentication.Jwt.verify(token, :sensocto) do
      {:ok, %{"sub" => subject}, resource} when not is_nil(resource) ->
        # The subject contains "user?id=<uuid>", use get_by_subject action to load user
        case Ash.read_one(
               Ash.Query.for_read(resource, :get_by_subject, %{subject: subject}),
               authorize?: false
             ) do
          {:ok, %{email: email}} when not is_nil(email) ->
            # Extract local part of email as username
            email
            |> to_string()
            |> String.split("@")
            |> List.first()

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_username(_), do: nil

  @impl true
  @spec terminate(any(), Phoenix.Socket.t()) :: :ok
  def terminate(reason, socket) do
    case Map.get(socket.assigns, :sensor_id) do
      sensor_id when is_binary(sensor_id) ->
        Logger.debug("Channel terminated for sensor: #{sensor_id}, #{inspect(reason)}")

        # Fire-and-forget cleanup via TaskSupervisor (non-blocking)
        # This prevents terminate/2 from blocking on Presence and DynamicSupervisor calls
        channel_pid = socket.channel_pid

        Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
          cleanup_sensor_connection(sensor_id, channel_pid)
        end)

      _ ->
        Logger.debug("Channel terminated for connection without sensor_id #{inspect(reason)}")
    end

    :ok
  end

  # Async cleanup of sensor connection (runs in TaskSupervisor)
  defp cleanup_sensor_connection(sensor_id, channel_pid) do
    # First untrack this connection from presence
    Presence.untrack(channel_pid, "presence:all", sensor_id)

    # Small delay to let presence state propagate
    Process.sleep(50)

    # Check if there are other active connections for this sensor
    # Only remove the sensor if no other connections exist
    presence_list = Presence.list("presence:all")
    other_connections = Map.get(presence_list, sensor_id, %{metas: []})

    case other_connections do
      %{metas: [_ | _] = metas} ->
        Logger.debug(
          "Sensor #{sensor_id} still has #{length(metas)} other connections - keeping sensor alive"
        )

      _ ->
        Logger.debug("Sensor #{sensor_id} has no other connections - removing sensor")
        disconnect_sensor_supervisor(sensor_id)
    end
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

  # Calculate backpressure configuration based on current attention level and system load
  # This is pushed to connectors so they can adjust their data transmission rates
  defp get_backpressure_config(sensor_id) do
    # Get attention level, defaulting to :none if tracker not available
    attention_level =
      try do
        AttentionTracker.get_sensor_attention_level(sensor_id)
      catch
        :exit, {:noproc, _} -> :none
      end

    # Get system load level
    {system_load, load_multiplier} =
      try do
        level = Sensocto.SystemLoadMonitor.get_load_level()
        multiplier = Sensocto.SystemLoadMonitor.get_load_multiplier()
        {level, multiplier}
      catch
        :exit, {:noproc, _} -> {:normal, 1.0}
      end

    # Base batch window and size recommendations based on attention level
    {base_batch_window, base_batch_size} =
      case attention_level do
        # Fast updates, small batches
        :high -> {100, 1}
        # Normal updates
        :medium -> {500, 5}
        # Slower updates, larger batches
        :low -> {2000, 10}
        # Minimal updates, large batches
        :none -> {5000, 20}
      end

    # Apply system load multiplier to batch window
    adjusted_batch_window = trunc(base_batch_window * load_multiplier)

    # Determine if client should pause transmission (critical load + low attention)
    paused = system_load == :critical and attention_level in [:low, :none]

    %{
      attention_level: attention_level,
      system_load: system_load,
      paused: paused,
      recommended_batch_window: adjusted_batch_window,
      recommended_batch_size: base_batch_size,
      load_multiplier: load_multiplier,
      timestamp: System.system_time(:millisecond)
    }
  end
end
