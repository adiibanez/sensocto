defmodule Sensocto.Sensors.Types.IMUSensor do
  @moduledoc """
  IMU (Inertial Measurement Unit) sensor type implementation.

  Supports accelerometer, gyroscope, and magnetometer data.
  """

  @behaviour Sensocto.Behaviours.SensorBehaviour

  alias Sensocto.Payloads.{IMUPayload, BatteryPayload}
  alias Sensocto.Behaviours.SensorBehaviour

  @impl true
  def sensor_type, do: "imu"

  @impl true
  def allowed_attributes do
    ["imu", "accelerometer", "gyroscope", "magnetometer", "battery"]
  end

  @impl true
  def validate_payload("imu", payload), do: IMUPayload.from_map(payload)

  def validate_payload(attr, payload)
      when attr in ["accelerometer", "gyroscope", "magnetometer"] do
    SensorBehaviour.validate_3d_vector(payload)
  end

  def validate_payload("battery", payload), do: BatteryPayload.from_map(payload)

  def validate_payload(_, _), do: {:error, :invalid_payload}

  @impl true
  def default_config do
    %{
      sampling_rate: 100,
      batch_size: 50
    }
  end

  @impl true
  def attribute_metadata("accelerometer") do
    %{
      unit: "m/s²",
      axes: [:x, :y, :z],
      description: "Linear acceleration"
    }
  end

  def attribute_metadata("gyroscope") do
    %{
      unit: "rad/s",
      axes: [:x, :y, :z],
      description: "Angular velocity"
    }
  end

  def attribute_metadata("magnetometer") do
    %{
      unit: "µT",
      axes: [:x, :y, :z],
      description: "Magnetic field strength"
    }
  end

  def attribute_metadata(_), do: %{}
end
