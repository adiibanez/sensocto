defmodule Sensocto.Sensors.Types.ECGSensor do
  @moduledoc """
  ECG sensor type implementation.

  Supports ECG waveform data along with derived metrics like heart rate (HR)
  and heart rate variability (HRV).
  """

  @behaviour Sensocto.Behaviours.SensorBehaviour

  alias Sensocto.Payloads.{ECGPayload, BatteryPayload}

  @impl true
  def sensor_type, do: "ecg"

  @impl true
  def allowed_attributes, do: ["ecg", "hr", "heartrate", "hrv", "battery"]

  @impl true
  def validate_payload("ecg", payload), do: ECGPayload.from_map(payload)

  def validate_payload(attr, %{"bpm" => bpm} = _payload)
      when attr in ["hr", "heartrate"] and is_number(bpm) and bpm > 0 and bpm < 300 do
    {:ok, %{bpm: bpm}}
  end

  def validate_payload("hrv", %{"rmssd" => rmssd, "sdnn" => sdnn} = _payload)
      when is_number(rmssd) and is_number(sdnn) do
    {:ok, %{rmssd: rmssd, sdnn: sdnn}}
  end

  def validate_payload("hrv", %{"rmssd" => rmssd} = _payload) when is_number(rmssd) do
    {:ok, %{rmssd: rmssd, sdnn: nil}}
  end

  def validate_payload("battery", payload), do: BatteryPayload.from_map(payload)

  def validate_payload(_, _), do: {:error, :invalid_payload}

  @impl true
  def default_config do
    %{
      sampling_rate: 512,
      batch_size: 100,
      lead: "I"
    }
  end

  @impl true
  def attribute_metadata("ecg") do
    %{
      sampling_rate: 512,
      unit: "mV",
      description: "ECG waveform signal"
    }
  end

  def attribute_metadata(attr) when attr in ["hr", "heartrate"] do
    %{
      unit: "bpm",
      range: {30, 220},
      description: "Heart rate in beats per minute"
    }
  end

  def attribute_metadata("hrv") do
    %{
      unit: "ms",
      description: "Heart rate variability metrics"
    }
  end

  def attribute_metadata("battery") do
    %{
      unit: "%",
      range: {0, 100},
      description: "Device battery level"
    }
  end

  def attribute_metadata(_), do: %{}
end
