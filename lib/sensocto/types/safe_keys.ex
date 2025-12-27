defmodule Sensocto.Types.SafeKeys do
  @moduledoc """
  Safe key conversion that prevents atom exhaustion attacks.

  The Erlang atom table is limited and atoms are never garbage collected.
  Using `String.to_atom/1` on untrusted input (like WebSocket data) can lead
  to a Denial of Service attack by exhausting the atom table.

  This module provides safe alternatives:
  - `validate_attribute_id/1` - validates format without creating atoms
  - `safe_string_to_existing_atom/1` - only converts whitelisted keys
  - `safe_keys_to_atoms/1` - converts a map with whitelisted keys only
  """

  @allowed_attribute_types ~w(
    ecg hrv hr heartrate imu geolocation battery button
    accelerometer gyroscope magnetometer temperature humidity
    pressure altitude speed buttplug proximity light
    spo2 respiration steps calories distance
  )

  @allowed_message_keys ~w(
    attribute_id payload timestamp sensor_id connector_id
    connector_name sensor_name sensor_type sampling_rate
    batch_size bearer_token action metadata features
    attributes values level charging latitude longitude
    accuracy x y z bpm rmssd sdnn value attribute_type
  )

  @type validation_result :: {:ok, String.t()} | {:error, :invalid_attribute_id}

  @doc """
  Checks if a string is an allowed attribute type.

  ## Examples

      iex> Sensocto.Types.SafeKeys.allowed_attribute_type?("ecg")
      true

      iex> Sensocto.Types.SafeKeys.allowed_attribute_type?("malicious_type")
      false
  """
  @spec allowed_attribute_type?(String.t()) :: boolean()
  def allowed_attribute_type?(type) when is_binary(type) do
    String.downcase(type) in @allowed_attribute_types
  end

  @doc """
  Returns the list of allowed attribute types.
  """
  @spec allowed_attribute_types() :: [String.t()]
  def allowed_attribute_types, do: @allowed_attribute_types

  @doc """
  Validates an attribute_id format without creating atoms.
  Attribute IDs must:
  - Start with a letter
  - Contain only alphanumeric characters, underscores, and hyphens
  - Be 1-64 characters long

  ## Examples

      iex> Sensocto.Types.SafeKeys.validate_attribute_id("heart_rate")
      {:ok, "heart_rate"}

      iex> Sensocto.Types.SafeKeys.validate_attribute_id("123invalid")
      {:error, :invalid_attribute_id}

      iex> Sensocto.Types.SafeKeys.validate_attribute_id("")
      {:error, :invalid_attribute_id}
  """
  @spec validate_attribute_id(String.t()) :: validation_result()
  def validate_attribute_id(attribute_id) when is_binary(attribute_id) do
    if Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/, attribute_id) do
      {:ok, attribute_id}
    else
      {:error, :invalid_attribute_id}
    end
  end

  def validate_attribute_id(_), do: {:error, :invalid_attribute_id}

  @doc """
  Converts a string key to an existing atom only if it's in the whitelist.
  Returns the original string if not whitelisted (safe approach).

  ## Examples

      iex> Sensocto.Types.SafeKeys.safe_string_to_existing_atom("sensor_id")
      {:ok, :sensor_id}

      iex> Sensocto.Types.SafeKeys.safe_string_to_existing_atom("unknown_key")
      {:ok, "unknown_key"}
  """
  @spec safe_string_to_existing_atom(String.t()) :: {:ok, atom() | String.t()}
  def safe_string_to_existing_atom(key) when is_binary(key) do
    if key in @allowed_message_keys do
      {:ok, String.to_existing_atom(key)}
    else
      # Keep unknown keys as strings - this is safe
      {:ok, key}
    end
  end

  @doc """
  Safely converts string keys to atoms for whitelisted keys only.
  Unknown keys are preserved as strings.

  ## Examples

      iex> Sensocto.Types.SafeKeys.safe_keys_to_atoms(%{"sensor_id" => "abc", "custom" => 123})
      {:ok, %{sensor_id: "abc", "custom" => 123}}
  """
  @spec safe_keys_to_atoms(map()) :: {:ok, map()}
  def safe_keys_to_atoms(map) when is_map(map) do
    result =
      Enum.reduce(map, %{}, fn {key, value}, acc ->
        {:ok, new_key} = safe_string_to_existing_atom(key)

        new_value =
          if is_map(value) do
            {:ok, converted} = safe_keys_to_atoms(value)
            converted
          else
            value
          end

        Map.put(acc, new_key, new_value)
      end)

    {:ok, result}
  end

  @doc """
  Validates and normalizes a measurement map from WebSocket input.
  Returns a map with validated string keys (no atom conversion).

  ## Examples

      iex> Sensocto.Types.SafeKeys.validate_measurement_keys(%{
      ...>   "attribute_id" => "heart_rate",
      ...>   "payload" => %{"bpm" => 72},
      ...>   "timestamp" => 1234567890
      ...> })
      {:ok, %{"attribute_id" => "heart_rate", "payload" => %{"bpm" => 72}, "timestamp" => 1234567890}}
  """
  @spec validate_measurement_keys(map()) :: {:ok, map()} | {:error, term()}
  def validate_measurement_keys(map) when is_map(map) do
    required = ["attribute_id", "payload", "timestamp"]
    missing = Enum.filter(required, &(!Map.has_key?(map, &1)))

    if missing == [] do
      with {:ok, _} <- validate_attribute_id(map["attribute_id"]) do
        {:ok, map}
      end
    else
      {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Validates an action string is one of the allowed actions.
  Returns the action as a string (not an atom).

  ## Examples

      iex> Sensocto.Types.SafeKeys.validate_action("register")
      {:ok, "register"}

      iex> Sensocto.Types.SafeKeys.validate_action("invalid")
      {:error, :invalid_action}
  """
  @spec validate_action(String.t()) :: {:ok, String.t()} | {:error, :invalid_action}
  def validate_action(action) when action in ["register", "unregister"] do
    {:ok, action}
  end

  def validate_action(_), do: {:error, :invalid_action}
end
