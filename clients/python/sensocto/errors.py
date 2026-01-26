"""Error types for the Sensocto client."""

from typing import Optional


class SensoctoError(Exception):
    """Base exception for all Sensocto errors."""

    def __init__(self, message: str, cause: Optional[Exception] = None):
        super().__init__(message)
        self.message = message
        self.cause = cause

    def __str__(self) -> str:
        if self.cause:
            return f"{self.message}: {self.cause}"
        return self.message


class ConnectionError(SensoctoError):
    """Raised when connection to the server fails."""

    pass


class ChannelJoinError(SensoctoError):
    """Raised when joining a channel fails."""

    def __init__(self, topic: str, reason: str):
        super().__init__(f"Failed to join channel '{topic}': {reason}")
        self.topic = topic
        self.reason = reason


class AuthenticationError(SensoctoError):
    """Raised when authentication fails."""

    pass


class TimeoutError(SensoctoError):
    """Raised when an operation times out."""

    def __init__(self, timeout_ms: int):
        super().__init__(f"Operation timed out after {timeout_ms}ms")
        self.timeout_ms = timeout_ms


class InvalidConfigError(SensoctoError):
    """Raised when configuration is invalid."""

    pass


class DisconnectedError(SensoctoError):
    """Raised when trying to perform an operation while disconnected."""

    def __init__(self) -> None:
        super().__init__("Client is disconnected")


class InvalidAttributeIdError(SensoctoError):
    """Raised when an attribute ID is invalid."""

    def __init__(self, attribute_id: str, reason: str):
        super().__init__(f"Invalid attribute ID '{attribute_id}': {reason}")
        self.attribute_id = attribute_id
        self.reason = reason
