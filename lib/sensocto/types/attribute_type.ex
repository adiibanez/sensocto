defmodule Sensocto.Types.AttributeType do
  @moduledoc """
  Enumeration of valid sensor attribute types.

  This module defines all known attribute types that can be used
  in the sensor system. Each type has specific payload schemas
  and rendering behaviors.

  ## Adding New Attribute Types

  To add a new attribute type:
  1. Add it to the @attribute_types list
  2. Create a corresponding payload module in `Sensocto.Payloads.*`
  3. Implement the `Sensocto.Protocols.AttributePayload` protocol
  4. Add rendering support in `AttributeComponent`

  ## Example

      iex> AttributeType.valid?("ecg")
      true

      iex> AttributeType.valid?("unknown")
      false

      iex> AttributeType.all()
      ["ecg", "hrv", "hr", ...]
  """

  @attribute_types [
    # Cardiac/Health
    "ecg",
    "hrv",
    "hr",
    "heartrate",
    "spo2",
    "respiration",

    # Motion/IMU
    "imu",
    "accelerometer",
    "gyroscope",
    "magnetometer",

    # Location
    "geolocation",
    "altitude",
    "speed",

    # Environment
    "temperature",
    "humidity",
    "pressure",
    "light",
    "proximity",

    # Device
    "battery",
    "button",

    # Activity
    "steps",
    "calories",
    "distance",

    # Specialty
    "buttplug"
  ]

  @type t :: String.t()

  @doc """
  Returns all valid attribute types.
  """
  @spec all() :: [String.t()]
  def all, do: @attribute_types

  @doc """
  Checks if a string is a valid attribute type.

  ## Examples

      iex> AttributeType.valid?("ecg")
      true

      iex> AttributeType.valid?("ECG")
      true

      iex> AttributeType.valid?("unknown")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(type) when is_binary(type) do
    String.downcase(type) in @attribute_types
  end

  def valid?(_), do: false

  @doc """
  Normalizes an attribute type to lowercase.
  Returns `{:ok, normalized}` if valid, `{:error, :invalid_type}` otherwise.

  ## Examples

      iex> AttributeType.normalize("ECG")
      {:ok, "ecg"}

      iex> AttributeType.normalize("unknown")
      {:error, :invalid_type}
  """
  @spec normalize(String.t()) :: {:ok, String.t()} | {:error, :invalid_type}
  def normalize(type) when is_binary(type) do
    normalized = String.downcase(type)

    if normalized in @attribute_types do
      {:ok, normalized}
    else
      {:error, :invalid_type}
    end
  end

  def normalize(_), do: {:error, :invalid_type}

  @doc """
  Returns the category of an attribute type.

  Categories help group related attributes for UI organization.

  ## Examples

      iex> AttributeType.category("ecg")
      :health

      iex> AttributeType.category("accelerometer")
      :motion
  """
  @spec category(String.t()) :: atom()
  def category(type) when is_binary(type) do
    case String.downcase(type) do
      t when t in ~w(ecg hrv hr heartrate spo2 respiration) -> :health
      t when t in ~w(imu accelerometer gyroscope magnetometer) -> :motion
      t when t in ~w(geolocation altitude speed) -> :location
      t when t in ~w(temperature humidity pressure light proximity) -> :environment
      t when t in ~w(battery button) -> :device
      t when t in ~w(steps calories distance) -> :activity
      "buttplug" -> :specialty
      _ -> :unknown
    end
  end

  @doc """
  Returns rendering hints for an attribute type.

  These hints help the UI choose appropriate visualizations.

  ## Examples

      iex> AttributeType.render_hints("ecg")
      %{chart_type: :waveform, color: "#ffc107", component: "ECGVisualization"}
  """
  @spec render_hints(String.t()) :: map()
  def render_hints(type) when is_binary(type) do
    case String.downcase(type) do
      "ecg" ->
        %{chart_type: :waveform, color: "#ffc107", component: "ECGVisualization"}

      "geolocation" ->
        %{chart_type: :map, component: "Map"}

      "battery" ->
        %{chart_type: :gauge, component: "BatteryMeter"}

      t when t in ~w(hr heartrate hrv) ->
        %{chart_type: :sparkline, color: "#ff4444", component: "SparklineWasm"}

      t when t in ~w(accelerometer gyroscope magnetometer imu) ->
        %{chart_type: :multi_axis, component: "IMU"}

      "temperature" ->
        %{chart_type: :gauge, unit: "°C", component: "TemperatureGauge"}

      _ ->
        %{chart_type: :sparkline, component: "SparklineWasm"}
    end
  end

  @doc """
  Returns the expected payload fields for an attribute type.

  This is used for validation at runtime.
  """
  @spec expected_payload_fields(String.t()) :: [String.t()]
  def expected_payload_fields(type) when is_binary(type) do
    case String.downcase(type) do
      "ecg" -> ["values"]
      "geolocation" -> ["latitude", "longitude"]
      "battery" -> ["level"]
      t when t in ~w(hr heartrate) -> ["bpm"]
      "hrv" -> ["rmssd", "sdnn"]
      t when t in ~w(accelerometer gyroscope magnetometer) -> ["x", "y", "z"]
      "imu" -> ["accelerometer", "gyroscope", "magnetometer"]
      "temperature" -> ["value"]
      "humidity" -> ["value"]
      "pressure" -> ["value"]
      "button" -> ["pressed"]
      "buttplug" -> ["command"]
      _ -> []
    end
  end
end
