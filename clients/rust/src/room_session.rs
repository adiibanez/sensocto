//! Room session — channel for live sensor/member updates in a specific room.

use crate::channel::PhoenixChannel;
use crate::models::RoomSensor;
use tokio::sync::mpsc;
use tracing::{debug, warn};

/// Events received from a room channel.
#[derive(Debug, Clone)]
pub enum RoomEvent {
    /// Initial state after join.
    RoomState {
        room_id: String,
        sensors: Vec<RoomSensor>,
        member_count: u64,
    },
    /// A sensor was added to the room.
    SensorAdded {
        room_id: String,
        sensor: RoomSensor,
    },
    /// A sensor was removed from the room.
    SensorRemoved {
        room_id: String,
        sensor_id: String,
    },
    /// A member joined the room.
    MemberJoined {
        room_id: String,
        user_id: String,
    },
    /// A member left the room.
    MemberLeft {
        room_id: String,
        user_id: String,
    },
    /// The room was closed.
    RoomClosed {
        room_id: String,
    },
}

/// A room session for receiving live sensor/member updates.
pub struct RoomSession {
    channel: PhoenixChannel,
    room_id: String,
}

impl RoomSession {
    pub(crate) fn new(
        channel: PhoenixChannel,
        room_id: String,
    ) -> (Self, mpsc::Sender<RoomEvent>, mpsc::Receiver<RoomEvent>) {
        let (event_tx, event_rx) = mpsc::channel(100);
        let session = Self { channel, room_id };
        (session, event_tx, event_rx)
    }

    pub fn room_id(&self) -> &str {
        &self.room_id
    }

    /// Join the underlying channel. Call this after registering event handlers.
    pub(crate) async fn join(&self) -> crate::error::Result<()> {
        self.channel.join().await.map(|_| ())
    }

    pub async fn is_joined(&self) -> bool {
        self.channel.is_joined().await
    }

    /// Leave the room channel.
    pub async fn close(&self) -> crate::error::Result<()> {
        self.channel.leave().await
    }
}

/// Parse a room channel event and send it to the event channel.
/// Called synchronously from the socket read loop — uses try_send.
pub(crate) fn handle_room_event_sync(
    tx: &mpsc::Sender<RoomEvent>,
    room_id: &str,
    event: &str,
    payload: serde_json::Value,
) {
    debug!("room:{} event: {} payload={}", room_id, event, payload);

    let room_event = match event {
        "room_state" => {
            let sensors = match payload.get("sensors") {
                Some(v) => match serde_json::from_value::<Vec<RoomSensor>>(v.clone()) {
                    Ok(s) => {
                        debug!("room:{}: {} sensors", room_id, s.len());
                        s
                    }
                    Err(e) => {
                        warn!("room:{}: failed to deserialize sensors: {}", room_id, e);
                        vec![]
                    }
                },
                None => vec![],
            };
            let member_count = payload
                .get("member_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            Some(RoomEvent::RoomState {
                room_id: room_id.to_string(),
                sensors,
                member_count,
            })
        }
        "sensor_added" => {
            let sensor = payload
                .get("sensor")
                .and_then(|v| match serde_json::from_value::<RoomSensor>(v.clone()) {
                    Ok(s) => Some(s),
                    Err(e) => {
                        warn!("room:{}: failed to deserialize sensor_added: {}", room_id, e);
                        None
                    }
                });
            sensor.map(|s| RoomEvent::SensorAdded {
                room_id: room_id.to_string(),
                sensor: s,
            })
        }
        "sensor_removed" => {
            let sensor_id = payload
                .get("sensor_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            Some(RoomEvent::SensorRemoved {
                room_id: room_id.to_string(),
                sensor_id,
            })
        }
        "member_joined" => {
            let user_id = payload
                .get("user_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            Some(RoomEvent::MemberJoined {
                room_id: room_id.to_string(),
                user_id,
            })
        }
        "member_left" => {
            let user_id = payload
                .get("user_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            Some(RoomEvent::MemberLeft {
                room_id: room_id.to_string(),
                user_id,
            })
        }
        "room_closed" => Some(RoomEvent::RoomClosed {
            room_id: room_id.to_string(),
        }),
        _ => {
            debug!("room:{}: unknown event: {}", room_id, event);
            None
        }
    };

    if let Some(event) = room_event {
        match tx.try_send(event) {
            Ok(()) => debug!("room:{}: event sent to mpsc", room_id),
            Err(e) => warn!("room:{}: mpsc try_send FAILED: {}", room_id, e),
        }
    }
}
