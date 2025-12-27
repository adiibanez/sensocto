defmodule Sensocto.Sensors.SensorRegistry do
  @moduledoc """
  Registry of known sensor type implementations.

  This module provides a lookup mechanism for sensor type modules
  and centralizes payload validation.

  ## Adding a New Sensor Type

  1. Create a new module implementing `Sensocto.Behaviours.SensorBehaviour`
  2. Add it to the `@sensor_types` map below
  3. The sensor will automatically be available for registration

  ## Example

      iex> SensorRegistry.get_sensor_module("ecg")
      {:ok, Sensocto.Sensors.Types.ECGSensor}

      iex> SensorRegistry.validate_payload("ecg", "hr", %{"bpm" => 72})
      {:ok, %{bpm: 72}}
  """

  alias Sensocto.Sensors.Types.{ECGSensor, IMUSensor, HTML5Sensor, ButtplugSensor}

  @sensor_types %{
    "ecg" => ECGSensor,
    "imu" => IMUSensor,
    "html5" => HTML5Sensor,
    "buttplug" => ButtplugSensor,
    # Aliases
    "hrm" => ECGSensor,
    "heart_rate_monitor" => ECGSensor,
    "motion" => IMUSensor,
    "browser" => HTML5Sensor
  }

  @type sensor_module :: module()

  @doc """
  Returns the sensor module for a given sensor type string.

  ## Examples

      iex> SensorRegistry.get_sensor_module("ecg")
      {:ok, Sensocto.Sensors.Types.ECGSensor}

      iex> SensorRegistry.get_sensor_module("unknown")
      {:error, :unknown_sensor_type}
  """
  @spec get_sensor_module(String.t()) :: {:ok, sensor_module()} | {:error, :unknown_sensor_type}
  def get_sensor_module(type) when is_binary(type) do
    normalized = String.downcase(type)

    case Map.fetch(@sensor_types, normalized) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_sensor_type}
    end
  end

  @doc """
  Returns all registered sensor types.
  """
  @spec all_types() :: [String.t()]
  def all_types do
    @sensor_types
    |> Enum.filter(fn {key, val} ->
      # Only return primary types, not aliases
      key == val.sensor_type()
    end)
    |> Enum.map(fn {key, _} -> key end)
  end

  @doc """
  Checks if a sensor type is registered.

  ## Examples

      iex> SensorRegistry.valid_sensor_type?("ecg")
      true

      iex> SensorRegistry.valid_sensor_type?("unknown")
      false
  """
  @spec valid_sensor_type?(String.t()) :: boolean()
  def valid_sensor_type?(type) when is_binary(type) do
    String.downcase(type) in Map.keys(@sensor_types)
  end

  @doc """
  Validates a payload for a specific sensor type and attribute.

  This is the main validation entry point used by the channel.

  ## Examples

      iex> SensorRegistry.validate_payload("ecg", "hr", %{"bpm" => 72})
      {:ok, %{bpm: 72}}

      iex> SensorRegistry.validate_payload("unknown", "attr", %{})
      {:error, :unknown_sensor_type}
  """
  @spec validate_payload(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def validate_payload(sensor_type, attribute_id, payload) do
    with {:ok, module} <- get_sensor_module(sensor_type) do
      module.validate_payload(attribute_id, payload)
    end
  end

  @doc """
  Returns the list of allowed attributes for a sensor type.

  ## Examples

      iex> SensorRegistry.allowed_attributes("ecg")
      {:ok, ["ecg", "hr", "heartrate", "hrv", "battery"]}
  """
  @spec allowed_attributes(String.t()) :: {:ok, [String.t()]} | {:error, :unknown_sensor_type}
  def allowed_attributes(sensor_type) do
    with {:ok, module} <- get_sensor_module(sensor_type) do
      {:ok, module.allowed_attributes()}
    end
  end

  @doc """
  Checks if an attribute is allowed for a sensor type.

  ## Examples

      iex> SensorRegistry.attribute_allowed?("ecg", "hr")
      true

      iex> SensorRegistry.attribute_allowed?("ecg", "gps")
      false
  """
  @spec attribute_allowed?(String.t(), String.t()) :: boolean()
  def attribute_allowed?(sensor_type, attribute_id) do
    case allowed_attributes(sensor_type) do
      {:ok, attrs} -> attribute_id in attrs
      {:error, _} -> false
    end
  end

  @doc """
  Returns the default configuration for a sensor type.
  """
  @spec default_config(String.t()) :: {:ok, map()} | {:error, :unknown_sensor_type}
  def default_config(sensor_type) do
    with {:ok, module} <- get_sensor_module(sensor_type) do
      {:ok, module.default_config()}
    end
  end

  @doc """
  Returns attribute metadata for a sensor type and attribute.
  """
  @spec attribute_metadata(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def attribute_metadata(sensor_type, attribute_id) do
    with {:ok, module} <- get_sensor_module(sensor_type) do
      if function_exported?(module, :attribute_metadata, 1) do
        {:ok, module.attribute_metadata(attribute_id)}
      else
        {:ok, %{}}
      end
    end
  end

  @doc """
  Handles a command for bidirectional sensors.

  ## Examples

      iex> SensorRegistry.handle_command("buttplug", %{"type" => "vibrate", "speed" => 0.5}, %{sensor_id: "dev1"})
      {:ok, %{command: :vibrate, speed: 0.5, device_id: "dev1"}}
  """
  @spec handle_command(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def handle_command(sensor_type, command, context) do
    with {:ok, module} <- get_sensor_module(sensor_type) do
      if function_exported?(module, :handle_command, 2) do
        module.handle_command(command, context)
      else
        {:error, :command_not_supported}
      end
    end
  end

  @doc """
  Checks if a sensor type supports bidirectional communication.
  """
  @spec bidirectional?(String.t()) :: boolean()
  def bidirectional?(sensor_type) do
    case get_sensor_module(sensor_type) do
      {:ok, module} -> function_exported?(module, :handle_command, 2)
      {:error, _} -> false
    end
  end
end
