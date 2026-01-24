# Sensocto API Attributes Reference

This document is the canonical reference for all sensor attribute types supported by Sensocto. It serves as the foundation for implementing API clients across platforms (Web BLE, Rust/Dioxus, Unity3D, iOS/SwiftUI, etc.).

**Version:** 1.0
**Last Updated:** 2024

---

## Table of Contents

1. [Overview](#overview)
2. [Message Format](#message-format)
3. [Attribute Types](#attribute-types)
   - [Health / Cardiac](#health--cardiac)
   - [Motion / IMU](#motion--imu)
   - [Location](#location)
   - [Environment](#environment)
   - [Marine / Coral Monitoring](#marine--coral-monitoring)
   - [Device](#device)
   - [Activity](#activity)
   - [AI / Inference](#ai--inference)
4. [Simulator Configuration](#simulator-configuration)
5. [Client Implementation Guide](#client-implementation-guide)

---

## Overview

Sensocto uses a sensor-attribute model where:
- **Sensors** are physical or virtual devices (e.g., "person_1", "drone_1")
- **Attributes** are data streams from sensors (e.g., "heartrate", "geolocation")
- Each attribute produces **messages** containing timestamped payloads

### Key Concepts

| Concept | Description |
|---------|-------------|
| `sensor_id` | Unique identifier for the sensor (string) |
| `attribute_id` | Identifier for the data type within a sensor (string) |
| `sensor_type` | Category hint for the attribute (matches attribute type) |
| `sampling_rate` | Data frequency in Hz (samples per second) |
| `batch_size` | Number of samples per message batch |
| `batch_window` | Time window in ms for collecting batch |

---

## Message Format

All sensor data is transmitted as batched messages with the following structure:

### Single Message

```json
{
  "timestamp": 1704067200000,
  "delay": 0.1,
  "payload": { ... }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | integer | Unix timestamp in milliseconds |
| `delay` | float | Seconds until next sample (1/sampling_rate) |
| `payload` | object/number | Attribute-specific data (see below) |

### Batch Message

```json
{
  "sensor_id": "person_1",
  "attribute_id": "heartrate",
  "messages": [
    { "timestamp": 1704067200000, "delay": 0.0, "payload": { "bpm": 72 } },
    { "timestamp": 1704067201000, "delay": 1.0, "payload": { "bpm": 73 } }
  ]
}
```

---

## Attribute Types

### Health / Cardiac

#### `ecg`

ECG waveform data for cardiac monitoring.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `values` | array[float] | mV | Waveform sample values |

**Typical Configuration:**
- Sampling Rate: 100-500 Hz
- Batch Size: 100 (1 second at 100Hz)
- Batch Window: 1000 ms

```yaml
ecg:
  sensor_type: "ecg"
  batch_size: 100
  batch_window: 1000
  sampling_rate: 100
  heart_rate: 72  # For simulation
```

---

#### `heartrate` / `hr`

Heart rate in beats per minute.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `bpm` | integer | bpm | Beats per minute |

**Typical Configuration:**
- Sampling Rate: 0.2-1 Hz
- Batch Size: 1

```yaml
heartrate:
  sensor_type: "heartrate"
  batch_size: 1
  batch_window: 5000
  sampling_rate: 0.2
  heart_rate: 72  # Base value for simulation
```

---

#### `hrv`

Heart rate variability metrics.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `rmssd` | float | ms | Root mean square of successive differences |
| `sdnn` | float | ms | Standard deviation of NN intervals |

---

#### `spo2`

Blood oxygen saturation.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | % | Oxygen saturation percentage (0-100) |

**Typical Configuration:**
```yaml
spo2:
  sensor_type: "spo2"
  batch_size: 1
  batch_window: 5000
  sampling_rate: 0.2
  min_value: 96
  max_value: 99
```

---

#### `respiration`

Respiratory rate.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | breaths/min | Breathing rate |

---

### Motion / IMU

#### `accelerometer`

Linear acceleration data.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `x` | float | m/s² | X-axis acceleration |
| `y` | float | m/s² | Y-axis acceleration |
| `z` | float | m/s² | Z-axis acceleration |

---

#### `gyroscope`

Angular velocity data.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `x` | float | rad/s | X-axis rotation rate |
| `y` | float | rad/s | Y-axis rotation rate |
| `z` | float | rad/s | Z-axis rotation rate |

---

#### `magnetometer`

Magnetic field data.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `x` | float | µT | X-axis magnetic field |
| `y` | float | µT | Y-axis magnetic field |
| `z` | float | µT | Z-axis magnetic field |

---

#### `imu`

Combined IMU data (accelerometer, gyroscope, magnetometer).

| Field | Type | Description |
|-------|------|-------------|
| `accelerometer` | object | `{x, y, z}` in m/s² |
| `gyroscope` | object | `{x, y, z}` in rad/s |
| `magnetometer` | object | `{x, y, z}` in µT |

---

#### `quaternion`

Rotation quaternion for 3D orientation.

| Field | Type | Description |
|-------|------|-------------|
| `w` | float | Scalar component |
| `x` | float | X component |
| `y` | float | Y component |
| `z` | float | Z component |

---

#### `euler`

Euler angles for orientation.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `roll` | float | degrees | Roll angle |
| `pitch` | float | degrees | Pitch angle |
| `yaw` | float | degrees | Yaw angle |

---

#### `heading`

Magnetic heading/compass direction.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | degrees | Heading (0-360, 0=North) |

---

#### `gravity`

Gravity vector.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `x` | float | m/s² | X-axis gravity component |
| `y` | float | m/s² | Y-axis gravity component |
| `z` | float | m/s² | Z-axis gravity component |

---

#### `tap`

Tap/gesture detection events.

| Field | Type | Description |
|-------|------|-------------|
| `direction` | string | Tap direction ("up", "down", "left", "right", "front", "back") |

---

### Location

#### `geolocation`

GPS/location coordinates.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `latitude` | float | degrees | Latitude (-90 to 90) |
| `longitude` | float | degrees | Longitude (-180 to 180) |
| `altitude` | float | meters | Altitude above sea level (optional) |
| `speed` | float | m/s | Speed over ground (optional) |
| `heading` | float | degrees | Direction of travel (optional) |
| `accuracy` | float | meters | Position accuracy (optional) |

**Simulator Track Modes:**
- `walk` - Walking speed (~5 km/h)
- `cycle` - Cycling speed (~20 km/h)
- `car` - Driving speed (~50 km/h)
- `train` - Rail speed (~100 km/h)
- `bird` - Bird migration pattern
- `drone` - Drone survey pattern
- `boat` - Marine vessel
- `stationary` - Fixed position

**Configuration Example:**
```yaml
geolocation:
  sensor_type: "geolocation"
  batch_size: 1
  batch_window: 1000
  sampling_rate: 1
  track_mode: "walk"
  playback_speed: 2
  random_start: false
```

---

#### `altitude`

Altitude/elevation data.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | meters | Altitude above sea level |

---

#### `speed`

Speed/velocity data.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | m/s | Speed |

---

### Environment

#### `temperature`

Temperature reading.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | °C | Temperature in Celsius |

---

#### `humidity`

Relative humidity.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | % | Relative humidity (0-100) |

---

#### `pressure`

Atmospheric pressure.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | hPa | Pressure in hectopascals |

---

#### `light`

Light intensity.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | lux | Light level |

---

#### `gas` / `air_quality`

Air quality sensor (CO2 and TVOC).

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `eco2` | integer | ppm | Equivalent CO2 |
| `tvoc` | integer | ppb | Total Volatile Organic Compounds |

---

#### `color`

RGB color sensor.

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `r` | integer | 0-255 | Red component |
| `g` | integer | 0-255 | Green component |
| `b` | integer | 0-255 | Blue component |

---

### Marine / Coral Monitoring

These attributes are designed for ocean/reef monitoring applications.

#### `water_temperature` / `sea_surface_temperature`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | °C | Water temperature |

Coral bleaching thresholds: Stress begins ~29°C, bleaching ~30°C

---

#### `salinity`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | ppt | Parts per thousand (coral ideal: 32-42) |

---

#### `ph`

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `value` | float | 0-14 | pH level (healthy reef: 7.8-8.5) |

---

#### `dissolved_oxygen`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | mg/L | Dissolved oxygen (healthy: >6 mg/L) |

---

#### `turbidity`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | NTU | Nephelometric Turbidity Units (ideal: <10) |

---

#### `depth`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | meters | Water depth |

---

#### `light_par`

Photosynthetically Active Radiation.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | µmol/m²/s | PAR intensity |

---

#### `nitrate` / `phosphate` / `ammonia`

Nutrient sensors.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | µmol/L | Nutrient concentration |

---

#### `alkalinity`

Carbonate chemistry for calcification.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | µmol/kg | Total alkalinity |

---

#### `current_speed` / `current_direction`

Ocean current measurements.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | m/s or degrees | Current speed or direction |

---

#### `wave_height`

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | meters | Wave height |

---

### Device

#### `battery`

Battery status with charging state.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `level` | float | % | Battery percentage (0-100) |
| `charging` | boolean | - | Whether device is charging |

The simulator maintains realistic battery behavior with:
- Drain rate: ~0.5% per minute (active)
- Charge rate: ~0.8% per minute
- Random charging state flips every 1-5 minutes

---

#### `button`

Button/switch state.

| Field | Type | Description |
|-------|------|-------------|
| `pressed` | boolean | Button pressed state |

---

#### `led`

LED control state.

| Field | Type | Description |
|-------|------|-------------|
| `mode` | string | LED mode ("off", "on", "blink", "pulse") |
| `r` | integer | Red (0-255) |
| `g` | integer | Green (0-255) |
| `b` | integer | Blue (0-255) |

---

#### `microphone`

Audio input level.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `level` | float | dB | Audio level in decibels |

---

#### `rich_presence`

Rich status/presence information.

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Presence title |
| `description` | string | Status description |
| `url` | string | Associated URL (optional) |
| `image` | string | Image URL (optional) |

---

### Activity

#### `steps`

Step counter.

| Field | Type | Description |
|-------|------|-------------|
| `count` | integer | Cumulative step count |

---

#### `calories`

Calories burned.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | kcal | Calories |

---

#### `distance`

Distance traveled.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | meters | Distance |

---

### AI / Inference

These attributes are for AI-powered detection systems (e.g., underwater camera analysis).

#### `fish_count`

Fish detection count.

| Field | Type | Description |
|-------|------|-------------|
| `value` | integer | Number of fish detected |

---

#### `species_diversity`

Biodiversity index.

| Field | Type | Description |
|-------|------|-------------|
| `value` | float | Shannon diversity index |

---

#### `coral_coverage` / `algae_coverage` / `bleaching_index`

Coverage percentages from image analysis.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `value` | float | % | Coverage or index percentage |

---

#### `inference_confidence`

AI model confidence score.

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `value` | float | 0-1 | Confidence score |

---

## Simulator Configuration

### YAML Scenario Format

Simulator scenarios are defined in YAML files under `config/simulator_scenarios/`.

```yaml
# scenario_name.yaml
connectors:
  connector_id:
    connector_id: "unique_id"
    connector_name: "Display Name"
    sensors:
      sensor_id:
        sensor_id: "sensor_1"
        sensor_name: "Sensor Display Name"
        attributes:
          attribute_id:
            attribute_id: "heartrate"
            sensor_type: "heartrate"
            batch_size: 1
            batch_window: 5000    # ms
            duration: 0          # 0 = continuous
            sampling_rate: 0.2   # Hz
            # Type-specific options:
            heart_rate: 72       # For cardiac types
            min_value: 60        # For generic types
            max_value: 100
            dummy_data: true
```

### Common Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `batch_size` | integer | Samples per batch message |
| `batch_window` | integer | Collection window in ms |
| `sampling_rate` | float | Samples per second (Hz) |
| `duration` | integer | Simulation duration (0 = continuous) |
| `dummy_data` | boolean | Use built-in data generator |
| `min_value` | float | Minimum value for generic types |
| `max_value` | float | Maximum value for generic types |

### GPS Track Options

| Option | Type | Description |
|--------|------|-------------|
| `track_mode` | string | Movement type (walk, cycle, car, drone, etc.) |
| `playback_speed` | float | Speed multiplier (1.0 = real-time) |
| `random_start` | boolean | Start at random track position |
| `no_loop` | boolean | Stop at end instead of looping |
| `track_name` | string | Specific track file name |
| `generate_track` | boolean | Generate procedural track |
| `start_lat` | float | Starting latitude for generated track |
| `start_lng` | float | Starting longitude for generated track |
| `track_duration` | integer | Duration in minutes for generated track |

---

## Client Implementation Guide

### Connection Protocol

Sensocto supports multiple connection methods:

1. **WebSocket (Phoenix Channels)** - Primary method for web clients
2. **Web Bluetooth (BLE)** - Direct sensor connection
3. **REST API** - For mobile apps (JWT authentication)

### WebSocket Channel Topics

| Topic | Description |
|-------|-------------|
| `sensor:lobby` | Global sensor updates (all sensors) |
| `room:{room_id}` | Room-specific sensor updates |
| `presence:all` | Sensor online/offline status |

### Message Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `sensor_batch` | Server → Client | Batch of sensor data |
| `presence_state` | Server → Client | Initial presence state |
| `presence_diff` | Server → Client | Presence changes |

### Example: Subscribing to Sensor Data (JavaScript)

```javascript
import { Socket } from "phoenix"

const socket = new Socket("/socket", { params: { token: userToken } })
socket.connect()

// Join room channel
const channel = socket.channel(`room:${roomId}`, {})
channel.join()
  .receive("ok", () => console.log("Joined room"))
  .receive("error", (resp) => console.error("Join failed", resp))

// Handle sensor data
channel.on("sensor_batch", (payload) => {
  const { sensor_id, attribute_id, messages } = payload
  messages.forEach(msg => {
    console.log(`${sensor_id}/${attribute_id}:`, msg.payload)
  })
})
```

### Example: Mobile API Authentication

```bash
# Get QR code token from Settings page, then:
curl -H "Authorization: Bearer <token>" \
     https://sensocto.app/api/auth/verify

# Response:
{
  "ok": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "User Name"
  }
}
```

### Recommended Sampling Rates by Attribute Type

| Category | Attribute | Typical Rate | Notes |
|----------|-----------|--------------|-------|
| High Frequency | ECG | 100-500 Hz | Real-time waveform |
| High Frequency | IMU | 50-200 Hz | Motion tracking |
| Medium Frequency | Geolocation | 1 Hz | GPS updates |
| Low Frequency | Heartrate | 0.2 Hz | Vital signs |
| Low Frequency | Temperature | 0.017 Hz | Environmental |
| Low Frequency | Battery | 0.1 Hz | Device status |

### Error Handling

All API responses follow this format:

```json
// Success
{ "ok": true, "data": { ... } }

// Error
{ "ok": false, "error": "Error description" }
```

---

## Validation

Use the `Sensocto.Types.AttributeType` module for validation:

```elixir
alias Sensocto.Types.AttributeType

# Check validity
AttributeType.valid?("ecg")       # true
AttributeType.valid?("unknown")   # false

# Normalize (lowercase)
AttributeType.normalize("ECG")    # {:ok, "ecg"}

# Get category
AttributeType.category("ecg")     # :health

# Get render hints (for UI)
AttributeType.render_hints("ecg") # %{chart_type: :waveform, ...}

# Get expected payload fields
AttributeType.expected_payload_fields("ecg") # ["values"]
```

---

## See Also

- [Getting Started Guide](getting-started.md)
- [Architecture Overview](architecture.md)
- [Simulator Integration](simulator-integration.md)
