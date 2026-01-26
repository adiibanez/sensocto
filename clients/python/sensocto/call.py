"""Call session implementation."""

import asyncio
import logging
from typing import Any, Callable, Dict, List, Optional

from sensocto.errors import DisconnectedError, SensoctoError
from sensocto.models import (
    CallEvent,
    CallParticipant,
    CallEndedEvent,
    MediaEventReceived,
    ParticipantAudioChangedEvent,
    ParticipantJoinedEvent,
    ParticipantLeftEvent,
    ParticipantVideoChangedEvent,
    QualityChangedEvent,
)
from sensocto.socket import PhoenixSocket

logger = logging.getLogger(__name__)


class CallSession:
    """Session for video/voice communication."""

    def __init__(
        self,
        socket: PhoenixSocket,
        topic: str,
        room_id: str,
        user_id: str,
        ice_servers: List[Any],
    ):
        """
        Creates a new call session.

        Args:
            socket: The Phoenix socket.
            topic: The channel topic.
            room_id: The room ID.
            user_id: The user ID.
            ice_servers: ICE servers for WebRTC.
        """
        self._socket = socket
        self._topic = topic
        self._room_id = room_id
        self._user_id = user_id
        self._ice_servers = ice_servers
        self._joined = False
        self._in_call = False
        self._endpoint_id: Optional[str] = None
        self._event_handlers: List[Callable[[CallEvent], None]] = []

        # Register event handlers
        self._setup_event_handlers()

    @property
    def room_id(self) -> str:
        """Returns the room ID."""
        return self._room_id

    @property
    def user_id(self) -> str:
        """Returns the user ID."""
        return self._user_id

    @property
    def in_call(self) -> bool:
        """Returns whether the user is in the call."""
        return self._in_call

    @property
    def endpoint_id(self) -> Optional[str]:
        """Returns the endpoint ID."""
        return self._endpoint_id

    @property
    def ice_servers(self) -> List[Any]:
        """Returns the ICE servers."""
        return self._ice_servers

    def on_event(self, handler: Callable[[CallEvent], None]) -> None:
        """
        Registers an event handler.

        Args:
            handler: Callback function called when events are received.
        """
        self._event_handlers.append(handler)

    async def join_channel(self, join_params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Joins the call channel.

        Args:
            join_params: Parameters for joining the channel.

        Returns:
            The join response from the server.
        """
        reply = await self._socket.send(self._topic, "phx_join", join_params)

        if reply.is_ok:
            self._joined = True
            # Extract ICE servers from response
            if "ice_servers" in reply.response:
                self._ice_servers = reply.response["ice_servers"]
            logger.info(f"Joined call channel: {self._topic}")
            return reply.response
        else:
            raise SensoctoError(f"Failed to join channel: {reply.response}")

    async def leave_channel(self) -> None:
        """Leaves the call channel."""
        if not self._joined:
            return

        if self._in_call:
            await self.leave_call()

        await self._socket.send(self._topic, "phx_leave", {})
        self._joined = False
        logger.info(f"Left call channel: {self._topic}")

    async def join_call(self) -> Dict[str, Any]:
        """
        Joins the actual call.

        Returns:
            The join response with endpoint_id and participants.
        """
        if not self._joined:
            raise SensoctoError("Channel not joined")

        reply = await self._socket.send(self._topic, "join_call", {})

        if reply.is_ok:
            self._in_call = True
            self._endpoint_id = reply.response.get("endpoint_id")
            logger.info(f"Joined call with endpoint: {self._endpoint_id}")
            return reply.response
        else:
            raise SensoctoError(f"Failed to join call: {reply.response}")

    async def leave_call(self) -> None:
        """Leaves the call."""
        if not self._in_call:
            return

        await self._socket.send(self._topic, "leave_call", {})
        self._in_call = False
        self._endpoint_id = None
        logger.info("Left call")

    async def send_media_event(self, data: Any) -> None:
        """
        Sends a media event (SDP offer/answer, ICE candidate).

        Args:
            data: The media event data.
        """
        if not self._in_call:
            raise SensoctoError("Not in call")

        await self._socket.send_no_reply(self._topic, "media_event", {"data": data})

    async def toggle_audio(self, enabled: bool) -> None:
        """
        Toggles the local audio state.

        Args:
            enabled: Whether audio should be enabled.
        """
        if not self._in_call:
            raise SensoctoError("Not in call")

        await self._socket.send(self._topic, "toggle_audio", {"enabled": enabled})

    async def toggle_video(self, enabled: bool) -> None:
        """
        Toggles the local video state.

        Args:
            enabled: Whether video should be enabled.
        """
        if not self._in_call:
            raise SensoctoError("Not in call")

        await self._socket.send(self._topic, "toggle_video", {"enabled": enabled})

    async def set_quality(self, quality: str) -> None:
        """
        Sets the video quality.

        Args:
            quality: Quality level ("high", "medium", "low", or "auto").
        """
        if not self._in_call:
            raise SensoctoError("Not in call")

        await self._socket.send(self._topic, "set_quality", {"quality": quality})

    async def get_participants(self) -> Dict[str, CallParticipant]:
        """
        Gets the current participants.

        Returns:
            Dictionary mapping user_id to CallParticipant.
        """
        reply = await self._socket.send(self._topic, "get_participants", {})

        if reply.is_ok:
            participants = {}
            for user_id, data in reply.response.get("participants", {}).items():
                participants[user_id] = CallParticipant(
                    user_id=data.get("user_id", user_id),
                    endpoint_id=data.get("endpoint_id", ""),
                    user_info=data.get("user_info", {}),
                    joined_at=data.get("joined_at"),
                    audio_enabled=data.get("audio_enabled", False),
                    video_enabled=data.get("video_enabled", False),
                )
            return participants

        return {}

    def _setup_event_handlers(self) -> None:
        """Sets up event handlers for call events."""
        self._socket.on(self._topic, "participant_joined", self._on_participant_joined)
        self._socket.on(self._topic, "participant_left", self._on_participant_left)
        self._socket.on(self._topic, "media_event", self._on_media_event)
        self._socket.on(self._topic, "participant_audio_changed", self._on_audio_changed)
        self._socket.on(self._topic, "participant_video_changed", self._on_video_changed)
        self._socket.on(self._topic, "quality_changed", self._on_quality_changed)
        self._socket.on(self._topic, "call_ended", self._on_call_ended)

    def _dispatch_event(self, event: CallEvent) -> None:
        """Dispatches an event to all handlers."""
        for handler in self._event_handlers:
            try:
                handler(event)
            except Exception as e:
                logger.error(f"Error in event handler: {e}")

    def _on_participant_joined(self, payload: Dict[str, Any]) -> None:
        """Handles participant joined event."""
        participant = CallParticipant(
            user_id=payload.get("user_id", ""),
            endpoint_id=payload.get("endpoint_id", ""),
            user_info=payload.get("user_info", {}),
            joined_at=payload.get("joined_at"),
            audio_enabled=payload.get("audio_enabled", False),
            video_enabled=payload.get("video_enabled", False),
        )
        self._dispatch_event(ParticipantJoinedEvent(participant=participant))

    def _on_participant_left(self, payload: Dict[str, Any]) -> None:
        """Handles participant left event."""
        self._dispatch_event(ParticipantLeftEvent(
            user_id=payload.get("user_id", ""),
            crashed=payload.get("crashed", False),
        ))

    def _on_media_event(self, payload: Dict[str, Any]) -> None:
        """Handles media event."""
        self._dispatch_event(MediaEventReceived(data=payload.get("data")))

    def _on_audio_changed(self, payload: Dict[str, Any]) -> None:
        """Handles audio changed event."""
        self._dispatch_event(ParticipantAudioChangedEvent(
            user_id=payload.get("user_id", ""),
            enabled=payload.get("audio_enabled", False),
        ))

    def _on_video_changed(self, payload: Dict[str, Any]) -> None:
        """Handles video changed event."""
        self._dispatch_event(ParticipantVideoChangedEvent(
            user_id=payload.get("user_id", ""),
            enabled=payload.get("video_enabled", False),
        ))

    def _on_quality_changed(self, payload: Dict[str, Any]) -> None:
        """Handles quality changed event."""
        self._dispatch_event(QualityChangedEvent(quality=payload.get("quality", "")))

    def _on_call_ended(self, payload: Dict[str, Any]) -> None:
        """Handles call ended event."""
        self._in_call = False
        self._dispatch_event(CallEndedEvent())

    async def close(self) -> None:
        """Closes the call session."""
        await self.leave_channel()
