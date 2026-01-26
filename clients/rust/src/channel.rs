//! Phoenix channel implementation.

use crate::config::SensorConfig;
use crate::error::{Result, SensoctoError};
use crate::models::{
    BackpressureConfig, CallEvent, CallParticipant, ChannelState, Measurement, SensorEvent,
};
use crate::socket::PhoenixSocket;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, info};

/// A Phoenix channel for real-time communication.
pub struct PhoenixChannel {
    socket: Arc<RwLock<PhoenixSocket>>,
    topic: String,
    join_params: serde_json::Value,
    state: Arc<RwLock<ChannelState>>,
}

impl PhoenixChannel {
    /// Creates a new channel.
    pub(crate) fn new(
        socket: Arc<RwLock<PhoenixSocket>>,
        topic: String,
        join_params: serde_json::Value,
    ) -> Self {
        Self {
            socket,
            topic,
            join_params,
            state: Arc::new(RwLock::new(ChannelState::Closed)),
        }
    }

    /// Joins the channel.
    pub async fn join(&self) -> Result<serde_json::Value> {
        *self.state.write().await = ChannelState::Joining;

        let socket = self.socket.read().await;
        let reply = socket
            .send(&self.topic, "phx_join", self.join_params.clone())
            .await?;

        if reply.status == "ok" {
            *self.state.write().await = ChannelState::Joined;
            info!("Joined channel: {}", self.topic);
            Ok(reply.response)
        } else {
            *self.state.write().await = ChannelState::Errored;
            Err(SensoctoError::ChannelJoinFailed {
                topic: self.topic.clone(),
                reason: reply.response.to_string(),
            })
        }
    }

    /// Leaves the channel.
    pub async fn leave(&self) -> Result<()> {
        if *self.state.read().await != ChannelState::Joined {
            return Ok(());
        }

        *self.state.write().await = ChannelState::Leaving;

        let socket = self.socket.read().await;
        let _ = socket
            .send(&self.topic, "phx_leave", serde_json::json!({}))
            .await;

        *self.state.write().await = ChannelState::Closed;
        info!("Left channel: {}", self.topic);
        Ok(())
    }

    /// Pushes a message to the channel.
    pub async fn push(&self, event: &str, payload: serde_json::Value) -> Result<serde_json::Value> {
        if *self.state.read().await != ChannelState::Joined {
            return Err(SensoctoError::ChannelNotJoined(self.topic.clone()));
        }

        let socket = self.socket.read().await;
        let reply = socket.send(&self.topic, event, payload).await?;

        if reply.status == "ok" {
            Ok(reply.response)
        } else {
            Err(SensoctoError::ServerError(reply.response.to_string()))
        }
    }

    /// Pushes a message without waiting for a reply.
    pub async fn push_no_reply(&self, event: &str, payload: serde_json::Value) -> Result<()> {
        if *self.state.read().await != ChannelState::Joined {
            return Err(SensoctoError::ChannelNotJoined(self.topic.clone()));
        }

        let socket = self.socket.read().await;
        socket.send_no_reply(&self.topic, event, payload).await
    }

    /// Returns the channel topic.
    pub fn topic(&self) -> &str {
        &self.topic
    }

    /// Returns whether the channel is joined.
    pub async fn is_joined(&self) -> bool {
        *self.state.read().await == ChannelState::Joined
    }
}

/// A sensor stream for sending measurements.
pub struct SensorStream {
    channel: PhoenixChannel,
    sensor_id: String,
    config: SensorConfig,
    batch_buffer: Arc<RwLock<Vec<Measurement>>>,
    backpressure: Arc<RwLock<BackpressureConfig>>,
    event_tx: mpsc::Sender<SensorEvent>,
}

impl SensorStream {
    /// Creates a new sensor stream.
    pub(crate) fn new(
        channel: PhoenixChannel,
        sensor_id: String,
        config: SensorConfig,
    ) -> (Self, mpsc::Receiver<SensorEvent>) {
        let (event_tx, event_rx) = mpsc::channel(100);

        let stream = Self {
            channel,
            sensor_id,
            config,
            batch_buffer: Arc::new(RwLock::new(Vec::new())),
            backpressure: Arc::new(RwLock::new(BackpressureConfig::default())),
            event_tx,
        };

        (stream, event_rx)
    }

    /// Returns the sensor ID.
    pub fn sensor_id(&self) -> &str {
        &self.sensor_id
    }

    /// Returns whether the stream is active.
    pub async fn is_active(&self) -> bool {
        self.channel.is_joined().await
    }

    /// Sends a single measurement.
    /// Returns Ok(true) if sent, Ok(false) if skipped due to backpressure pause.
    pub async fn send_measurement(
        &self,
        attribute_id: &str,
        payload: serde_json::Value,
    ) -> Result<bool> {
        self.send_measurement_with_timestamp(
            attribute_id,
            payload,
            chrono::Utc::now().timestamp_millis(),
        )
        .await
    }

    /// Sends a single measurement with a specific timestamp.
    /// Returns Ok(true) if sent, Ok(false) if skipped due to backpressure pause.
    pub async fn send_measurement_with_timestamp(
        &self,
        attribute_id: &str,
        payload: serde_json::Value,
        timestamp: i64,
    ) -> Result<bool> {
        // Skip sending when server signals pause (critical load + low attention)
        if self.backpressure.read().await.paused {
            return Ok(false);
        }

        validate_attribute_id(attribute_id)?;

        let message = serde_json::json!({
            "attribute_id": attribute_id,
            "payload": payload,
            "timestamp": timestamp
        });

        self.channel.push_no_reply("measurement", message).await?;
        Ok(true)
    }

    /// Adds a measurement to the batch buffer.
    pub async fn add_to_batch(&self, attribute_id: &str, payload: serde_json::Value) {
        self.add_to_batch_with_timestamp(
            attribute_id,
            payload,
            chrono::Utc::now().timestamp_millis(),
        )
        .await
    }

    /// Adds a measurement to the batch buffer with a specific timestamp.
    /// When server signals pause, measurements are still buffered but not sent.
    pub async fn add_to_batch_with_timestamp(
        &self,
        attribute_id: &str,
        payload: serde_json::Value,
        timestamp: i64,
    ) {
        let measurement = Measurement {
            attribute_id: attribute_id.to_string(),
            payload,
            timestamp,
        };

        let mut buffer = self.batch_buffer.write().await;
        buffer.push(measurement);

        let bp = self.backpressure.read().await;
        let batch_size = bp.recommended_batch_size as usize;
        let is_paused = bp.paused;
        drop(bp);

        // Skip auto-flush when paused (measurements buffer but don't send)
        if is_paused {
            return;
        }

        if buffer.len() >= batch_size {
            drop(buffer);
            let _ = self.flush_batch().await;
        }
    }

    /// Flushes the batch buffer.
    /// When server signals pause, flush is skipped and measurements remain buffered.
    /// Returns Ok(true) if flushed, Ok(false) if skipped due to pause or empty buffer.
    pub async fn flush_batch(&self) -> Result<bool> {
        self.flush_batch_internal(false).await
    }

    /// Force flushes the batch buffer even when paused (used during close).
    pub async fn force_flush_batch(&self) -> Result<bool> {
        self.flush_batch_internal(true).await
    }

    async fn flush_batch_internal(&self, force: bool) -> Result<bool> {
        let mut buffer = self.batch_buffer.write().await;
        if buffer.is_empty() {
            return Ok(false);
        }

        // Skip flush when paused unless forced
        if self.backpressure.read().await.paused && !force {
            return Ok(false);
        }

        let measurements: Vec<serde_json::Value> = buffer
            .drain(..)
            .map(|m| {
                serde_json::json!({
                    "attribute_id": m.attribute_id,
                    "payload": m.payload,
                    "timestamp": m.timestamp
                })
            })
            .collect();

        drop(buffer);

        debug!("Flushing batch of {} measurements", measurements.len());
        self.channel
            .push_no_reply("measurements_batch", serde_json::Value::Array(measurements))
            .await?;
        Ok(true)
    }

    /// Updates the attribute registry.
    pub async fn update_attribute(
        &self,
        action: &str,
        attribute_id: &str,
        metadata: Option<HashMap<String, serde_json::Value>>,
    ) -> Result<()> {
        validate_attribute_id(attribute_id)?;

        let payload = serde_json::json!({
            "action": action,
            "attribute_id": attribute_id,
            "metadata": metadata.unwrap_or_default()
        });

        self.channel.push_no_reply("update_attributes", payload).await
    }

    /// Returns the current backpressure configuration.
    pub async fn backpressure_config(&self) -> BackpressureConfig {
        self.backpressure.read().await.clone()
    }

    /// Returns whether sending is paused due to server backpressure.
    /// When paused, measurements should not be sent to avoid overwhelming the server.
    pub async fn is_paused(&self) -> bool {
        self.backpressure.read().await.paused
    }

    /// Updates the backpressure configuration.
    pub(crate) async fn set_backpressure_config(&self, config: BackpressureConfig) {
        *self.backpressure.write().await = config.clone();
        let _ = self.event_tx.send(SensorEvent::BackpressureConfig(config)).await;
    }

    /// Closes the sensor stream.
    pub async fn close(&self) -> Result<()> {
        // Force flush remaining measurements even if paused
        let _ = self.force_flush_batch().await;
        self.channel.leave().await
    }
}

/// A call session for video/voice communication.
pub struct CallSession {
    channel: PhoenixChannel,
    room_id: String,
    user_id: String,
    ice_servers: Vec<serde_json::Value>,
    in_call: Arc<RwLock<bool>>,
    endpoint_id: Arc<RwLock<Option<String>>>,
    event_tx: mpsc::Sender<CallEvent>,
}

impl CallSession {
    /// Creates a new call session.
    pub(crate) fn new(
        channel: PhoenixChannel,
        room_id: String,
        user_id: String,
        ice_servers: Vec<serde_json::Value>,
    ) -> (Self, mpsc::Receiver<CallEvent>) {
        let (event_tx, event_rx) = mpsc::channel(100);

        let session = Self {
            channel,
            room_id,
            user_id,
            ice_servers,
            in_call: Arc::new(RwLock::new(false)),
            endpoint_id: Arc::new(RwLock::new(None)),
            event_tx,
        };

        (session, event_rx)
    }

    /// Returns the room ID.
    pub fn room_id(&self) -> &str {
        &self.room_id
    }

    /// Returns the user ID.
    pub fn user_id(&self) -> &str {
        &self.user_id
    }

    /// Returns whether the user is in the call.
    pub async fn in_call(&self) -> bool {
        *self.in_call.read().await
    }

    /// Returns the endpoint ID.
    pub async fn endpoint_id(&self) -> Option<String> {
        self.endpoint_id.read().await.clone()
    }

    /// Returns the ICE servers.
    pub fn ice_servers(&self) -> &[serde_json::Value] {
        &self.ice_servers
    }

    /// Joins the call.
    pub async fn join_call(&self) -> Result<serde_json::Value> {
        let response = self.channel.push("join_call", serde_json::json!({})).await?;

        *self.in_call.write().await = true;

        if let Some(endpoint_id) = response.get("endpoint_id").and_then(|v| v.as_str()) {
            *self.endpoint_id.write().await = Some(endpoint_id.to_string());
        }

        Ok(response)
    }

    /// Leaves the call.
    pub async fn leave_call(&self) -> Result<()> {
        if !*self.in_call.read().await {
            return Ok(());
        }

        self.channel.push("leave_call", serde_json::json!({})).await?;
        *self.in_call.write().await = false;
        *self.endpoint_id.write().await = None;

        Ok(())
    }

    /// Sends a media event (SDP offer/answer, ICE candidate).
    pub async fn send_media_event(&self, data: serde_json::Value) -> Result<()> {
        if !*self.in_call.read().await {
            return Err(SensoctoError::Other("Not in call".into()));
        }

        self.channel
            .push_no_reply("media_event", serde_json::json!({ "data": data }))
            .await
    }

    /// Toggles audio.
    pub async fn toggle_audio(&self, enabled: bool) -> Result<()> {
        if !*self.in_call.read().await {
            return Err(SensoctoError::Other("Not in call".into()));
        }

        self.channel
            .push("toggle_audio", serde_json::json!({ "enabled": enabled }))
            .await?;
        Ok(())
    }

    /// Toggles video.
    pub async fn toggle_video(&self, enabled: bool) -> Result<()> {
        if !*self.in_call.read().await {
            return Err(SensoctoError::Other("Not in call".into()));
        }

        self.channel
            .push("toggle_video", serde_json::json!({ "enabled": enabled }))
            .await?;
        Ok(())
    }

    /// Sets the video quality.
    pub async fn set_quality(&self, quality: &str) -> Result<()> {
        if !*self.in_call.read().await {
            return Err(SensoctoError::Other("Not in call".into()));
        }

        self.channel
            .push("set_quality", serde_json::json!({ "quality": quality }))
            .await?;
        Ok(())
    }

    /// Gets the current participants.
    pub async fn get_participants(&self) -> Result<HashMap<String, CallParticipant>> {
        let response = self.channel.push("get_participants", serde_json::json!({})).await?;

        if let Some(participants) = response.get("participants") {
            Ok(serde_json::from_value(participants.clone()).unwrap_or_default())
        } else {
            Ok(HashMap::new())
        }
    }

    /// Handles incoming events.
    pub(crate) async fn handle_event(&self, event: &str, payload: serde_json::Value) {
        let call_event = match event {
            "participant_joined" => {
                serde_json::from_value::<CallParticipant>(payload)
                    .ok()
                    .map(CallEvent::ParticipantJoined)
            }
            "participant_left" => {
                let user_id = payload.get("user_id").and_then(|v| v.as_str()).unwrap_or_default();
                let crashed = payload.get("crashed").and_then(|v| v.as_bool()).unwrap_or(false);
                Some(CallEvent::ParticipantLeft {
                    user_id: user_id.to_string(),
                    crashed,
                })
            }
            "media_event" => {
                payload.get("data").cloned().map(CallEvent::MediaEvent)
            }
            "participant_audio_changed" => {
                let user_id = payload.get("user_id").and_then(|v| v.as_str()).unwrap_or_default();
                let enabled = payload.get("audio_enabled").and_then(|v| v.as_bool()).unwrap_or(false);
                Some(CallEvent::ParticipantAudioChanged {
                    user_id: user_id.to_string(),
                    enabled,
                })
            }
            "participant_video_changed" => {
                let user_id = payload.get("user_id").and_then(|v| v.as_str()).unwrap_or_default();
                let enabled = payload.get("video_enabled").and_then(|v| v.as_bool()).unwrap_or(false);
                Some(CallEvent::ParticipantVideoChanged {
                    user_id: user_id.to_string(),
                    enabled,
                })
            }
            "quality_changed" => {
                payload.get("quality").and_then(|v| v.as_str()).map(|q| CallEvent::QualityChanged(q.to_string()))
            }
            "call_ended" => Some(CallEvent::CallEnded),
            _ => None,
        };

        if let Some(event) = call_event {
            let _ = self.event_tx.send(event).await;
        }
    }
}

/// Validates an attribute ID.
fn validate_attribute_id(id: &str) -> Result<()> {
    if id.is_empty() || id.len() > 64 {
        return Err(SensoctoError::InvalidAttributeId(
            "Attribute ID must be 1-64 characters".into(),
        ));
    }

    let first_char = id.chars().next().unwrap();
    if !first_char.is_ascii_alphabetic() {
        return Err(SensoctoError::InvalidAttributeId(
            "Attribute ID must start with a letter".into(),
        ));
    }

    if !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
        return Err(SensoctoError::InvalidAttributeId(
            "Attribute ID must contain only alphanumeric characters, underscores, or hyphens".into(),
        ));
    }

    Ok(())
}
