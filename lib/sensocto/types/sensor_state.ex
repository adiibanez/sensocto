defmodule Sensocto.Types.SensorState do
  @moduledoc """
  Type-safe sensor state representation.

  Represents the complete state of a sensor including its metadata
  and current attribute values. Used for rendering in LiveView.

  ## Example

      %SensorState{
        sensor_id: "sensor_123",
        sensor_name: "ECG Monitor",
        sensor_type: "ecg",
        connector_id: "connector_456",
        connector_name: "BLE Connector",
        sampling_rate: 512,
        batch_size: 100,
        attributes: %{
          "ecg" => %AttributeState{...},
          "battery" => %AttributeState{...}
        }
      }
  """

  alias Sensocto.Types.AttributeState

  @type t :: %__MODULE__{
          sensor_id: String.t(),
          sensor_name: String.t(),
          sensor_type: String.t(),
          connector_id: String.t(),
          connector_name: String.t(),
          sampling_rate: non_neg_integer() | nil,
          batch_size: non_neg_integer() | nil,
          attributes: %{String.t() => AttributeState.t()}
        }

  @enforce_keys [:sensor_id, :sensor_name, :connector_id, :connector_name]
  defstruct [
    :sensor_id,
    :sensor_name,
    :sensor_type,
    :connector_id,
    :connector_name,
    :sampling_rate,
    :batch_size,
    attributes: %{}
  ]

  @doc """
  Creates a SensorState from a map (typically from GenServer state).
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    with {:ok, sensor_id} <- fetch_required(map, [:sensor_id, "sensor_id"]),
         {:ok, sensor_name} <- fetch_required(map, [:sensor_name, "sensor_name"]),
         {:ok, connector_id} <- fetch_required(map, [:connector_id, "connector_id"]),
         {:ok, connector_name} <- fetch_required(map, [:connector_name, "connector_name"]) do
      {:ok,
       %__MODULE__{
         sensor_id: sensor_id,
         sensor_name: sensor_name,
         sensor_type: fetch_optional(map, [:sensor_type, "sensor_type"]),
         connector_id: connector_id,
         connector_name: connector_name,
         sampling_rate: fetch_optional(map, [:sampling_rate, "sampling_rate"]),
         batch_size: fetch_optional(map, [:batch_size, "batch_size"]),
         attributes: transform_attributes(fetch_optional(map, [:attributes, "attributes"]) || %{})
       }}
    end
  end

  @doc """
  Gets an attribute by ID from the sensor state.
  """
  @spec get_attribute(t(), String.t()) :: AttributeState.t() | nil
  def get_attribute(%__MODULE__{attributes: attrs}, attribute_id) do
    Map.get(attrs, attribute_id)
  end

  @doc """
  Updates an attribute in the sensor state.
  """
  @spec put_attribute(t(), String.t(), AttributeState.t()) :: t()
  def put_attribute(%__MODULE__{} = state, attribute_id, attribute) do
    %{state | attributes: Map.put(state.attributes, attribute_id, attribute)}
  end

  # Private helpers

  defp fetch_required(map, keys) when is_list(keys) do
    result =
      Enum.find_value(keys, fn key ->
        case Map.fetch(map, key) do
          {:ok, value} when value != nil -> value
          _ -> nil
        end
      end)

    if result do
      {:ok, to_string(result)}
    else
      {:error, {:missing_field, hd(keys)}}
    end
  end

  defp fetch_optional(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp transform_attributes(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      string_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      attr_state = AttributeState.from_map(value, string_key)
      Map.put(acc, string_key, attr_state)
    end)
  end

  defp transform_attributes(_), do: %{}
end

defmodule Sensocto.Types.AttributeState do
  @moduledoc """
  Represents the state of a single sensor attribute.

  Contains the attribute metadata and current values.
  """

  @type t :: %__MODULE__{
          attribute_id: String.t(),
          attribute_type: String.t() | nil,
          sampling_rate: non_neg_integer() | nil,
          values: list(),
          lastvalue: map() | nil
        }

  defstruct [
    :attribute_id,
    :attribute_type,
    :sampling_rate,
    values: [],
    lastvalue: nil
  ]

  @doc """
  Creates an AttributeState from a map.
  """
  @spec from_map(map(), String.t()) :: t()
  def from_map(map, attribute_id) when is_map(map) do
    %__MODULE__{
      attribute_id: attribute_id,
      attribute_type: get_string(map, [:attribute_type, "attribute_type", :type, "type"]),
      sampling_rate: get_value(map, [:sampling_rate, "sampling_rate"]),
      values: get_value(map, [:values, "values"]) || [],
      lastvalue: get_value(map, [:lastvalue, "lastvalue"])
    }
  end

  def from_map(_, attribute_id), do: %__MODULE__{attribute_id: attribute_id}

  defp get_string(map, keys) do
    value = get_value(map, keys)
    if value, do: to_string(value), else: nil
  end

  defp get_value(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end
end
