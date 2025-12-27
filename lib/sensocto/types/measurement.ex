defmodule Sensocto.Types.Measurement do
  @moduledoc """
  Type-safe measurement struct for sensor data points.

  A measurement represents a single data point from a sensor attribute,
  containing the payload value, timestamp, and identifying information.

  ## Example

      iex> Measurement.new(%{
      ...>   "sensor_id" => "sensor_123",
      ...>   "attribute_id" => "heart_rate",
      ...>   "timestamp" => 1703683200000,
      ...>   "payload" => %{"bpm" => 72}
      ...> })
      {:ok, %Measurement{
        sensor_id: "sensor_123",
        attribute_id: "heart_rate",
        timestamp: 1703683200000,
        payload: %{"bpm" => 72}
      }}
  """

  alias Sensocto.Types.SafeKeys

  @type t :: %__MODULE__{
          sensor_id: String.t(),
          attribute_id: String.t(),
          timestamp: integer(),
          payload: map() | number()
        }

  @enforce_keys [:sensor_id, :attribute_id, :timestamp, :payload]
  defstruct [:sensor_id, :attribute_id, :timestamp, :payload]

  @doc """
  Creates a new Measurement from a map with string keys (typically from JSON/WebSocket).

  Validates:
  - All required fields are present
  - attribute_id matches valid format
  - timestamp is an integer

  ## Examples

      iex> Measurement.new(%{
      ...>   "sensor_id" => "sensor_123",
      ...>   "attribute_id" => "heart_rate",
      ...>   "timestamp" => 1703683200000,
      ...>   "payload" => 72
      ...> })
      {:ok, %Measurement{...}}

      iex> Measurement.new(%{"payload" => 72})
      {:error, {:missing_fields, ["sensor_id", "attribute_id", "timestamp"]}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(params) when is_map(params) do
    with {:ok, sensor_id} <- fetch_string(params, "sensor_id"),
         {:ok, attribute_id} <- fetch_and_validate_attribute_id(params),
         {:ok, timestamp} <- fetch_timestamp(params),
         {:ok, payload} <- fetch_payload(params) do
      {:ok,
       %__MODULE__{
         sensor_id: sensor_id,
         attribute_id: attribute_id,
         timestamp: timestamp,
         payload: payload
       }}
    end
  end

  @doc """
  Creates a new Measurement from a map with atom keys (internal use).

  This is used when data has already been validated and converted.
  """
  @spec from_atom_keys(map()) :: {:ok, t()} | {:error, term()}
  def from_atom_keys(%{
        attribute_id: attribute_id,
        payload: payload,
        timestamp: timestamp,
        sensor_id: sensor_id
      }) do
    {:ok,
     %__MODULE__{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       timestamp: timestamp,
       payload: payload
     }}
  end

  def from_atom_keys(_), do: {:error, :invalid_measurement}

  @doc """
  Converts a Measurement to a map with atom keys for internal use.
  """
  @spec to_atom_map(t()) :: map()
  def to_atom_map(%__MODULE__{} = m) do
    %{
      sensor_id: m.sensor_id,
      attribute_id: m.attribute_id,
      timestamp: m.timestamp,
      payload: m.payload
    }
  end

  @doc """
  Converts a Measurement to a map with string keys for JSON serialization.
  """
  @spec to_string_map(t()) :: map()
  def to_string_map(%__MODULE__{} = m) do
    %{
      "sensor_id" => m.sensor_id,
      "attribute_id" => m.attribute_id,
      "timestamp" => m.timestamp,
      "payload" => m.payload
    }
  end

  # Private helpers

  defp fetch_string(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}

      {:ok, _} ->
        {:error, {:invalid_field, key}}

      :error ->
        {:error, {:missing_field, key}}
    end
  end

  defp fetch_and_validate_attribute_id(params) do
    with {:ok, attr_id} <- fetch_string(params, "attribute_id"),
         {:ok, validated} <- SafeKeys.validate_attribute_id(attr_id) do
      {:ok, validated}
    end
  end

  defp fetch_timestamp(params) do
    case Map.fetch(params, "timestamp") do
      {:ok, ts} when is_integer(ts) and ts > 0 ->
        {:ok, ts}

      {:ok, ts} when is_binary(ts) ->
        case Integer.parse(ts) do
          {int, ""} when int > 0 -> {:ok, int}
          _ -> {:error, :invalid_timestamp}
        end

      {:ok, ts} when is_float(ts) ->
        {:ok, trunc(ts)}

      {:ok, _} ->
        {:error, :invalid_timestamp}

      :error ->
        {:error, {:missing_field, "timestamp"}}
    end
  end

  defp fetch_payload(params) do
    case Map.fetch(params, "payload") do
      {:ok, payload} when is_map(payload) or is_number(payload) or is_list(payload) ->
        {:ok, payload}

      {:ok, _} ->
        {:error, :invalid_payload}

      :error ->
        {:error, {:missing_field, "payload"}}
    end
  end
end
