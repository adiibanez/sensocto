defmodule Sensocto.Payloads.IMUPayload do
  @moduledoc """
  Inertial Measurement Unit (IMU) payload.

  Contains 3-axis accelerometer, gyroscope, and optionally magnetometer data.

  ## Example

      iex> IMUPayload.from_map(%{
      ...>   "accelerometer" => %{"x" => 0.1, "y" => 9.8, "z" => 0.2},
      ...>   "gyroscope" => %{"x" => 0.0, "y" => 0.1, "z" => 0.0}
      ...> })
      {:ok, %IMUPayload{...}}
  """

  @type vector3 :: %{x: float(), y: float(), z: float()}

  @type t :: %__MODULE__{
          accelerometer: vector3() | nil,
          gyroscope: vector3() | nil,
          magnetometer: vector3() | nil
        }

  defstruct [:accelerometer, :gyroscope, :magnetometer]

  @doc """
  Creates an IMUPayload from a map.

  Supports two formats:
  1. Nested format: `%{"accelerometer" => %{"x" => ..., "y" => ..., "z" => ...}}`
  2. Flat format: `%{"x" => ..., "y" => ..., "z" => ...}` (treated as accelerometer)
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"accelerometer" => acc} = params) when is_map(acc) do
    with {:ok, acc_vec} <- parse_vector(acc),
         {:ok, gyro_vec} <- parse_optional_vector(Map.get(params, "gyroscope")),
         {:ok, mag_vec} <- parse_optional_vector(Map.get(params, "magnetometer")) do
      {:ok,
       %__MODULE__{
         accelerometer: acc_vec,
         gyroscope: gyro_vec,
         magnetometer: mag_vec
       }}
    end
  end

  # Flat format (just x, y, z) - treat as accelerometer
  def from_map(%{"x" => x, "y" => y, "z" => z})
      when is_number(x) and is_number(y) and is_number(z) do
    {:ok,
     %__MODULE__{
       accelerometer: %{x: x / 1, y: y / 1, z: z / 1},
       gyroscope: nil,
       magnetometer: nil
     }}
  end

  def from_map(%{accelerometer: acc} = params) when is_map(acc) do
    from_map(%{
      "accelerometer" => atomize_vector(acc),
      "gyroscope" => atomize_vector(Map.get(params, :gyroscope)),
      "magnetometer" => atomize_vector(Map.get(params, :magnetometer))
    })
  end

  def from_map(_), do: {:error, :invalid_imu_payload}

  @doc """
  Calculates the magnitude of acceleration (useful for motion detection).
  """
  @spec acceleration_magnitude(t()) :: float() | nil
  def acceleration_magnitude(%__MODULE__{accelerometer: nil}), do: nil

  def acceleration_magnitude(%__MODULE__{accelerometer: %{x: x, y: y, z: z}}) do
    :math.sqrt(x * x + y * y + z * z)
  end

  defp parse_vector(%{"x" => x, "y" => y, "z" => z})
       when is_number(x) and is_number(y) and is_number(z) do
    {:ok, %{x: x / 1, y: y / 1, z: z / 1}}
  end

  defp parse_vector(%{x: x, y: y, z: z})
       when is_number(x) and is_number(y) and is_number(z) do
    {:ok, %{x: x / 1, y: y / 1, z: z / 1}}
  end

  defp parse_vector(_), do: {:error, :invalid_vector}

  defp parse_optional_vector(nil), do: {:ok, nil}
  defp parse_optional_vector(map), do: parse_vector(map)

  defp atomize_vector(nil), do: nil

  defp atomize_vector(map) when is_map(map) do
    %{
      "x" => Map.get(map, :x) || Map.get(map, "x"),
      "y" => Map.get(map, :y) || Map.get(map, "y"),
      "z" => Map.get(map, :z) || Map.get(map, "z")
    }
  end

  defimpl Sensocto.Protocols.AttributePayload do
    def validate(%Sensocto.Payloads.IMUPayload{accelerometer: acc})
        when is_map(acc) do
      {:ok, @for}
    end

    def validate(_), do: {:error, :invalid_imu_payload}

    def display_value(%{accelerometer: %{x: x, y: y, z: z}}) do
      "Acc: (#{fmt(x)}, #{fmt(y)}, #{fmt(z)})"
    end

    def display_value(_), do: "IMU data"

    def render_hints(_) do
      %{
        component: "IMU",
        chart_type: :multi_axis,
        axes: [:accelerometer, :gyroscope, :magnetometer]
      }
    end

    defp fmt(n), do: Float.round(n, 2) |> to_string()
  end
end
