"""Phoenix WebSocket implementation for Python."""

import asyncio
import json
import logging
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

import websockets
from websockets.client import WebSocketClientProtocol

from sensocto.errors import ConnectionError, TimeoutError

logger = logging.getLogger(__name__)


@dataclass
class PhoenixMessage:
    """Phoenix protocol message."""

    topic: str
    event: str
    payload: Any
    ref: Optional[str] = None

    def to_json(self) -> str:
        """Serializes the message to JSON."""
        return json.dumps(
            {
                "topic": self.topic,
                "event": self.event,
                "payload": self.payload,
                "ref": self.ref,
            }
        )

    @classmethod
    def from_json(cls, data: str) -> "PhoenixMessage":
        """Deserializes a message from JSON."""
        obj = json.loads(data)
        return cls(
            topic=obj.get("topic", ""),
            event=obj.get("event", ""),
            payload=obj.get("payload", {}),
            ref=obj.get("ref"),
        )


@dataclass
class PhoenixReply:
    """Response from a Phoenix channel operation."""

    status: str
    response: Any

    @property
    def is_ok(self) -> bool:
        """Returns True if the reply indicates success."""
        return self.status == "ok"

    @property
    def is_error(self) -> bool:
        """Returns True if the reply indicates an error."""
        return not self.is_ok


EventHandler = Callable[[Dict[str, Any]], None]


class PhoenixSocket:
    """Phoenix WebSocket client."""

    def __init__(self, url: str, heartbeat_interval: float = 30.0):
        """
        Creates a new Phoenix socket.

        Args:
            url: WebSocket URL (e.g., wss://example.com/socket/websocket)
            heartbeat_interval: Heartbeat interval in seconds.
        """
        self._url = url
        self._heartbeat_interval = heartbeat_interval
        self._ws: Optional[WebSocketClientProtocol] = None
        self._ref_counter = 0
        self._pending_replies: Dict[str, asyncio.Future[PhoenixReply]] = {}
        self._event_handlers: Dict[str, List[EventHandler]] = {}
        self._connected = False
        self._receive_task: Optional[asyncio.Task] = None
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()

    @property
    def is_connected(self) -> bool:
        """Returns whether the socket is connected."""
        return self._connected and self._ws is not None

    async def connect(self) -> None:
        """Connects to the Phoenix server."""
        logger.info(f"Connecting to {self._url}")

        try:
            self._ws = await websockets.connect(self._url)
            self._connected = True

            # Start background tasks
            self._receive_task = asyncio.create_task(self._receive_loop())
            self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())

            logger.info("Connected to Phoenix server")
        except Exception as e:
            raise ConnectionError(f"Failed to connect to {self._url}", e)

    async def disconnect(self) -> None:
        """Disconnects from the Phoenix server."""
        self._connected = False

        # Cancel background tasks
        if self._receive_task:
            self._receive_task.cancel()
            try:
                await self._receive_task
            except asyncio.CancelledError:
                pass

        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

        # Close WebSocket
        if self._ws:
            await self._ws.close()
            self._ws = None

        logger.info("Disconnected from Phoenix server")

    async def send(
        self,
        topic: str,
        event: str,
        payload: Any,
        timeout: float = 10.0,
    ) -> PhoenixReply:
        """
        Sends a message and waits for a reply.

        Args:
            topic: The channel topic.
            event: The event name.
            payload: The message payload.
            timeout: Timeout in seconds.

        Returns:
            The reply from the server.
        """
        ref = self._generate_ref()

        message = PhoenixMessage(
            topic=topic,
            event=event,
            payload=payload,
            ref=ref,
        )

        # Create future for reply
        future: asyncio.Future[PhoenixReply] = asyncio.get_event_loop().create_future()
        self._pending_replies[ref] = future

        try:
            # Send message
            await self._send_raw(message.to_json())

            # Wait for reply with timeout
            try:
                reply = await asyncio.wait_for(future, timeout=timeout)
                return reply
            except asyncio.TimeoutError:
                raise TimeoutError(int(timeout * 1000))
        finally:
            self._pending_replies.pop(ref, None)

    async def send_no_reply(self, topic: str, event: str, payload: Any) -> None:
        """
        Sends a message without waiting for a reply.

        Args:
            topic: The channel topic.
            event: The event name.
            payload: The message payload.
        """
        ref = self._generate_ref()

        message = PhoenixMessage(
            topic=topic,
            event=event,
            payload=payload,
            ref=ref,
        )

        await self._send_raw(message.to_json())

    def on(self, topic: str, event: str, handler: EventHandler) -> None:
        """
        Registers an event handler.

        Args:
            topic: The channel topic.
            event: The event name.
            handler: The callback function.
        """
        key = f"{topic}:{event}"
        if key not in self._event_handlers:
            self._event_handlers[key] = []
        self._event_handlers[key].append(handler)

    def off(self, topic: str, event: str, handler: Optional[EventHandler] = None) -> None:
        """
        Removes an event handler.

        Args:
            topic: The channel topic.
            event: The event name.
            handler: The specific handler to remove, or None to remove all.
        """
        key = f"{topic}:{event}"
        if handler is None:
            self._event_handlers.pop(key, None)
        elif key in self._event_handlers:
            try:
                self._event_handlers[key].remove(handler)
            except ValueError:
                pass

    async def _send_raw(self, data: str) -> None:
        """Sends raw data through the WebSocket."""
        if not self._ws:
            raise ConnectionError("Not connected")

        async with self._lock:
            await self._ws.send(data)
            logger.debug(f"Sent: {data}")

    def _generate_ref(self) -> str:
        """Generates a unique message reference."""
        self._ref_counter += 1
        return str(self._ref_counter)

    async def _receive_loop(self) -> None:
        """Background task for receiving messages."""
        if not self._ws:
            return

        try:
            async for data in self._ws:
                if not self._connected:
                    break

                try:
                    message = PhoenixMessage.from_json(data)
                    logger.debug(f"Received: {data}")
                    await self._handle_message(message)
                except json.JSONDecodeError as e:
                    logger.warning(f"Failed to parse message: {e}")
        except websockets.ConnectionClosed:
            logger.info("WebSocket connection closed")
            self._connected = False
        except Exception as e:
            logger.error(f"Error in receive loop: {e}")
            self._connected = False

    async def _handle_message(self, message: PhoenixMessage) -> None:
        """Handles an incoming message."""
        # Handle reply
        if message.event == "phx_reply" and message.ref:
            future = self._pending_replies.get(message.ref)
            if future and not future.done():
                payload = message.payload or {}
                reply = PhoenixReply(
                    status=payload.get("status", "error"),
                    response=payload.get("response", {}),
                )
                future.set_result(reply)
            return

        # Dispatch to event handlers
        key = f"{message.topic}:{message.event}"
        handlers = self._event_handlers.get(key, [])
        for handler in handlers:
            try:
                handler(message.payload)
            except Exception as e:
                logger.error(f"Error in event handler for {key}: {e}")

    async def _heartbeat_loop(self) -> None:
        """Background task for sending heartbeats."""
        while self._connected:
            await asyncio.sleep(self._heartbeat_interval)

            if self._connected:
                try:
                    ref = self._generate_ref()
                    message = PhoenixMessage(
                        topic="phoenix",
                        event="heartbeat",
                        payload={},
                        ref=ref,
                    )
                    await self._send_raw(message.to_json())
                except Exception as e:
                    logger.warning(f"Failed to send heartbeat: {e}")
