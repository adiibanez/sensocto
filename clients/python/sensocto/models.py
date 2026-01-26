"""Data models for the Sensocto client."""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Union

from pydantic import BaseModel, Field


class ConnectionState(str, Enum):
    """Connection state of the client."""

    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    RECONNECTING = "reconnecting"
    ERROR = "error"


class AttentionLevel(str, Enum):
    """Server attention level for backpressure control."""

    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

    @property
    def recommended_batch_window(self) -> int:
        """Returns the recommended batch window in milliseconds."""
        windows = {
            AttentionLevel.HIGH: 100,
            AttentionLevel.MEDIUM: 500,
            AttentionLevel.LOW: 2000,
            AttentionLevel.NONE: 5000,
        }
        return windows[self]

    @property
    def recommended_batch_size(self) -> int:
        """Returns the recommended batch size."""
        sizes = {
            AttentionLevel.HIGH: 1,
            AttentionLevel.MEDIUM: 5,
            AttentionLevel.LOW: 10,
            AttentionLevel.NONE: 20,
        }
        return sizes[self]


class RoomRole(str, Enum):
    """Room membership role."""

    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class Measurement(BaseModel):
    """A single sensor measurement."""

    attribute_id: str = Field(..., description="The attribute identifier")
    payload: Union[Dict[str, Any], float, int, List[Any]] = Field(
        ..., description="The measurement payload"
    )
    timestamp: int = Field(..., description="Unix timestamp in milliseconds")

    @classmethod
    def create(
        cls,
        attribute_id: str,
        payload: Union[Dict[str, Any], float, int, List[Any]],
        timestamp: Optional[int] = None,
    ) -> "Measurement":
        """Creates a measurement with optional auto-generated timestamp."""
        if timestamp is None:
            timestamp = int(datetime.utcnow().timestamp() * 1000)
        return cls(attribute_id=attribute_id, payload=payload, timestamp=timestamp)


class BackpressureConfig(BaseModel):
    """Backpressure configuration from the server."""

    attention_level: AttentionLevel = AttentionLevel.NONE
    recommended_batch_window: int = 500
    recommended_batch_size: int = 5
    timestamp: int = 0

    @classmethod
    def from_payload(cls, payload: Dict[str, Any]) -> "BackpressureConfig":
        """Creates a BackpressureConfig from a server payload."""
        attention = payload.get("attention_level", "none")
        try:
            attention_level = AttentionLevel(attention)
        except ValueError:
            attention_level = AttentionLevel.NONE

        return cls(
            attention_level=attention_level,
            recommended_batch_window=payload.get("recommended_batch_window", 500),
            recommended_batch_size=payload.get("recommended_batch_size", 5),
            timestamp=payload.get("timestamp", 0),
        )


class Room(BaseModel):
    """A room in Sensocto."""

    id: str
    name: str
    description: Optional[str] = None
    join_code: Optional[str] = None
    is_public: bool = True
    calls_enabled: bool = True
    owner_id: str
    configuration: Dict[str, Any] = Field(default_factory=dict)


class User(BaseModel):
    """A user in Sensocto."""

    id: str
    email: Optional[str] = None


class CallParticipant(BaseModel):
    """A call participant."""

    user_id: str
    endpoint_id: str
    user_info: Dict[str, Any] = Field(default_factory=dict)
    joined_at: Optional[str] = None
    audio_enabled: bool = False
    video_enabled: bool = False


class IceServer(BaseModel):
    """ICE server configuration for WebRTC."""

    urls: List[str]
    username: Optional[str] = None
    credential: Optional[str] = None


@dataclass
class SensorEvent:
    """Base class for sensor events."""

    pass


@dataclass
class BackpressureConfigEvent(SensorEvent):
    """Backpressure configuration update event."""

    config: BackpressureConfig


@dataclass
class GenericSensorEvent(SensorEvent):
    """Generic sensor event with payload."""

    event: str
    payload: Dict[str, Any]


@dataclass
class CallEvent:
    """Base class for call events."""

    pass


@dataclass
class ParticipantJoinedEvent(CallEvent):
    """Event when a participant joins."""

    participant: CallParticipant


@dataclass
class ParticipantLeftEvent(CallEvent):
    """Event when a participant leaves."""

    user_id: str
    crashed: bool = False


@dataclass
class MediaEventReceived(CallEvent):
    """WebRTC media event received."""

    data: Any


@dataclass
class ParticipantAudioChangedEvent(CallEvent):
    """Event when participant audio state changes."""

    user_id: str
    enabled: bool


@dataclass
class ParticipantVideoChangedEvent(CallEvent):
    """Event when participant video state changes."""

    user_id: str
    enabled: bool


@dataclass
class QualityChangedEvent(CallEvent):
    """Event when call quality changes."""

    quality: str


@dataclass
class CallEndedEvent(CallEvent):
    """Event when call ends."""

    pass
