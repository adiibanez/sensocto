"""Configuration types for the Sensocto client."""

from dataclasses import dataclass, field
from typing import List, Optional
from urllib.parse import urlparse
import uuid

from sensocto.errors import InvalidConfigError


@dataclass
class SensoctoConfig:
    """Configuration for the Sensocto client."""

    server_url: str
    """The Sensocto server URL."""

    connector_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    """Unique identifier for this connector."""

    connector_name: str = "Python Connector"
    """Human-readable name for this connector."""

    connector_type: str = "python"
    """Type of connector."""

    bearer_token: Optional[str] = None
    """Bearer token for authentication."""

    auto_join_connector: bool = True
    """Automatically join connector channel on connect."""

    heartbeat_interval_seconds: float = 30.0
    """Heartbeat interval in seconds."""

    connection_timeout_seconds: float = 10.0
    """Connection timeout in seconds."""

    auto_reconnect: bool = True
    """Whether to auto-reconnect on disconnect."""

    max_reconnect_attempts: int = 5
    """Maximum reconnection attempts."""

    features: List[str] = field(default_factory=list)
    """Supported features."""

    def validate(self) -> None:
        """Validates the configuration."""
        if not self.server_url:
            raise InvalidConfigError("Server URL is required")

        parsed = urlparse(self.server_url)
        if parsed.scheme not in ("http", "https"):
            raise InvalidConfigError("Server URL must use http or https scheme")

        if not parsed.netloc:
            raise InvalidConfigError("Server URL must have a host")

        if self.heartbeat_interval_seconds < 1.0:
            raise InvalidConfigError("Heartbeat interval must be at least 1 second")

    @property
    def websocket_url(self) -> str:
        """Returns the WebSocket URL for connecting."""
        parsed = urlparse(self.server_url)
        protocol = "wss" if parsed.scheme == "https" else "ws"
        port = f":{parsed.port}" if parsed.port else ""
        return f"{protocol}://{parsed.hostname}{port}/socket/websocket"


@dataclass
class SensorConfig:
    """Configuration for a sensor."""

    sensor_name: str
    """Human-readable name for the sensor."""

    sensor_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    """Unique sensor identifier."""

    sensor_type: str = "generic"
    """Type of sensor."""

    attributes: List[str] = field(default_factory=list)
    """List of attributes this sensor will report."""

    sampling_rate_hz: int = 10
    """Sampling rate in Hz."""

    batch_size: int = 5
    """Number of measurements to batch."""

    def with_sensor_id(self, sensor_id: str) -> "SensorConfig":
        """Returns a copy with the specified sensor ID."""
        self.sensor_id = sensor_id
        return self

    def with_sensor_type(self, sensor_type: str) -> "SensorConfig":
        """Returns a copy with the specified sensor type."""
        self.sensor_type = sensor_type
        return self

    def with_attributes(self, attributes: List[str]) -> "SensorConfig":
        """Returns a copy with the specified attributes."""
        self.attributes = attributes
        return self

    def with_sampling_rate(self, hz: int) -> "SensorConfig":
        """Returns a copy with the specified sampling rate."""
        self.sampling_rate_hz = hz
        return self

    def with_batch_size(self, size: int) -> "SensorConfig":
        """Returns a copy with the specified batch size."""
        self.batch_size = size
        return self
