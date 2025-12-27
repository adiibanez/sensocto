defmodule Sensocto.Behaviours.SensorBehaviour do
  @moduledoc """
  Behaviour for implementing sensor types.

  Each sensor type (ECG, IMU, Geolocation, etc.) should implement this behaviour
  to define its valid attributes, payload validation, and optional transformations.

  ## Implementing a New Sensor Type

  1. Create a new module in `Sensocto.Sensors.Types.*`
  2. Add `@behaviour Sensocto.Behaviours.SensorBehaviour`
  3. Implement all required callbacks
  4. Register the sensor in `Sensocto.Sensors.SensorRegistry`

  ## Example Implementation

      defmodule Sensocto.Sensors.Types.ECGSensor do
        @behaviour Sensocto.Behaviours.SensorBehaviour

        @impl true
        def sensor_type, do: "ecg"

        @impl true
        def allowed_attributes, do: ["ecg", "hr", "hrv", "battery"]

        @impl true
        def validate_payload("ecg", %{"values" => values}) when is_list(values) do
          {:ok, %{values: values}}
        end
        def validate_payload(_, _), do: {:error, :invalid_payload}

        @impl true
        def default_config do
          %{
            sampling_rate: 512,
            batch_size: 100
          }
        end
      end

  ## Bidirectional Sensors

  For sensors that support bidirectional communication (like buttplug),
  implement the optional `handle_command/2` callback to process commands
  sent to the sensor.
  """

  @doc """
  Returns the sensor type identifier (e.g., "ecg", "imu", "buttplug").

  This should be a lowercase string matching the `sensor_type` field
  in sensor registration messages.
  """
  @callback sensor_type() :: String.t()

  @doc """
  Returns list of allowed attribute IDs for this sensor type.

  When a sensor registers, its attributes are validated against this list.
  Only attributes in this list will be accepted.
  """
  @callback allowed_attributes() :: [String.t()]

  @doc """
  Validates a payload for a specific attribute.

  Called when a measurement is received to ensure the payload
  matches the expected structure for the attribute type.

  ## Parameters
  - `attribute_id` - The attribute identifier (e.g., "ecg", "battery")
  - `payload` - The raw payload map from the measurement

  ## Returns
  - `{:ok, validated_payload}` - The validated (and optionally transformed) payload
  - `{:error, reason}` - Validation failed with reason
  """
  @callback validate_payload(attribute_id :: String.t(), payload :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Returns default configuration for this sensor type.

  This includes settings like default sampling rate, batch size,
  and any other sensor-specific configuration.
  """
  @callback default_config() :: map()

  @doc """
  Optional: Transforms a payload before storage.

  Use this to normalize, enrich, or convert payload data before
  it's stored in the AttributeStore.
  """
  @callback transform_payload(attribute_id :: String.t(), payload :: map()) :: map()

  @doc """
  Optional: Returns metadata about a specific attribute.

  This can include units, display hints, valid ranges, etc.
  """
  @callback attribute_metadata(attribute_id :: String.t()) :: map()

  @doc """
  Optional: Handles a command sent to the sensor (for bidirectional sensors).

  This is used for sensors like buttplug that can receive commands
  in addition to sending measurements.

  ## Parameters
  - `command` - The command to execute
  - `context` - Additional context (sensor_id, etc.)

  ## Returns
  - `{:ok, response}` - Command executed successfully
  - `{:error, reason}` - Command failed
  """
  @callback handle_command(command :: map(), context :: map()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks [transform_payload: 2, attribute_metadata: 1, handle_command: 2]

  # Helper functions for behaviour implementers

  @doc """
  Validates that all required fields are present in a payload.
  """
  @spec validate_required_fields(map(), [String.t()]) ::
          {:ok, map()} | {:error, {:missing_fields, [String.t()]}}
  def validate_required_fields(payload, required_fields) do
    missing =
      Enum.filter(required_fields, fn field ->
        !Map.has_key?(payload, field)
      end)

    if Enum.empty?(missing) do
      {:ok, payload}
    else
      {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Extracts and validates a numeric value from a payload field.
  """
  @spec validate_numeric(map(), String.t()) :: {:ok, number()} | {:error, term()}
  def validate_numeric(payload, field) do
    case Map.fetch(payload, field) do
      {:ok, value} when is_number(value) -> {:ok, value}
      {:ok, _} -> {:error, {:invalid_type, field, :number}}
      :error -> {:error, {:missing_field, field}}
    end
  end

  @doc """
  Validates a 3D vector (x, y, z) from a payload.
  """
  @spec validate_3d_vector(map()) :: {:ok, map()} | {:error, term()}
  def validate_3d_vector(payload) do
    with {:ok, x} <- validate_numeric(payload, "x"),
         {:ok, y} <- validate_numeric(payload, "y"),
         {:ok, z} <- validate_numeric(payload, "z") do
      {:ok, %{x: x, y: y, z: z}}
    end
  end
end
