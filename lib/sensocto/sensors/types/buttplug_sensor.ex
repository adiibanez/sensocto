defmodule Sensocto.Sensors.Types.ButtplugSensor do
  @moduledoc """
  Buttplug.io sensor type implementation.

  This is a bidirectional sensor that supports:
  - Receiving vibration/rotation data from devices
  - Sending commands to control devices

  Uses the Buttplug.io protocol for intimate device control.
  """

  @behaviour Sensocto.Behaviours.SensorBehaviour

  alias Sensocto.Payloads.BatteryPayload

  @impl true
  def sensor_type, do: "buttplug"

  @impl true
  def allowed_attributes do
    ["vibrate", "rotate", "linear", "battery", "status", "sensor"]
  end

  @impl true
  def validate_payload("vibrate", %{"speed" => speed})
      when is_number(speed) and speed >= 0 and speed <= 1 do
    {:ok, %{speed: speed}}
  end

  def validate_payload("vibrate", %{"speeds" => speeds}) when is_list(speeds) do
    if Enum.all?(speeds, fn s -> is_number(s) and s >= 0 and s <= 1 end) do
      {:ok, %{speeds: speeds}}
    else
      {:error, :invalid_vibrate_speeds}
    end
  end

  def validate_payload("rotate", %{"speed" => speed, "clockwise" => clockwise})
      when is_number(speed) and speed >= 0 and speed <= 1 and is_boolean(clockwise) do
    {:ok, %{speed: speed, clockwise: clockwise}}
  end

  def validate_payload("linear", %{"position" => pos, "duration" => duration})
      when is_number(pos) and pos >= 0 and pos <= 1 and is_integer(duration) and duration > 0 do
    {:ok, %{position: pos, duration: duration}}
  end

  def validate_payload("battery", payload), do: BatteryPayload.from_map(payload)

  def validate_payload("status", %{"connected" => connected}) when is_boolean(connected) do
    {:ok, %{connected: connected}}
  end

  def validate_payload("sensor", payload) when is_map(payload) do
    # Generic sensor data from device
    {:ok, payload}
  end

  def validate_payload(_, _), do: {:error, :invalid_payload}

  @impl true
  def default_config do
    %{
      sampling_rate: 10,
      batch_size: 1,
      bidirectional: true
    }
  end

  @impl true
  def attribute_metadata("vibrate") do
    %{
      unit: "0-1",
      range: {0, 1},
      description: "Vibration motor speed",
      controllable: true
    }
  end

  def attribute_metadata("rotate") do
    %{
      unit: "0-1",
      range: {0, 1},
      description: "Rotation speed and direction",
      controllable: true
    }
  end

  def attribute_metadata("linear") do
    %{
      unit: "0-1 position, ms duration",
      description: "Linear actuator position",
      controllable: true
    }
  end

  def attribute_metadata(_), do: %{}

  @doc """
  Handles commands sent to the buttplug device.

  ## Supported Commands

  - `%{"type" => "vibrate", "speed" => 0.5}` - Set vibration speed
  - `%{"type" => "stop"}` - Stop all motors
  - `%{"type" => "rotate", "speed" => 0.5, "clockwise" => true}` - Set rotation
  - `%{"type" => "linear", "position" => 0.5, "duration" => 500}` - Move linear actuator
  """
  @impl true
  def handle_command(%{"type" => "vibrate", "speed" => speed} = _cmd, context)
      when is_number(speed) and speed >= 0 and speed <= 1 do
    # In a real implementation, this would send the command via WebSocket/GenServer
    {:ok, %{command: :vibrate, speed: speed, device_id: context[:sensor_id]}}
  end

  def handle_command(%{"type" => "stop"}, context) do
    {:ok, %{command: :stop, device_id: context[:sensor_id]}}
  end

  def handle_command(%{"type" => "rotate", "speed" => speed, "clockwise" => cw} = _cmd, context)
      when is_number(speed) and is_boolean(cw) do
    {:ok, %{command: :rotate, speed: speed, clockwise: cw, device_id: context[:sensor_id]}}
  end

  def handle_command(%{"type" => "linear", "position" => pos, "duration" => dur} = _cmd, context)
      when is_number(pos) and is_integer(dur) do
    {:ok,
     %{command: :linear, position: pos, duration: dur, device_id: context[:sensor_id]}}
  end

  def handle_command(_, _), do: {:error, :unknown_command}
end
