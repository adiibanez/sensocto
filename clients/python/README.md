# Sensocto Python SDK

[![Python SDK CI](https://github.com/sensocto/sensocto/actions/workflows/python-sdk.yml/badge.svg)](https://github.com/sensocto/sensocto/actions/workflows/python-sdk.yml)
[![PyPI](https://img.shields.io/pypi/v/sensocto.svg)](https://pypi.org/project/sensocto/)
[![Python Versions](https://img.shields.io/pypi/pyversions/sensocto.svg)](https://pypi.org/project/sensocto/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Code style: black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)
[![Ruff](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json)](https://github.com/astral-sh/ruff)

Python client library for connecting to the Sensocto sensor platform. Stream real-time sensor data, join video/voice calls, and manage rooms.

## Features

- Async-first design using asyncio
- Real-time sensor data streaming via Phoenix WebSocket channels
- Video/voice call support via WebRTC signaling
- Automatic backpressure handling
- Type hints and Pydantic models for data validation
- Context manager support for clean resource management

## Installation

```bash
pip install sensocto
```

Or with optional sync support:

```bash
pip install sensocto[sync]
```

## Quick Start

### Basic Connection

```python
import asyncio
from sensocto import SensoctoClient, SensorConfig

async def main():
    # Create and connect client
    client = SensoctoClient(
        server_url="https://your-sensocto-server.com",
        bearer_token="your-auth-token",
        connector_name="Python Sensor Device",
    )

    await client.connect()
    print("Connected to Sensocto!")

    # ... do work ...

    await client.disconnect()

asyncio.run(main())
```

### Using Context Manager

```python
async def main():
    async with SensoctoClient(
        server_url="https://your-server.com",
        bearer_token="your-token",
    ) as client:
        # Client is connected and will auto-disconnect on exit
        sensor = await client.register_sensor(
            SensorConfig(sensor_name="My Sensor")
        )
        await sensor.send_measurement("temperature", {"value": 23.5})
```

### Streaming Sensor Data

```python
import asyncio
from sensocto import SensoctoClient, SensorConfig

async def main():
    async with SensoctoClient(
        server_url="https://your-server.com",
        bearer_token="your-token",
    ) as client:

        # Configure sensor
        sensor_config = SensorConfig(
            sensor_name="Temperature Sensor",
            sensor_type="temperature",
            attributes=["celsius", "fahrenheit", "humidity"],
            sampling_rate_hz=10,
            batch_size=5,
        )

        # Register sensor
        sensor = await client.register_sensor(sensor_config)

        # Handle backpressure updates
        def on_backpressure(config):
            print(f"Attention level: {config.attention_level}")
            print(f"Recommended batch size: {config.recommended_batch_size}")

        sensor.on_backpressure(on_backpressure)

        # Send measurements
        while True:
            # Single measurement
            await sensor.send_measurement(
                "celsius",
                {"value": 23.5, "unit": "C"}
            )

            # Or use batching for efficiency
            await sensor.add_to_batch("celsius", {"value": 23.6})
            await sensor.add_to_batch("humidity", {"value": 45.2})

            # Batch is automatically flushed when it reaches the configured size
            # Or flush manually:
            # await sensor.flush_batch()

            await asyncio.sleep(0.1)

asyncio.run(main())
```

### IMU Sensor Data

```python
async def stream_imu_data(client):
    sensor_config = SensorConfig(
        sensor_name="IMU Sensor",
        sensor_type="imu",
        attributes=["accelerometer", "gyroscope", "magnetometer"],
        sampling_rate_hz=100,
        batch_size=10,
    )

    sensor = await client.register_sensor(sensor_config)

    while True:
        # Simulated IMU data - replace with actual sensor readings
        accel = {"x": 0.01, "y": 0.02, "z": 9.81}
        gyro = {"x": 0.001, "y": -0.002, "z": 0.0005}

        await sensor.add_to_batch("accelerometer", accel)
        await sensor.add_to_batch("gyroscope", gyro)

        await asyncio.sleep(0.01)  # 100 Hz
```

### Video/Voice Calls

```python
from sensocto import (
    SensoctoClient,
    CallEvent,
    ParticipantJoinedEvent,
    ParticipantLeftEvent,
    MediaEventReceived,
    CallEndedEvent,
)

async def join_video_call(client):
    # Join call channel
    user_info = {
        "name": "Alice",
        "avatar": "https://example.com/avatar.png",
    }

    call = await client.join_call(
        room_id="room-123",
        user_id="user-456",
        user_info=user_info,
    )

    # Handle call events
    def on_call_event(event: CallEvent):
        if isinstance(event, ParticipantJoinedEvent):
            print(f"Participant joined: {event.participant.user_id}")
        elif isinstance(event, ParticipantLeftEvent):
            print(f"Participant left: {event.user_id}")
        elif isinstance(event, MediaEventReceived):
            # Handle WebRTC signaling
            print(f"Media event: {event.data}")
        elif isinstance(event, CallEndedEvent):
            print("Call ended")

    call.on_event(on_call_event)

    # Actually join the call
    result = await call.join_call()
    print(f"Joined call with endpoint: {result.get('endpoint_id')}")

    # Get ICE servers for WebRTC
    print(f"ICE servers: {call.ice_servers}")

    # Toggle audio/video
    await call.toggle_audio(True)
    await call.toggle_video(False)

    # Send WebRTC signaling data
    await call.send_media_event({
        "type": "offer",
        "sdp": "..."
    })

    # Get participants
    participants = await call.get_participants()
    print(f"Participants: {participants}")

    # Leave call when done
    await call.leave_call()
```

## Configuration Options

```python
from sensocto import SensoctoClient

client = SensoctoClient(
    # Required
    server_url="https://sensocto.example.com",

    # Authentication
    bearer_token="your-jwt-token",

    # Connector identity
    connector_name="My Python Device",
    connector_type="iot",
    connector_id="custom-id",  # Auto-generated if not set

    # Connection behavior
    auto_join_connector=True,
    auto_reconnect=True,
    max_reconnect_attempts=5,

    # Timing
    heartbeat_interval_seconds=30.0,
    connection_timeout_seconds=10.0,

    # Features
    features=["streaming", "calls"],
)
```

## Error Handling

```python
from sensocto import (
    SensoctoClient,
    SensoctoError,
    ConnectionError,
    AuthenticationError,
    TimeoutError,
    ChannelJoinError,
)

async def handle_errors():
    client = SensoctoClient(server_url="https://server.com")

    try:
        await client.connect()
    except ConnectionError as e:
        print(f"Connection failed: {e}")
    except AuthenticationError as e:
        print(f"Auth failed: {e}")
    except TimeoutError as e:
        print(f"Timed out after {e.timeout_ms}ms")
    except SensoctoError as e:
        print(f"Other error: {e}")
```

## Backpressure Handling

The server sends backpressure configuration to help you adjust data transmission rates:

```python
from sensocto import AttentionLevel

def on_backpressure(config):
    if config.attention_level == AttentionLevel.HIGH:
        # Server wants fast updates
        print("High attention - increasing update rate")
    elif config.attention_level in (AttentionLevel.LOW, AttentionLevel.NONE):
        # Server has low attention - can batch more aggressively
        print("Low attention - batching more data")

    # Use recommended settings
    print(f"Recommended batch size: {config.recommended_batch_size}")
    print(f"Recommended batch window: {config.recommended_batch_window}ms")

sensor.on_backpressure(on_backpressure)
```

## Attribute ID Rules

Attribute IDs must:
- Start with a letter (a-z, A-Z)
- Contain only alphanumeric characters, underscores, or hyphens
- Be 1-64 characters long

Valid examples: `heart_rate`, `accelerometer`, `gps-location`, `temp1`

## Jupyter Notebook Support

The SDK works well in Jupyter notebooks and interactive environments:

```python
# In a Jupyter cell
import asyncio
from sensocto import SensoctoClient, SensorConfig

# Create client
client = SensoctoClient(
    server_url="https://your-server.com",
    bearer_token="your-token",
)

# Connect (use nest_asyncio if needed)
await client.connect()

# Register sensor
sensor = await client.register_sensor(
    SensorConfig(sensor_name="Notebook Sensor")
)

# Send data
await sensor.send_measurement("value", {"data": 42})

# Clean up
await client.disconnect()
```

## Development

### Running Tests

```bash
pip install -e ".[dev]"
pytest
```

### Type Checking

```bash
mypy sensocto
```

### Formatting

```bash
black sensocto
ruff check sensocto
```

## License

MIT License - see LICENSE file for details.

## Support

- Documentation: https://docs.sensocto.com
- Issues: https://github.com/sensocto/python-sdk/issues
- Email: support@sensocto.com
