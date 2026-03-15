//! Lobby session — read-only channel for the room list with live updates.

use crate::channel::PhoenixChannel;
use crate::models::Room;
use tokio::sync::mpsc;
use tracing::{debug, warn};

/// Events received from the lobby channel.
#[derive(Debug, Clone)]
pub enum LobbyEvent {
    /// Initial room lists after join.
    LobbyState {
        my_rooms: Vec<Room>,
        public_rooms: Vec<Room>,
    },
    /// A room appeared (created or user was invited).
    RoomAdded(Room),
    /// A room disappeared (deleted or user was removed).
    RoomRemoved { room_id: String },
    /// Room metadata changed.
    RoomUpdated(Room),
    /// Membership changed in one of user's rooms.
    MembershipChanged {
        room_id: String,
        action: String,
        user_id: String,
    },
}

/// Read-only lobby session. Receives room list updates via the lobby channel.
pub struct LobbySession {
    channel: PhoenixChannel,
    user_id: String,
}

impl LobbySession {
    pub(crate) fn new(
        channel: PhoenixChannel,
        user_id: String,
    ) -> (Self, mpsc::Sender<LobbyEvent>, mpsc::Receiver<LobbyEvent>) {
        let (event_tx, event_rx) = mpsc::channel(100);
        let session = Self {
            channel,
            user_id,
        };
        (session, event_tx, event_rx)
    }

    pub fn user_id(&self) -> &str {
        &self.user_id
    }

    /// Join the underlying channel. Call this after registering event handlers.
    pub(crate) async fn join(&self) -> crate::error::Result<()> {
        self.channel.join().await.map(|_| ())
    }

    pub async fn is_joined(&self) -> bool {
        self.channel.is_joined().await
    }

    /// Leave the lobby channel.
    pub async fn close(&self) -> crate::error::Result<()> {
        self.channel.leave().await
    }

}

/// Parse a lobby channel event and send it to the event channel.
/// NOTE: This is called synchronously from the socket read loop, so we use try_send.
pub(crate) fn handle_lobby_event_sync(
    tx: &mpsc::Sender<LobbyEvent>,
    event: &str,
    payload: serde_json::Value,
) {
    debug!("lobby event received: {} payload={}", event, payload);

    let lobby_event = match event {
        "lobby_state" => {
            let my_rooms = match payload.get("my_rooms") {
                Some(v) => match serde_json::from_value::<Vec<Room>>(v.clone()) {
                    Ok(rooms) => {
                        debug!("lobby: deserialized {} my_rooms", rooms.len());
                        rooms
                    }
                    Err(e) => {
                        warn!("lobby: failed to deserialize my_rooms: {} — raw: {}", e, v);
                        vec![]
                    }
                },
                None => {
                    warn!("lobby: no my_rooms field in payload");
                    vec![]
                }
            };
            let public_rooms = match payload.get("public_rooms") {
                Some(v) => match serde_json::from_value::<Vec<Room>>(v.clone()) {
                    Ok(rooms) => {
                        debug!("lobby: deserialized {} public_rooms", rooms.len());
                        rooms
                    }
                    Err(e) => {
                        warn!("lobby: failed to deserialize public_rooms: {} — raw: {}", e, v);
                        vec![]
                    }
                },
                None => {
                    warn!("lobby: no public_rooms field in payload");
                    vec![]
                }
            };
            Some(LobbyEvent::LobbyState {
                my_rooms,
                public_rooms,
            })
        }
        "room_added" => match serde_json::from_value::<Room>(payload.clone()) {
            Ok(room) => Some(LobbyEvent::RoomAdded(room)),
            Err(e) => {
                warn!("lobby: failed to deserialize room_added: {} — raw: {}", e, payload);
                None
            }
        },
        "room_removed" => {
            let room_id = payload
                .get("room_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            Some(LobbyEvent::RoomRemoved { room_id })
        }
        "room_updated" => match serde_json::from_value::<Room>(payload.clone()) {
            Ok(room) => Some(LobbyEvent::RoomUpdated(room)),
            Err(e) => {
                warn!("lobby: failed to deserialize room_updated: {} — raw: {}", e, payload);
                None
            }
        },
        "membership_changed" => {
            let room_id = payload
                .get("room_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let action = payload
                .get("action")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let user_id = payload
                .get("user_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            Some(LobbyEvent::MembershipChanged {
                room_id,
                action,
                user_id,
            })
        }
        _ => {
            debug!("lobby: unknown event: {}", event);
            None
        }
    };

    if let Some(event) = lobby_event {
        match tx.try_send(event) {
            Ok(()) => debug!("lobby: event sent to mpsc"),
            Err(e) => warn!("lobby: mpsc try_send FAILED: {}", e),
        }
    }
}
