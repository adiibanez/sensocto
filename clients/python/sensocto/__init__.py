"""
Sensocto Python SDK

Python client library for connecting to the Sensocto sensor platform.
Supports real-time sensor data streaming, video/voice calls, and room management.

Example:
    >>> import asyncio
    >>> from sensocto import SensoctoClient, SensorConfig
    >>>
    >>> async def main():
    ...     client = SensoctoClient(
    ...         server_url="https://your-server.com",
    ...         bearer_token="your-token"
    ...     )
    ...     await client.connect()
    ...
    ...     sensor = await client.register_sensor(
    ...         SensorConfig(sensor_name="My Sensor", sensor_type="temperature")
    ...     )
    ...     await sensor.send_measurement("celsius", {"value": 23.5})
    ...
    >>> asyncio.run(main())
"""

from sensocto.call import CallSession
from sensocto.client import SensoctoClient
from sensocto.config import SensoctoConfig, SensorConfig
from sensocto.errors import (
    AuthenticationError,
    ChannelJoinError,
    ConnectionError,
    InvalidConfigError,
    SensoctoError,
    TimeoutError,
)
from sensocto.models import (
    AttentionLevel,
    BackpressureConfig,
    CallEvent,
    CallParticipant,
    ConnectionState,
    Measurement,
    Room,
    RoomRole,
    SensorEvent,
    User,
)
from sensocto.sensor import SensorStream

__version__ = "0.1.0"
__author__ = "Sensocto"
__email__ = "support@sensocto.com"

__all__ = [
    # Main client
    "SensoctoClient",
    # Configuration
    "SensoctoConfig",
    "SensorConfig",
    # Streams and sessions
    "SensorStream",
    "CallSession",
    # Models
    "AttentionLevel",
    "BackpressureConfig",
    "CallEvent",
    "CallParticipant",
    "ConnectionState",
    "Measurement",
    "Room",
    "RoomRole",
    "SensorEvent",
    "User",
    # Errors
    "SensoctoError",
    "ConnectionError",
    "ChannelJoinError",
    "AuthenticationError",
    "TimeoutError",
    "InvalidConfigError",
]
