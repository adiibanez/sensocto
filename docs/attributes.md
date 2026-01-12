# Sensor Attribute Types

This document lists all supported sensor attribute types in Sensocto. Attribute types define the kind of data a sensor produces and determine how it is displayed in the UI.

## Overview

Attribute types are organized into categories for easier navigation. Each type has:
- A unique identifier (lowercase string)
- Expected payload fields
- A default visualization component

**Source:** `lib/sensocto/types/attribute_type.ex`

---

## Health / Cardiac

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `ecg` | `values` (array) | Waveform chart | ECG waveform data, typically 100Hz+ |
| `heartrate` | `bpm` | Sparkline | Heart rate in beats per minute |
| `hr` | `bpm` | Sparkline | Alias for heartrate |
| `hrv` | `rmssd`, `sdnn` | Sparkline | Heart rate variability metrics |
| `spo2` | `value` | Gauge | Blood oxygen saturation (%) |
| `respiration` | `value` | Sparkline | Breathing rate |

---

## Motion / IMU

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `imu` | `accelerometer`, `gyroscope`, `magnetometer` | Multi-axis chart | Combined IMU data |
| `accelerometer` | `x`, `y`, `z` | Multi-axis chart | Linear acceleration (m/s^2) |
| `gyroscope` | `x`, `y`, `z` | Multi-axis chart | Angular velocity (rad/s) |
| `magnetometer` | `x`, `y`, `z` | Multi-axis chart | Magnetic field (uT) |
| `gravity` | `x`, `y`, `z` | Multi-axis chart | Gravity vector |
| `quaternion` | `w`, `x`, `y`, `z` | 3D orientation | Rotation quaternion |
| `euler` | `roll`, `pitch`, `yaw` | 3D orientation | Euler angles (degrees) |
| `heading` | `value` | Compass | Magnetic heading (degrees) |
| `orientation` | `value` | Orientation display | Device orientation |
| `tap` | `direction` | Event indicator | Tap/gesture detection |

---

## Location

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `geolocation` | `latitude`, `longitude` | Map | GPS coordinates |
| `altitude` | `value` | Sparkline | Altitude (meters) |
| `speed` | `value` | Sparkline | Speed (m/s) |

---

## Environment

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `temperature` | `value` | Gauge | Temperature (Celsius) |
| `humidity` | `value` | Gauge | Relative humidity (%) |
| `pressure` | `value` | Gauge | Atmospheric pressure (hPa) |
| `light` | `value` | Sparkline | Light intensity (lux) |
| `proximity` | `value` | Sparkline | Proximity sensor reading |
| `gas` | `eco2`, `tvoc` | Gauge | Gas sensor (CO2 ppm, TVOC ppb) |
| `air_quality` | `eco2`, `tvoc` | Gauge | Air quality index |
| `color` | `r`, `g`, `b` | Color swatch | Color sensor RGB values |

---

## Device

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `battery` | `level` | Battery gauge | Battery percentage (0-100) |
| `button` | `pressed` | Button indicator | Button press state |
| `led` | `mode`, `r`, `g`, `b` | LED control | LED state and color |
| `speaker` | `frequency` | Speaker control | Audio output control |
| `microphone` | `level` | Level meter | Audio input level |
| `body_location` | `value` | Info display | Sensor placement on body |
| `rich_presence` | `title`, `description`, `url`, `image` | Card | Rich presence/status info |

---

## Activity

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `steps` | `count` | Counter | Step count |
| `calories` | `value` | Sparkline | Calories burned |
| `distance` | `value` | Sparkline | Distance traveled (meters) |

---

## Specialty

| Type | Payload Fields | Visualization | Description |
|------|----------------|---------------|-------------|
| `buttplug` | `command` | Control | Haptic device control |

---

## Adding New Attribute Types

To add a new attribute type:

1. Add it to the `@attribute_types` list in `lib/sensocto/types/attribute_type.ex`
2. Define its category in the `category/1` function
3. Add render hints in the `render_hints/1` function
4. Define expected payload fields in `expected_payload_fields/1`
5. Implement rendering in `lib/sensocto_web/live/components/attribute_component.ex`
   - Create both `:summary` and full view render clauses

Example:

```elixir
# In attribute_type.ex
@attribute_types [
  # ...
  "my_new_type"
]

def category("my_new_type"), do: :device

def render_hints("my_new_type") do
  %{chart_type: :sparkline, component: "MyComponent", color: "#abc123"}
end

def expected_payload_fields("my_new_type"), do: ["value", "unit"]
```

## Validation

Use the `AttributeType` module to validate types:

```elixir
alias Sensocto.Types.AttributeType

# Check if valid
AttributeType.valid?("ecg")      # true
AttributeType.valid?("unknown")  # false

# Normalize (lowercase)
AttributeType.normalize("ECG")   # {:ok, "ecg"}

# Get category
AttributeType.category("ecg")    # :health

# Get all types
AttributeType.all()              # ["ecg", "hrv", ...]
```
