defmodule Sensocto.Sensors.Types.HTML5Sensor do
  @moduledoc """
  HTML5 sensor type implementation.

  Supports sensors available through the HTML5 Sensor APIs:
  - Geolocation
  - DeviceMotion (accelerometer)
  - DeviceOrientation (gyroscope)
  - Battery Status
  - Ambient Light
  """

  @behaviour Sensocto.Behaviours.SensorBehaviour

  alias Sensocto.Payloads.{GeolocationPayload, BatteryPayload}
  alias Sensocto.Behaviours.SensorBehaviour

  @impl true
  def sensor_type, do: "html5"

  @impl true
  def allowed_attributes do
    [
      "geolocation",
      "accelerometer",
      "gyroscope",
      "magnetometer",
      "battery",
      "light",
      "proximity"
    ]
  end

  @impl true
  def validate_payload("geolocation", payload), do: GeolocationPayload.from_map(payload)
  def validate_payload("battery", payload), do: BatteryPayload.from_map(payload)

  def validate_payload(attr, payload)
      when attr in ["accelerometer", "gyroscope", "magnetometer"] do
    SensorBehaviour.validate_3d_vector(payload)
  end

  def validate_payload("light", %{"lux" => lux}) when is_number(lux) and lux >= 0 do
    {:ok, %{lux: lux}}
  end

  def validate_payload("proximity", %{"near" => near}) when is_boolean(near) do
    {:ok, %{near: near}}
  end

  def validate_payload("proximity", %{"distance" => distance})
      when is_number(distance) and distance >= 0 do
    {:ok, %{distance: distance, near: distance < 5}}
  end

  def validate_payload(_, _), do: {:error, :invalid_payload}

  @impl true
  def default_config do
    %{
      sampling_rate: 10,
      batch_size: 1
    }
  end

  @impl true
  def attribute_metadata("geolocation") do
    %{
      description: "GPS coordinates from browser",
      requires_permission: true
    }
  end

  def attribute_metadata("light") do
    %{
      unit: "lux",
      description: "Ambient light level"
    }
  end

  def attribute_metadata("proximity") do
    %{
      description: "Proximity sensor (near/far or distance)"
    }
  end

  def attribute_metadata(_), do: %{}
end
