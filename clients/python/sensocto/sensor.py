"""Sensor stream implementation."""

import asyncio
import logging
import re
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional, Union

from sensocto.config import SensorConfig
from sensocto.errors import DisconnectedError, InvalidAttributeIdError
from sensocto.models import BackpressureConfig, Measurement
from sensocto.socket import PhoenixSocket

logger = logging.getLogger(__name__)

# Regex pattern for validating attribute IDs
ATTRIBUTE_ID_PATTERN = re.compile(r"^[a-zA-Z][a-zA-Z0-9_-]{0,63}$")


def validate_attribute_id(attribute_id: str) -> None:
    """Validates an attribute ID."""
    if not attribute_id:
        raise InvalidAttributeIdError(attribute_id, "Attribute ID cannot be empty")
    if len(attribute_id) > 64:
        raise InvalidAttributeIdError(attribute_id, "Attribute ID cannot exceed 64 characters")
    if not ATTRIBUTE_ID_PATTERN.match(attribute_id):
        raise InvalidAttributeIdError(
            attribute_id,
            "Attribute ID must start with a letter and contain only "
            "alphanumeric characters, underscores, or hyphens",
        )


class SensorStream:
    """Stream for sending sensor measurements to the server."""

    def __init__(
        self,
        socket: PhoenixSocket,
        topic: str,
        sensor_id: str,
        config: SensorConfig,
    ):
        """
        Creates a new sensor stream.

        Args:
            socket: The Phoenix socket.
            topic: The channel topic.
            sensor_id: The sensor ID.
            config: The sensor configuration.
        """
        self._socket = socket
        self._topic = topic
        self._sensor_id = sensor_id
        self._config = config
        self._joined = False
        self._batch_buffer: List[Measurement] = []
        self._batch_lock = asyncio.Lock()
        self._backpressure = BackpressureConfig()
        self._on_backpressure: Optional[Callable[[BackpressureConfig], None]] = None

        # Register backpressure handler
        self._socket.on(topic, "backpressure_config", self._handle_backpressure)

    @property
    def sensor_id(self) -> str:
        """Returns the sensor ID."""
        return self._sensor_id

    @property
    def is_active(self) -> bool:
        """Returns whether the stream is active."""
        return self._joined and self._socket.is_connected

    @property
    def backpressure_config(self) -> BackpressureConfig:
        """Returns the current backpressure configuration."""
        return self._backpressure

    def on_backpressure(self, handler: Callable[[BackpressureConfig], None]) -> None:
        """
        Sets the backpressure update handler.

        Args:
            handler: Callback function called when backpressure config updates.
        """
        self._on_backpressure = handler

    async def join(self, join_params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Joins the sensor channel.

        Args:
            join_params: Parameters for joining the channel.

        Returns:
            The join response from the server.
        """
        reply = await self._socket.send(self._topic, "phx_join", join_params)

        if reply.is_ok:
            self._joined = True
            logger.info(f"Joined sensor channel: {self._topic}")
            return reply.response
        else:
            raise Exception(f"Failed to join channel: {reply.response}")

    async def leave(self) -> None:
        """Leaves the sensor channel."""
        if not self._joined:
            return

        # Flush remaining measurements
        await self.flush_batch()

        await self._socket.send(self._topic, "phx_leave", {})
        self._joined = False
        logger.info(f"Left sensor channel: {self._topic}")

    async def send_measurement(
        self,
        attribute_id: str,
        payload: Union[Dict[str, Any], float, int, List[Any]],
        timestamp: Optional[int] = None,
    ) -> None:
        """
        Sends a single measurement to the server.

        Args:
            attribute_id: The attribute identifier.
            payload: The measurement payload.
            timestamp: Optional timestamp in milliseconds (uses current time if not provided).
        """
        if not self.is_active:
            raise DisconnectedError()

        validate_attribute_id(attribute_id)

        if timestamp is None:
            timestamp = int(datetime.utcnow().timestamp() * 1000)

        message = {
            "attribute_id": attribute_id,
            "payload": payload,
            "timestamp": timestamp,
        }

        await self._socket.send_no_reply(self._topic, "measurement", message)

    async def add_to_batch(
        self,
        attribute_id: str,
        payload: Union[Dict[str, Any], float, int, List[Any]],
        timestamp: Optional[int] = None,
    ) -> None:
        """
        Adds a measurement to the batch buffer.

        The batch will be sent when it reaches the configured size or when
        flush_batch() is called.

        Args:
            attribute_id: The attribute identifier.
            payload: The measurement payload.
            timestamp: Optional timestamp in milliseconds.
        """
        if not self.is_active:
            raise DisconnectedError()

        validate_attribute_id(attribute_id)

        if timestamp is None:
            timestamp = int(datetime.utcnow().timestamp() * 1000)

        measurement = Measurement(
            attribute_id=attribute_id,
            payload=payload,
            timestamp=timestamp,
        )

        async with self._batch_lock:
            self._batch_buffer.append(measurement)

            batch_size = self._backpressure.recommended_batch_size
            if len(self._batch_buffer) >= batch_size:
                await self._flush_batch_internal()

    async def flush_batch(self) -> None:
        """Flushes any pending measurements in the batch buffer."""
        async with self._batch_lock:
            await self._flush_batch_internal()

    async def _flush_batch_internal(self) -> None:
        """Internal method to flush the batch (must be called with lock held)."""
        if not self._batch_buffer:
            return

        measurements = [
            {
                "attribute_id": m.attribute_id,
                "payload": m.payload,
                "timestamp": m.timestamp,
            }
            for m in self._batch_buffer
        ]

        self._batch_buffer.clear()

        logger.debug(f"Flushing batch of {len(measurements)} measurements")
        await self._socket.send_no_reply(self._topic, "measurements_batch", measurements)

    async def update_attribute(
        self,
        action: str,
        attribute_id: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        """
        Updates the attribute registry.

        Args:
            action: The action to perform ("add", "remove", "update").
            attribute_id: The attribute identifier.
            metadata: Optional metadata for the attribute.
        """
        if not self.is_active:
            raise DisconnectedError()

        validate_attribute_id(attribute_id)

        payload = {
            "action": action,
            "attribute_id": attribute_id,
            "metadata": metadata or {},
        }

        await self._socket.send_no_reply(self._topic, "update_attributes", payload)

    def _handle_backpressure(self, payload: Dict[str, Any]) -> None:
        """Handles backpressure configuration from the server."""
        self._backpressure = BackpressureConfig.from_payload(payload)
        logger.debug(f"Backpressure config updated: {self._backpressure}")

        if self._on_backpressure:
            try:
                self._on_backpressure(self._backpressure)
            except Exception as e:
                logger.error(f"Error in backpressure handler: {e}")

    async def close(self) -> None:
        """Closes the sensor stream."""
        await self.leave()
