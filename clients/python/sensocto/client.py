"""Main Sensocto client implementation."""

import logging
from typing import Any, Dict, Optional

from sensocto.call import CallSession
from sensocto.config import SensoctoConfig, SensorConfig
from sensocto.errors import DisconnectedError
from sensocto.models import ConnectionState
from sensocto.sensor import SensorStream
from sensocto.socket import PhoenixSocket

logger = logging.getLogger(__name__)


class SensoctoClient:
    """
    Main client for connecting to Sensocto.

    Example:
        >>> async with SensoctoClient(
        ...     server_url="https://your-server.com",
        ...     bearer_token="your-token"
        ... ) as client:
        ...     sensor = await client.register_sensor(
        ...         SensorConfig(sensor_name="My Sensor")
        ...     )
        ...     await sensor.send_measurement("temperature", {"value": 23.5})
    """

    def __init__(
        self,
        server_url: str,
        bearer_token: Optional[str] = None,
        connector_name: str = "Python Connector",
        connector_type: str = "python",
        connector_id: Optional[str] = None,
        auto_join_connector: bool = True,
        heartbeat_interval_seconds: float = 30.0,
        **kwargs: Any,
    ):
        """
        Creates a new Sensocto client.

        Args:
            server_url: The Sensocto server URL.
            bearer_token: Bearer token for authentication.
            connector_name: Human-readable name for this connector.
            connector_type: Type of connector.
            connector_id: Unique connector identifier (auto-generated if not provided).
            auto_join_connector: Whether to auto-join the connector channel.
            heartbeat_interval_seconds: Heartbeat interval in seconds.
            **kwargs: Additional configuration options.
        """
        self._config = SensoctoConfig(
            server_url=server_url,
            bearer_token=bearer_token,
            connector_name=connector_name,
            connector_type=connector_type,
            auto_join_connector=auto_join_connector,
            heartbeat_interval_seconds=heartbeat_interval_seconds,
            **{k: v for k, v in kwargs.items() if hasattr(SensoctoConfig, k)},
        )

        if connector_id:
            self._config.connector_id = connector_id

        self._socket: Optional[PhoenixSocket] = None
        self._state = ConnectionState.DISCONNECTED
        self._connector_joined = False

    @classmethod
    def from_config(cls, config: SensoctoConfig) -> "SensoctoClient":
        """
        Creates a client from a configuration object.

        Args:
            config: The configuration.

        Returns:
            A new SensoctoClient instance.
        """
        client = cls.__new__(cls)
        client._config = config
        client._socket = None
        client._state = ConnectionState.DISCONNECTED
        client._connector_joined = False
        return client

    @property
    def connection_state(self) -> ConnectionState:
        """Returns the current connection state."""
        return self._state

    @property
    def is_connected(self) -> bool:
        """Returns whether the client is connected."""
        return self._state == ConnectionState.CONNECTED

    @property
    def connector_id(self) -> str:
        """Returns the connector ID."""
        return self._config.connector_id

    @property
    def connector_name(self) -> str:
        """Returns the connector name."""
        return self._config.connector_name

    async def connect(self) -> None:
        """Connects to the Sensocto server."""
        self._config.validate()

        self._state = ConnectionState.CONNECTING
        logger.info(f"Connecting to {self._config.server_url}")

        try:
            self._socket = PhoenixSocket(
                url=self._config.websocket_url,
                heartbeat_interval=self._config.heartbeat_interval_seconds,
            )

            await self._socket.connect()

            self._state = ConnectionState.CONNECTED
            logger.info("Connected to Sensocto server")

            # Auto-join connector channel if configured
            if self._config.auto_join_connector:
                await self._join_connector_channel()

        except Exception:
            self._state = ConnectionState.ERROR
            raise

    async def disconnect(self) -> None:
        """Disconnects from the Sensocto server."""
        if self._socket:
            await self._socket.disconnect()
            self._socket = None

        self._state = ConnectionState.DISCONNECTED
        self._connector_joined = False
        logger.info("Disconnected from Sensocto server")

    async def register_sensor(self, config: SensorConfig) -> SensorStream:
        """
        Registers a sensor and returns a stream for sending measurements.

        Args:
            config: The sensor configuration.

        Returns:
            A SensorStream for sending measurements.
        """
        if not self.is_connected or not self._socket:
            raise DisconnectedError()

        sensor_id = config.sensor_id
        topic = f"sensocto:sensor:{sensor_id}"

        join_params = {
            "connector_id": self._config.connector_id,
            "connector_name": self._config.connector_name,
            "sensor_id": sensor_id,
            "sensor_name": config.sensor_name,
            "sensor_type": config.sensor_type,
            "attributes": config.attributes,
            "sampling_rate": config.sampling_rate_hz,
            "batch_size": config.batch_size,
            "bearer_token": self._config.bearer_token or "",
        }

        stream = SensorStream(
            socket=self._socket,
            topic=topic,
            sensor_id=sensor_id,
            config=config,
        )

        await stream.join(join_params)
        logger.info(f"Registered sensor: {sensor_id}")

        return stream

    async def join_call(
        self,
        room_id: str,
        user_id: str,
        user_info: Optional[Dict[str, Any]] = None,
    ) -> CallSession:
        """
        Joins a video/voice call in a room.

        Args:
            room_id: The room ID.
            user_id: The user ID.
            user_info: Optional additional user information.

        Returns:
            A CallSession for managing the call.
        """
        if not self.is_connected or not self._socket:
            raise DisconnectedError()

        topic = f"call:{room_id}"

        join_params = {
            "user_id": user_id,
            "user_info": user_info or {},
        }

        session = CallSession(
            socket=self._socket,
            topic=topic,
            room_id=room_id,
            user_id=user_id,
            ice_servers=[],
        )

        await session.join_channel(join_params)
        logger.info(f"Joined call channel: {room_id}")

        return session

    async def _join_connector_channel(self) -> None:
        """Joins the connector channel."""
        if not self._socket:
            return

        topic = f"sensocto:connector:{self._config.connector_id}"

        join_params = {
            "connector_id": self._config.connector_id,
            "connector_name": self._config.connector_name,
            "connector_type": self._config.connector_type,
            "features": self._config.features,
            "bearer_token": self._config.bearer_token or "",
        }

        reply = await self._socket.send(topic, "phx_join", join_params)

        if reply.is_ok:
            self._connector_joined = True
            logger.info("Joined connector channel")
        else:
            logger.warning(f"Failed to join connector channel: {reply.response}")

    async def __aenter__(self) -> "SensoctoClient":
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """Async context manager exit."""
        await self.disconnect()
