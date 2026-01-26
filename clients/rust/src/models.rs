//! Data models for the Sensocto client.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A single sensor measurement.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Measurement {
    /// The attribute identifier (e.g., "heart_rate", "temperature").
    pub attribute_id: String,

    /// The measurement payload.
    pub payload: serde_json::Value,

    /// Unix timestamp in milliseconds.
    pub timestamp: i64,
}

impl Measurement {
    /// Creates a new measurement with the current timestamp.
    pub fn new(attribute_id: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            attribute_id: attribute_id.into(),
            payload,
            timestamp: chrono::Utc::now().timestamp_millis(),
        }
    }

    /// Creates a new measurement with a specific timestamp.
    pub fn with_timestamp(
        attribute_id: impl Into<String>,
        payload: serde_json::Value,
        timestamp: i64,
    ) -> Self {
        Self {
            attribute_id: attribute_id.into(),
            payload,
            timestamp,
        }
    }
}

/// Connection state of the client.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    /// Not connected to the server.
    Disconnected,
    /// Currently connecting.
    Connecting,
    /// Connected and ready.
    Connected,
    /// Attempting to reconnect.
    Reconnecting,
    /// In an error state.
    Error,
}

/// System load level from the server.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum SystemLoadLevel {
    /// System running smoothly.
    #[default]
    Normal,
    /// Moderate load.
    Elevated,
    /// Heavy load.
    High,
    /// System overloaded.
    Critical,
}

/// Backpressure configuration from the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackpressureConfig {
    /// Current attention level.
    pub attention_level: AttentionLevel,

    /// Current system load level.
    #[serde(default)]
    pub system_load: SystemLoadLevel,

    /// Whether the client should pause sending data.
    /// True when system_load is critical AND attention is low/none.
    #[serde(default)]
    pub paused: bool,

    /// Recommended time window between batch sends (ms).
    pub recommended_batch_window: u32,

    /// Recommended batch size.
    pub recommended_batch_size: u32,

    /// Load multiplier applied to batch window.
    #[serde(default = "default_load_multiplier")]
    pub load_multiplier: f32,

    /// Server timestamp when config was generated.
    pub timestamp: i64,
}

fn default_load_multiplier() -> f32 {
    1.0
}

impl Default for BackpressureConfig {
    fn default() -> Self {
        Self {
            attention_level: AttentionLevel::None,
            system_load: SystemLoadLevel::Normal,
            paused: false,
            recommended_batch_window: 500,
            recommended_batch_size: 5,
            load_multiplier: 1.0,
            timestamp: 0,
        }
    }
}

impl BackpressureConfig {
    /// Returns whether sending should be paused.
    pub fn should_pause(&self) -> bool {
        self.paused
    }

    /// Returns the effective batch window considering load.
    pub fn effective_batch_window(&self) -> u32 {
        (self.recommended_batch_window as f32 * self.load_multiplier) as u32
    }
}

/// Server attention level for backpressure control.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum AttentionLevel {
    /// No active viewers - minimal updates needed.
    #[default]
    None,
    /// Low attention - slower updates acceptable.
    Low,
    /// Medium attention - normal updates.
    Medium,
    /// High attention - fast updates needed.
    High,
}

impl AttentionLevel {
    /// Returns the recommended batch window in milliseconds.
    pub fn recommended_batch_window(&self) -> u32 {
        match self {
            AttentionLevel::High => 100,
            AttentionLevel::Medium => 500,
            AttentionLevel::Low => 2000,
            AttentionLevel::None => 5000,
        }
    }

    /// Returns the recommended batch size.
    pub fn recommended_batch_size(&self) -> u32 {
        match self {
            AttentionLevel::High => 1,
            AttentionLevel::Medium => 5,
            AttentionLevel::Low => 10,
            AttentionLevel::None => 20,
        }
    }
}

/// Room membership role.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RoomRole {
    Owner,
    Admin,
    Member,
}

/// A room in Sensocto.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Room {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub join_code: Option<String>,
    pub is_public: bool,
    pub calls_enabled: bool,
    pub owner_id: String,
    #[serde(default)]
    pub configuration: HashMap<String, serde_json::Value>,
}

/// A user in Sensocto.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub email: Option<String>,
}

/// A call participant.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallParticipant {
    pub user_id: String,
    pub endpoint_id: String,
    #[serde(default)]
    pub user_info: HashMap<String, serde_json::Value>,
    pub joined_at: Option<String>,
    #[serde(default)]
    pub audio_enabled: bool,
    #[serde(default)]
    pub video_enabled: bool,
}

/// ICE server configuration for WebRTC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceServer {
    pub urls: Vec<String>,
    pub username: Option<String>,
    pub credential: Option<String>,
}

/// Channel state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelState {
    Closed,
    Joining,
    Joined,
    Leaving,
    Errored,
}

/// Phoenix protocol message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PhoenixMessage {
    pub topic: String,
    pub event: String,
    pub payload: serde_json::Value,
    #[serde(rename = "ref")]
    pub msg_ref: Option<String>,
}

/// Phoenix reply payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PhoenixReply {
    pub status: String,
    #[serde(default)]
    pub response: serde_json::Value,
}

/// Events that can be received from a sensor channel.
#[derive(Debug, Clone)]
pub enum SensorEvent {
    /// Backpressure configuration update.
    BackpressureConfig(BackpressureConfig),
    /// Generic event with payload.
    Other {
        event: String,
        payload: serde_json::Value,
    },
}

/// Events that can be received from a call channel.
#[derive(Debug, Clone)]
pub enum CallEvent {
    /// A participant joined the call.
    ParticipantJoined(CallParticipant),
    /// A participant left the call.
    ParticipantLeft { user_id: String, crashed: bool },
    /// Media event for WebRTC signaling.
    MediaEvent(serde_json::Value),
    /// Participant audio state changed.
    ParticipantAudioChanged { user_id: String, enabled: bool },
    /// Participant video state changed.
    ParticipantVideoChanged { user_id: String, enabled: bool },
    /// Call quality changed.
    QualityChanged(String),
    /// The call has ended.
    CallEnded,
}

/// Connection state change events for monitoring connection health.
#[derive(Debug, Clone)]
pub enum ConnectionEvent {
    /// Successfully connected to the server.
    Connected,
    /// Disconnected from the server (intentional or error).
    Disconnected { reason: String },
    /// Attempting to reconnect.
    Reconnecting { attempt: u32, max_attempts: u32 },
    /// Successfully reconnected.
    Reconnected { attempt: u32 },
    /// Reconnection failed after all attempts.
    ReconnectionFailed { attempts: u32, last_error: String },
    /// Connection error occurred.
    Error { message: String },
}
