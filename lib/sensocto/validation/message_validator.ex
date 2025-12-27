defmodule Sensocto.Validation.MessageValidator do
  @moduledoc """
  Validates incoming WebSocket messages at the channel boundary.

  This module provides a fail-fast validation layer that rejects invalid
  messages immediately, preventing malformed data from flowing through
  the system.

  ## Usage in Channels

      def handle_in("measurement", data, socket) do
        sensor_type = socket.assigns[:sensor_type]

        case MessageValidator.validate_measurement(data, sensor_type) do
          {:ok, measurement} ->
            SimpleSensor.put_attribute(socket.assigns.sensor_id, measurement)
            {:noreply, socket}

          {:error, reason} ->
            Logger.warning("Invalid measurement rejected: \#{inspect(reason)}")
            {:reply, {:error, %{reason: inspect(reason)}}, socket}
        end
      end

  ## Validation Strategy

  The validator uses a fail-fast approach:
  1. Check required fields are present
  2. Validate attribute_id format (prevents atom exhaustion)
  3. Validate payload structure matches attribute type
  4. Only valid data passes through

  Invalid messages are rejected with descriptive error reasons.
  """

  alias Sensocto.Types.SafeKeys
  alias Sensocto.Sensors.SensorRegistry

  @type validation_result :: {:ok, term()} | {:error, term()}

  @doc """
  Validates sensor join parameters.

  Checks that all required fields are present and sensor_type is valid.

  ## Required fields
  - sensor_id
  - connector_id
  - connector_name
  - sensor_name
  - sensor_type

  ## Returns
  - `{:ok, params}` - Valid parameters
  - `{:error, reason}` - Validation failed
  """
  @spec validate_join_params(map()) :: validation_result()
  def validate_join_params(params) when is_map(params) do
    required = ["sensor_id", "connector_id", "connector_name", "sensor_name", "sensor_type"]

    with :ok <- check_required_fields(params, required),
         {:ok, _} <- SafeKeys.validate_attribute_id(params["sensor_id"]),
         {:ok, _sensor_type} <- validate_sensor_type(params["sensor_type"]) do
      {:ok, params}
    end
  end

  @doc """
  Validates a single measurement message.

  ## Parameters
  - `data` - The raw measurement map from WebSocket
  - `sensor_type` - The sensor type for payload validation

  ## Returns
  - `{:ok, measurement}` - Valid Measurement struct
  - `{:error, reason}` - Validation failed with reason
  """
  @spec validate_measurement(map(), String.t()) :: validation_result()
  def validate_measurement(data, sensor_type) when is_map(data) and is_binary(sensor_type) do
    with {:ok, _} <- SafeKeys.validate_measurement_keys(data),
         {:ok, _} <- validate_attribute_for_sensor(sensor_type, data["attribute_id"]),
         {:ok, _} <-
           SensorRegistry.validate_payload(sensor_type, data["attribute_id"], data["payload"]) do
      # Return the validated data (with string keys for now)
      {:ok, data}
    end
  end

  def validate_measurement(_, _), do: {:error, :invalid_measurement}

  @doc """
  Validates a batch of measurement messages.

  All measurements in the batch must be valid. If any measurement fails
  validation, the entire batch is rejected.

  ## Returns
  - `{:ok, measurements}` - List of valid measurements
  - `{:error, {:batch_validation_failed, count}}` - Number of failed validations
  """
  @spec validate_measurement_batch([map()], String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def validate_measurement_batch(list, sensor_type) when is_list(list) do
    results = Enum.map(list, &validate_measurement(&1, sensor_type))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, m} -> m end)}
    else
      {:error, {:batch_validation_failed, length(errors)}}
    end
  end

  def validate_measurement_batch(_, _), do: {:error, :invalid_batch}

  @doc """
  Validates an update_attributes message.

  ## Parameters
  - `action` - "register" or "unregister"
  - `attribute_id` - The attribute identifier
  - `metadata` - Additional metadata map

  ## Returns
  - `{:ok, %{action: atom, attribute_id: string, metadata: map}}` - Validated data
  - `{:error, reason}` - Validation failed
  """
  @spec validate_update_attributes(String.t(), String.t(), map()) :: validation_result()
  def validate_update_attributes(action, attribute_id, metadata)
      when is_binary(action) and is_binary(attribute_id) and is_map(metadata) do
    with {:ok, validated_action} <- SafeKeys.validate_action(action),
         {:ok, validated_attr_id} <- SafeKeys.validate_attribute_id(attribute_id),
         {:ok, safe_metadata} <- SafeKeys.safe_keys_to_atoms(metadata) do
      {:ok,
       %{
         action: String.to_existing_atom(validated_action),
         attribute_id: validated_attr_id,
         metadata: safe_metadata
       }}
    end
  end

  def validate_update_attributes(_, _, _), do: {:error, :invalid_update_attributes}

  @doc """
  Validates a command for bidirectional sensors.

  ## Parameters
  - `sensor_type` - The sensor type
  - `command` - The command map
  - `context` - Additional context (sensor_id, etc.)

  ## Returns
  - `{:ok, result}` - Command validated and processed
  - `{:error, reason}` - Validation or execution failed
  """
  @spec validate_command(String.t(), map(), map()) :: validation_result()
  def validate_command(sensor_type, command, context)
      when is_binary(sensor_type) and is_map(command) do
    with {:ok, _} <- validate_sensor_type(sensor_type),
         true <- SensorRegistry.bidirectional?(sensor_type) do
      SensorRegistry.handle_command(sensor_type, command, context)
    else
      false -> {:error, :command_not_supported}
      error -> error
    end
  end

  def validate_command(_, _, _), do: {:error, :invalid_command}

  # Private helpers

  defp check_required_fields(params, required) do
    missing = Enum.filter(required, &(!Map.has_key?(params, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_sensor_type(type) when is_binary(type) do
    if SensorRegistry.valid_sensor_type?(type) do
      {:ok, type}
    else
      {:error, :unknown_sensor_type}
    end
  end

  defp validate_sensor_type(_), do: {:error, :invalid_sensor_type}

  defp validate_attribute_for_sensor(sensor_type, attribute_id) do
    if SensorRegistry.attribute_allowed?(sensor_type, attribute_id) do
      {:ok, attribute_id}
    else
      {:error, {:invalid_attribute_for_sensor, attribute_id, sensor_type}}
    end
  end
end
