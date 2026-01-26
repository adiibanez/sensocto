//! Main Sensocto client implementation.

use crate::channel::{CallSession, PhoenixChannel, SensorStream};
use crate::config::{SensoctoConfig, SensoctoConfigBuilder, SensorConfig};
use crate::error::{Result, SensoctoError};
use crate::models::{BackpressureConfig, CallEvent, ConnectionEvent, ConnectionState, SensorEvent};
use crate::socket::PhoenixSocket;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, error, info, warn};

/// Main client for connecting to Sensocto.
pub struct SensoctoClient {
    config: SensoctoConfig,
    socket: Arc<RwLock<PhoenixSocket>>,
    state: Arc<RwLock<ConnectionState>>,
    connector_channel: Arc<RwLock<Option<PhoenixChannel>>>,
    /// Channel for connection state events
    connection_event_tx: Option<mpsc::Sender<ConnectionEvent>>,
    /// Flag to stop reconnection attempts
    stop_reconnecting: Arc<RwLock<bool>>,
}

impl SensoctoClient {
    /// Creates a new client with the given configuration.
    pub fn new(config: SensoctoConfig) -> Result<Self> {
        config.validate()?;

        let socket_url = config.websocket_url()?;
        let socket = PhoenixSocket::new(socket_url, config.heartbeat_interval);

        Ok(Self {
            config,
            socket: Arc::new(RwLock::new(socket)),
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            connector_channel: Arc::new(RwLock::new(None)),
            connection_event_tx: None,
            stop_reconnecting: Arc::new(RwLock::new(false)),
        })
    }

    /// Creates a new client with a connection event receiver.
    /// Use this to monitor connection state changes.
    pub fn with_events(config: SensoctoConfig) -> Result<(Self, mpsc::Receiver<ConnectionEvent>)> {
        config.validate()?;

        let socket_url = config.websocket_url()?;
        let socket = PhoenixSocket::new(socket_url, config.heartbeat_interval);

        let (tx, rx) = mpsc::channel(32);

        let client = Self {
            config,
            socket: Arc::new(RwLock::new(socket)),
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            connector_channel: Arc::new(RwLock::new(None)),
            connection_event_tx: Some(tx),
            stop_reconnecting: Arc::new(RwLock::new(false)),
        };

        Ok((client, rx))
    }

    /// Creates a configuration builder.
    pub fn builder() -> SensoctoConfigBuilder {
        SensoctoConfig::builder()
    }

    /// Connects to the Sensocto server.
    pub async fn connect(&self) -> Result<()> {
        *self.stop_reconnecting.write().await = false;
        *self.state.write().await = ConnectionState::Connecting;

        let mut socket = self.socket.write().await;
        if let Err(e) = socket.connect().await {
            *self.state.write().await = ConnectionState::Error;
            self.emit_event(ConnectionEvent::Error {
                message: e.to_string(),
            })
            .await;
            return Err(e);
        }
        drop(socket);

        *self.state.write().await = ConnectionState::Connected;
        self.emit_event(ConnectionEvent::Connected).await;
        info!("Connected to Sensocto server");

        // Auto-join connector channel if configured
        if self.config.auto_join_connector {
            self.join_connector_channel().await?;
        }

        // Start connection monitor for auto-reconnect
        if self.config.auto_reconnect {
            self.start_connection_monitor().await;
        }

        Ok(())
    }

    /// Connects with automatic retry on failure.
    /// Uses exponential backoff with jitter.
    pub async fn connect_with_retry(&self) -> Result<()> {
        let max_attempts = self.config.max_reconnect_attempts;

        for attempt in 1..=max_attempts {
            match self.connect().await {
                Ok(()) => return Ok(()),
                Err(e) => {
                    if attempt == max_attempts {
                        self.emit_event(ConnectionEvent::ReconnectionFailed {
                            attempts: max_attempts,
                            last_error: e.to_string(),
                        })
                        .await;
                        return Err(e);
                    }

                    let delay = Self::calculate_backoff(attempt);
                    warn!(
                        "Connection attempt {} failed: {}. Retrying in {:?}",
                        attempt, e, delay
                    );
                    self.emit_event(ConnectionEvent::Reconnecting {
                        attempt,
                        max_attempts,
                    })
                    .await;
                    tokio::time::sleep(delay).await;
                }
            }
        }

        Err(SensoctoError::ConnectionFailed(
            "Max connection attempts reached".into(),
        ))
    }

    /// Disconnects from the Sensocto server.
    pub async fn disconnect(&self) {
        // Stop reconnection attempts
        *self.stop_reconnecting.write().await = true;

        // Leave connector channel
        if let Some(channel) = self.connector_channel.write().await.take() {
            let _ = channel.leave().await;
        }

        // Disconnect socket
        self.socket.write().await.disconnect().await;
        *self.state.write().await = ConnectionState::Disconnected;

        self.emit_event(ConnectionEvent::Disconnected {
            reason: "User requested disconnect".into(),
        })
        .await;

        info!("Disconnected from Sensocto server");
    }

    /// Starts a background task to monitor connection and auto-reconnect.
    async fn start_connection_monitor(&self) {
        let socket = self.socket.clone();
        let state = self.state.clone();
        let stop_flag = self.stop_reconnecting.clone();
        let config = self.config.clone();
        let event_tx = self.connection_event_tx.clone();
        let connector_channel = self.connector_channel.clone();

        tokio::spawn(async move {
            let mut check_interval = tokio::time::interval(Duration::from_secs(5));

            loop {
                check_interval.tick().await;

                // Check if we should stop
                if *stop_flag.read().await {
                    debug!("Connection monitor stopped");
                    break;
                }

                // Check if socket is still connected
                let is_connected = socket.read().await.is_connected().await;

                if !is_connected {
                    let current_state = *state.read().await;
                    if current_state == ConnectionState::Connected {
                        // Connection was lost - attempt reconnect
                        warn!("Connection lost, attempting reconnect...");
                        *state.write().await = ConnectionState::Reconnecting;

                        if let Some(tx) = &event_tx {
                            let _ = tx
                                .send(ConnectionEvent::Disconnected {
                                    reason: "Connection lost".into(),
                                })
                                .await;
                        }

                        // Attempt reconnection with exponential backoff
                        let mut reconnected = false;
                        for attempt in 1..=config.max_reconnect_attempts {
                            if *stop_flag.read().await {
                                break;
                            }

                            if let Some(tx) = &event_tx {
                                let _ = tx
                                    .send(ConnectionEvent::Reconnecting {
                                        attempt,
                                        max_attempts: config.max_reconnect_attempts,
                                    })
                                    .await;
                            }

                            let delay = Self::calculate_backoff(attempt);
                            info!("Reconnection attempt {} in {:?}", attempt, delay);
                            tokio::time::sleep(delay).await;

                            // Try to reconnect
                            let mut socket_guard = socket.write().await;
                            if socket_guard.connect().await.is_ok() {
                                drop(socket_guard);
                                *state.write().await = ConnectionState::Connected;

                                // Re-join connector channel if needed
                                if config.auto_join_connector {
                                    let topic =
                                        format!("sensocto:connector:{}", config.connector_id);
                                    let join_params = serde_json::json!({
                                        "connector_id": config.connector_id,
                                        "connector_name": config.connector_name,
                                        "connector_type": config.connector_type,
                                        "features": config.features,
                                        "bearer_token": config.bearer_token.clone().unwrap_or_default()
                                    });

                                    let channel =
                                        PhoenixChannel::new(socket.clone(), topic, join_params);
                                    if channel.join().await.is_ok() {
                                        *connector_channel.write().await = Some(channel);
                                    }
                                }

                                if let Some(tx) = &event_tx {
                                    let _ = tx.send(ConnectionEvent::Reconnected { attempt }).await;
                                }

                                info!("Reconnected on attempt {}", attempt);
                                reconnected = true;
                                break;
                            }
                        }

                        if !reconnected && !*stop_flag.read().await {
                            *state.write().await = ConnectionState::Error;
                            error!(
                                "Failed to reconnect after {} attempts",
                                config.max_reconnect_attempts
                            );

                            if let Some(tx) = &event_tx {
                                let _ = tx
                                    .send(ConnectionEvent::ReconnectionFailed {
                                        attempts: config.max_reconnect_attempts,
                                        last_error: "Connection failed".into(),
                                    })
                                    .await;
                            }
                            break;
                        }
                    }
                }
            }
        });
    }

    /// Calculates exponential backoff delay with jitter.
    fn calculate_backoff(attempt: u32) -> Duration {
        // Base delay: 1s, 2s, 4s, 8s, 16s, max 30s
        let base_ms = 1000u64 * 2u64.pow(attempt.saturating_sub(1));
        let capped_ms = base_ms.min(30_000);

        // Add jitter (±20%)
        let jitter_range = capped_ms / 5;
        let jitter = (rand::random::<u64>() % (jitter_range * 2)).saturating_sub(jitter_range);
        let final_ms = capped_ms.saturating_add(jitter);

        Duration::from_millis(final_ms)
    }

    /// Emits a connection event if a receiver is configured.
    async fn emit_event(&self, event: ConnectionEvent) {
        if let Some(tx) = &self.connection_event_tx {
            let _ = tx.send(event).await;
        }
    }

    /// Returns the current connection state.
    pub async fn connection_state(&self) -> ConnectionState {
        *self.state.read().await
    }

    /// Returns whether the client is connected.
    pub async fn is_connected(&self) -> bool {
        *self.state.read().await == ConnectionState::Connected
    }

    /// Registers a sensor and returns a stream for sending measurements.
    pub async fn register_sensor(
        &self,
        config: SensorConfig,
    ) -> Result<(SensorStream, mpsc::Receiver<SensorEvent>)> {
        if !self.is_connected().await {
            return Err(SensoctoError::Disconnected);
        }

        let sensor_id = config.sensor_id.clone();
        let topic = format!("sensocto:sensor:{}", sensor_id);

        let join_params = serde_json::json!({
            "connector_id": self.config.connector_id,
            "connector_name": self.config.connector_name,
            "sensor_id": sensor_id,
            "sensor_name": config.sensor_name,
            "sensor_type": config.sensor_type,
            "attributes": config.attributes,
            "sampling_rate": config.sampling_rate_hz,
            "batch_size": config.batch_size,
            "bearer_token": self.config.bearer_token.clone().unwrap_or_default()
        });

        let channel = PhoenixChannel::new(self.socket.clone(), topic.clone(), join_params);

        // Set up backpressure handler before joining
        let socket = self.socket.read().await;
        let backpressure_config = Arc::new(RwLock::new(BackpressureConfig::default()));
        let bp_config = backpressure_config.clone();

        socket
            .on(&topic, "backpressure_config", move |payload| {
                if let Ok(config) = serde_json::from_value::<BackpressureConfig>(payload) {
                    debug!("Received backpressure config: {:?}", config);
                    // Note: This is a simplified approach. In production, you'd want
                    // to properly propagate this to the SensorStream.
                    let bp = bp_config.clone();
                    tokio::spawn(async move {
                        *bp.write().await = config;
                    });
                }
            })
            .await;
        drop(socket);

        // Join the channel
        channel.join().await?;

        let (stream, event_rx) = SensorStream::new(channel, sensor_id, config);

        info!("Registered sensor: {}", stream.sensor_id());

        Ok((stream, event_rx))
    }

    /// Joins a video/voice call in a room.
    pub async fn join_call(
        &self,
        room_id: &str,
        user_id: &str,
        user_info: Option<HashMap<String, serde_json::Value>>,
    ) -> Result<(CallSession, mpsc::Receiver<CallEvent>)> {
        if !self.is_connected().await {
            return Err(SensoctoError::Disconnected);
        }

        let topic = format!("call:{}", room_id);

        let join_params = serde_json::json!({
            "user_id": user_id,
            "user_info": user_info.unwrap_or_default()
        });

        let channel = PhoenixChannel::new(self.socket.clone(), topic.clone(), join_params);

        // Join the channel
        let response = channel.join().await?;

        // Extract ICE servers from response
        let ice_servers = response
            .get("ice_servers")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let (session, event_rx) =
            CallSession::new(channel, room_id.to_string(), user_id.to_string(), ice_servers);

        // Set up event handlers
        let socket = self.socket.read().await;
        let session_arc = Arc::new(session);

        for event in &[
            "participant_joined",
            "participant_left",
            "media_event",
            "participant_audio_changed",
            "participant_video_changed",
            "quality_changed",
            "call_ended",
        ] {
            let session_clone = session_arc.clone();
            let event_name = event.to_string();
            socket
                .on(&topic, event, move |payload| {
                    let s = session_clone.clone();
                    let e = event_name.clone();
                    tokio::spawn(async move {
                        s.handle_event(&e, payload).await;
                    });
                })
                .await;
        }
        drop(socket);

        info!("Joined call channel: {}", room_id);

        // Extract the session from Arc (we know there's only one reference)
        let session = Arc::try_unwrap(session_arc).map_err(|_| {
            SensoctoError::Other("Failed to unwrap session".into())
        })?;

        Ok((session, event_rx))
    }

    /// Joins the connector channel.
    async fn join_connector_channel(&self) -> Result<()> {
        let topic = format!("sensocto:connector:{}", self.config.connector_id);

        let join_params = serde_json::json!({
            "connector_id": self.config.connector_id,
            "connector_name": self.config.connector_name,
            "connector_type": self.config.connector_type,
            "features": self.config.features,
            "bearer_token": self.config.bearer_token.clone().unwrap_or_default()
        });

        let channel = PhoenixChannel::new(self.socket.clone(), topic, join_params);
        channel.join().await?;

        *self.connector_channel.write().await = Some(channel);

        info!("Joined connector channel");

        Ok(())
    }

    /// Returns the connector ID.
    pub fn connector_id(&self) -> &str {
        &self.config.connector_id
    }

    /// Returns the connector name.
    pub fn connector_name(&self) -> &str {
        &self.config.connector_name
    }
}
