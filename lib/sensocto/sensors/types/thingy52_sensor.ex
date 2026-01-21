defmodule Sensocto.Sensors.Types.Thingy52Sensor do
  @moduledoc """
  Nordic Thingy:52 sensor type implementation.

  The Thingy:52 is a multi-sensor development kit from Nordic Semiconductor
  that includes environmental, motion, UI, and sound capabilities.

  ## BLE Services

  ### Environment Service (EF680200-9B35-4933-9B10-52FFA9740042)
  - Temperature (EF680201) - Integer (1 byte) + Decimal (1 byte)
  - Pressure (EF680202) - Integer (4 bytes) + Decimal (1 byte)
  - Humidity (EF680203) - 1 byte (0-100%)
  - Gas/Air Quality (EF680204) - eCO2 (2 bytes) + TVOC (2 bytes)
  - Color (EF680205) - R, G, B, Clear (2 bytes each)

  ### Motion Service (EF680400-9B35-4933-9B10-52FFA9740042)
  - Accelerometer/Gyroscope/Magnetometer Raw (EF680406)
  - Quaternion (EF680404) - w, x, y, z (4 bytes each as int32)
  - Euler Angles (EF680403) - Roll, Pitch, Yaw
  - Rotation Matrix (EF680405)
  - Heading (EF680409)
  - Gravity Vector (EF680407)
  - Step Counter (EF680408)
  - Tap Detection (EF68040A)
  - Orientation (EF68040B)

  ### UI Service (EF680300-9B35-4933-9B10-52FFA9740042)
  - LED (EF680301) - Mode, RGB, Intensity (writable)
  - Button (EF680302) - Press state

  ### Sound Service (EF680500-9B35-4933-9B10-52FFA9740042)
  - Speaker Data (EF680502) - Audio samples (writable)
  - Speaker Status (EF680503)
  - Microphone (EF680504)

  ### Battery Service (0x180F)
  - Battery Level (0x2A19)
  """

  @behaviour Sensocto.Behaviours.SensorBehaviour

  alias Sensocto.Payloads.BatteryPayload
  alias Sensocto.Behaviours.SensorBehaviour

  # Environment attributes
  @environment_attrs ["temperature", "pressure", "humidity", "gas", "air_quality", "color"]

  # Motion attributes
  @motion_attrs [
    "accelerometer",
    "gyroscope",
    "magnetometer",
    "quaternion",
    "euler",
    "heading",
    "gravity",
    "steps",
    "tap",
    "orientation"
  ]

  # UI attributes
  @ui_attrs ["button", "led"]

  # Sound attributes
  @sound_attrs ["speaker", "microphone"]

  # Device attributes
  @device_attrs ["battery"]

  @impl true
  def sensor_type, do: "thingy52"

  @impl true
  def allowed_attributes do
    @environment_attrs ++ @motion_attrs ++ @ui_attrs ++ @sound_attrs ++ @device_attrs
  end

  # Temperature validation - Thingy:52 sends integer + decimal parts
  @impl true
  def validate_payload("temperature", %{"value" => value}) when is_number(value) do
    {:ok, %{value: value, unit: "°C"}}
  end

  def validate_payload("temperature", %{"integer" => int, "decimal" => dec})
      when is_integer(int) and is_integer(dec) do
    value = int + dec / 100.0
    {:ok, %{value: value, unit: "°C"}}
  end

  # Pressure validation - Thingy:52 sends integer (hPa) + decimal
  def validate_payload("pressure", %{"value" => value}) when is_number(value) do
    {:ok, %{value: value, unit: "hPa"}}
  end

  def validate_payload("pressure", %{"integer" => int, "decimal" => dec})
      when is_integer(int) and is_integer(dec) do
    value = int + dec / 100.0
    {:ok, %{value: value, unit: "hPa"}}
  end

  # Humidity validation - 0-100%
  def validate_payload("humidity", %{"value" => value})
      when is_number(value) and value >= 0 and value <= 100 do
    {:ok, %{value: value, unit: "%"}}
  end

  # Gas/Air Quality validation - eCO2 (ppm) and TVOC (ppb)
  def validate_payload(attr, %{"eco2" => eco2, "tvoc" => tvoc})
      when attr in ["gas", "air_quality"] and is_number(eco2) and is_number(tvoc) do
    {:ok, %{eco2: eco2, tvoc: tvoc, eco2_unit: "ppm", tvoc_unit: "ppb"}}
  end

  def validate_payload(attr, %{"eco2" => eco2})
      when attr in ["gas", "air_quality"] and is_number(eco2) do
    {:ok, %{eco2: eco2, tvoc: nil, eco2_unit: "ppm", tvoc_unit: "ppb"}}
  end

  # Color validation - RGBC values
  def validate_payload("color", %{"r" => r, "g" => g, "b" => b, "c" => c})
      when is_integer(r) and is_integer(g) and is_integer(b) and is_integer(c) do
    # Calculate color temperature and luminance
    luminance = calculate_luminance(r, g, b)
    color_temp = calculate_color_temperature(r, g, b)

    {:ok,
     %{
       r: r,
       g: g,
       b: b,
       clear: c,
       luminance: luminance,
       color_temperature: color_temp,
       hex: rgb_to_hex(r, g, b)
     }}
  end

  def validate_payload("color", %{"r" => r, "g" => g, "b" => b})
      when is_integer(r) and is_integer(g) and is_integer(b) do
    {:ok, %{r: r, g: g, b: b, clear: nil, hex: rgb_to_hex(r, g, b)}}
  end

  # 3D vector attributes (accelerometer, gyroscope, magnetometer, gravity)
  def validate_payload(attr, payload)
      when attr in ["accelerometer", "gyroscope", "magnetometer", "gravity"] do
    SensorBehaviour.validate_3d_vector(payload)
  end

  # Quaternion validation - w, x, y, z components
  def validate_payload("quaternion", %{"w" => w, "x" => x, "y" => y, "z" => z})
      when is_number(w) and is_number(x) and is_number(y) and is_number(z) do
    {:ok, %{w: w, x: x, y: y, z: z}}
  end

  # Euler angles validation - roll, pitch, yaw in degrees
  def validate_payload("euler", %{"roll" => roll, "pitch" => pitch, "yaw" => yaw})
      when is_number(roll) and is_number(pitch) and is_number(yaw) do
    {:ok, %{roll: roll, pitch: pitch, yaw: yaw, unit: "°"}}
  end

  # Heading validation - compass heading in degrees
  def validate_payload("heading", %{"value" => value}) when is_number(value) do
    # Normalize to 0-360 range
    normalized = Float.floor(:math.fmod(value + 360, 360) * 10) / 10
    direction = heading_to_direction(normalized)
    {:ok, %{value: normalized, direction: direction, unit: "°"}}
  end

  # Step counter validation
  def validate_payload("steps", %{"count" => count}) when is_integer(count) and count >= 0 do
    {:ok, %{count: count}}
  end

  def validate_payload("steps", %{"value" => value}) when is_integer(value) and value >= 0 do
    {:ok, %{count: value}}
  end

  # Tap detection validation
  def validate_payload("tap", %{"direction" => direction, "count" => count})
      when is_integer(direction) and is_integer(count) do
    tap_direction = decode_tap_direction(direction)
    {:ok, %{direction: tap_direction, count: count}}
  end

  def validate_payload("tap", %{"value" => value}) when is_integer(value) do
    {:ok, %{direction: decode_tap_direction(value), count: 1}}
  end

  # Orientation validation
  def validate_payload("orientation", %{"value" => value}) when is_integer(value) do
    orientation = decode_orientation(value)
    {:ok, %{value: value, orientation: orientation}}
  end

  # Button validation (single button, reports press state)
  def validate_payload("button", %{"pressed" => pressed}) when is_boolean(pressed) do
    {:ok, %{pressed: pressed, state: if(pressed, do: "pressed", else: "released")}}
  end

  def validate_payload("button", %{"value" => value}) when is_integer(value) do
    pressed = value > 0
    {:ok, %{pressed: pressed, state: if(pressed, do: "pressed", else: "released"), value: value}}
  end

  def validate_payload("button", value) when is_integer(value) do
    pressed = value > 0
    {:ok, %{pressed: pressed, state: if(pressed, do: "pressed", else: "released"), value: value}}
  end

  # LED control (for setting LED state)
  def validate_payload("led", %{"mode" => mode} = payload)
      when mode in ["off", "constant", "breathe", "one_shot"] do
    {:ok,
     %{
       mode: mode,
       r: Map.get(payload, "r", 0),
       g: Map.get(payload, "g", 0),
       b: Map.get(payload, "b", 0),
       intensity: Map.get(payload, "intensity", 100),
       delay: Map.get(payload, "delay", 0)
     }}
  end

  def validate_payload("led", %{"r" => r, "g" => g, "b" => b})
      when is_integer(r) and is_integer(g) and is_integer(b) do
    {:ok, %{mode: "constant", r: r, g: g, b: b, intensity: 100}}
  end

  # Speaker control (for playing sounds)
  def validate_payload("speaker", %{"frequency" => freq}) when is_number(freq) do
    {:ok, %{frequency: freq, duration: nil}}
  end

  def validate_payload("speaker", %{"frequency" => freq, "duration" => dur})
      when is_number(freq) and is_number(dur) do
    {:ok, %{frequency: freq, duration: dur}}
  end

  def validate_payload("speaker", %{"sample" => sample}) when is_integer(sample) do
    {:ok, %{sample: sample}}
  end

  # Microphone data (audio samples or level)
  def validate_payload("microphone", %{"level" => level}) when is_number(level) do
    {:ok, %{level: level, unit: "dB"}}
  end

  def validate_payload("microphone", %{"samples" => samples}) when is_list(samples) do
    {:ok, %{samples: samples}}
  end

  # Battery validation
  def validate_payload("battery", payload), do: BatteryPayload.from_map(payload)

  # Fallback for unknown payloads
  def validate_payload(_, _), do: {:error, :invalid_payload}

  @impl true
  def default_config do
    %{
      sampling_rate: 5,
      batch_size: 1,
      environment_interval: 1000,
      motion_interval: 200,
      led_mode: "breathe",
      led_color: %{r: 0, g: 255, b: 100}
    }
  end

  @impl true
  def attribute_metadata("temperature") do
    %{
      unit: "°C",
      range: {-40, 85},
      resolution: 0.01,
      description: "Ambient temperature from LPS22HB sensor"
    }
  end

  def attribute_metadata("pressure") do
    %{
      unit: "hPa",
      range: {260, 1260},
      resolution: 0.01,
      description: "Barometric pressure from LPS22HB sensor"
    }
  end

  def attribute_metadata("humidity") do
    %{
      unit: "%",
      range: {0, 100},
      resolution: 1,
      description: "Relative humidity from HTS221 sensor"
    }
  end

  def attribute_metadata(attr) when attr in ["gas", "air_quality"] do
    %{
      eco2_unit: "ppm",
      tvoc_unit: "ppb",
      eco2_range: {400, 8192},
      tvoc_range: {0, 1187},
      description: "Air quality from CCS811 gas sensor"
    }
  end

  def attribute_metadata("color") do
    %{
      description: "Color and light intensity from BH1745NUC sensor",
      components: [:r, :g, :b, :clear]
    }
  end

  def attribute_metadata("accelerometer") do
    %{
      unit: "m/s²",
      axes: [:x, :y, :z],
      range: {-20, 20},
      description: "Linear acceleration from LIS2DH12"
    }
  end

  def attribute_metadata("gyroscope") do
    %{
      unit: "°/s",
      axes: [:x, :y, :z],
      range: {-2000, 2000},
      description: "Angular velocity from MPU-9250"
    }
  end

  def attribute_metadata("magnetometer") do
    %{
      unit: "µT",
      axes: [:x, :y, :z],
      description: "Magnetic field from MPU-9250"
    }
  end

  def attribute_metadata("quaternion") do
    %{
      components: [:w, :x, :y, :z],
      description: "Orientation as unit quaternion"
    }
  end

  def attribute_metadata("euler") do
    %{
      unit: "°",
      components: [:roll, :pitch, :yaw],
      description: "Orientation as Euler angles"
    }
  end

  def attribute_metadata("heading") do
    %{
      unit: "°",
      range: {0, 360},
      description: "Compass heading relative to magnetic north"
    }
  end

  def attribute_metadata("steps") do
    %{
      unit: "steps",
      description: "Step counter"
    }
  end

  def attribute_metadata("tap") do
    %{
      description: "Tap and double-tap detection"
    }
  end

  def attribute_metadata("orientation") do
    %{
      description: "Device orientation (portrait, landscape, face up/down)"
    }
  end

  def attribute_metadata("button") do
    %{
      description: "User button state"
    }
  end

  def attribute_metadata("led") do
    %{
      modes: ["off", "constant", "breathe", "one_shot"],
      description: "RGB LED control"
    }
  end

  def attribute_metadata("speaker") do
    %{
      frequency_range: {0, 20000},
      description: "Speaker for audio output"
    }
  end

  def attribute_metadata("microphone") do
    %{
      description: "Digital microphone for audio input"
    }
  end

  def attribute_metadata("battery") do
    %{
      unit: "%",
      range: {0, 100},
      description: "Battery level"
    }
  end

  def attribute_metadata(_), do: %{}

  # Bidirectional support for LED and Speaker control
  @impl true
  def handle_command(%{"type" => "led"} = command, context) do
    led_state = %{
      mode: Map.get(command, "mode", "constant"),
      r: Map.get(command, "r", 0),
      g: Map.get(command, "g", 0),
      b: Map.get(command, "b", 0),
      intensity: Map.get(command, "intensity", 100),
      delay: Map.get(command, "delay", 350)
    }

    {:ok, %{command: :set_led, led: led_state, sensor_id: context[:sensor_id]}}
  end

  def handle_command(%{"type" => "speaker", "frequency" => freq} = command, context) do
    {:ok,
     %{
       command: :play_tone,
       frequency: freq,
       duration: Map.get(command, "duration", 500),
       sensor_id: context[:sensor_id]
     }}
  end

  def handle_command(%{"type" => "speaker", "sample" => sample}, context) do
    {:ok, %{command: :play_sample, sample: sample, sensor_id: context[:sensor_id]}}
  end

  def handle_command(_, _), do: {:error, :unknown_command}

  # Helper functions

  defp calculate_luminance(r, g, b) do
    # Relative luminance using ITU-R BT.709 coefficients
    # Scale from 16-bit to normalized
    max_val = max(max(r, g), b)

    if max_val > 0 do
      rn = r / max_val
      gn = g / max_val
      bn = b / max_val
      Float.round(0.2126 * rn + 0.7152 * gn + 0.0722 * bn, 2)
    else
      0.0
    end
  end

  defp calculate_color_temperature(r, _g, b) do
    # Simplified color temperature estimation in Kelvin
    if r > 0 and b > 0 do
      ratio = b / r
      # Approximate mapping (this is a simplification)
      cond do
        ratio > 2.0 -> 10000
        ratio > 1.5 -> 7500
        ratio > 1.0 -> 6500
        ratio > 0.7 -> 5000
        ratio > 0.5 -> 4000
        ratio > 0.3 -> 3000
        true -> 2700
      end
    else
      5000
    end
  end

  defp rgb_to_hex(r, g, b) do
    # Normalize 16-bit values to 8-bit for hex representation
    r8 = min(255, div(r, 257))
    g8 = min(255, div(g, 257))
    b8 = min(255, div(b, 257))
    "#" <> Base.encode16(<<r8, g8, b8>>, case: :lower)
  end

  defp heading_to_direction(heading) when is_number(heading) do
    cond do
      heading >= 337.5 or heading < 22.5 -> "N"
      heading >= 22.5 and heading < 67.5 -> "NE"
      heading >= 67.5 and heading < 112.5 -> "E"
      heading >= 112.5 and heading < 157.5 -> "SE"
      heading >= 157.5 and heading < 202.5 -> "S"
      heading >= 202.5 and heading < 247.5 -> "SW"
      heading >= 247.5 and heading < 292.5 -> "W"
      heading >= 292.5 and heading < 337.5 -> "NW"
      true -> "?"
    end
  end

  defp decode_tap_direction(value) do
    case value do
      1 -> "X+"
      2 -> "X-"
      3 -> "Y+"
      4 -> "Y-"
      5 -> "Z+"
      6 -> "Z-"
      _ -> "unknown"
    end
  end

  defp decode_orientation(value) do
    case value do
      0 -> "portrait"
      1 -> "landscape"
      2 -> "reverse_portrait"
      3 -> "reverse_landscape"
      4 -> "face_up"
      5 -> "face_down"
      _ -> "unknown"
    end
  end
end
