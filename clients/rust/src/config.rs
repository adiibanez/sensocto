//! Configuration types for the Sensocto client.

use crate::error::{Result, SensoctoError};
use std::time::Duration;
use uuid::Uuid;

/// Configuration for the Sensocto client.
#[derive(Debug, Clone)]
pub struct SensoctoConfig {
    /// The Sensocto server URL.
    pub server_url: String,

    /// Unique identifier for this connector.
    pub connector_id: String,

    /// Human-readable name for this connector.
    pub connector_name: String,

    /// Type of connector (e.g., "rust", "iot", "mobile").
    pub connector_type: String,

    /// Bearer token for authentication.
    pub bearer_token: Option<String>,

    /// Automatically join connector channel on connect.
    pub auto_join_connector: bool,

    /// Heartbeat interval.
    pub heartbeat_interval: Duration,

    /// Connection timeout.
    pub connection_timeout: Duration,

    /// Whether to auto-reconnect on disconnect.
    pub auto_reconnect: bool,

    /// Maximum reconnection attempts.
    pub max_reconnect_attempts: u32,

    /// Supported features.
    pub features: Vec<String>,
}

impl Default for SensoctoConfig {
    fn default() -> Self {
        Self {
            server_url: "http://localhost:4000".to_string(),
            connector_id: Uuid::new_v4().to_string(),
            connector_name: "Rust Connector".to_string(),
            connector_type: "rust".to_string(),
            bearer_token: None,
            auto_join_connector: true,
            heartbeat_interval: Duration::from_secs(30),
            connection_timeout: Duration::from_secs(10),
            auto_reconnect: true,
            max_reconnect_attempts: 5,
            features: Vec::new(),
        }
    }
}

impl SensoctoConfig {
    /// Creates a new configuration builder.
    pub fn builder() -> SensoctoConfigBuilder {
        SensoctoConfigBuilder::default()
    }

    /// Validates the configuration.
    pub fn validate(&self) -> Result<()> {
        if self.server_url.is_empty() {
            return Err(SensoctoError::InvalidConfig(
                "Server URL is required".into(),
            ));
        }

        url::Url::parse(&self.server_url)?;

        if self.heartbeat_interval.as_millis() < 1000 {
            return Err(SensoctoError::InvalidConfig(
                "Heartbeat interval must be at least 1 second".into(),
            ));
        }

        Ok(())
    }

    /// Returns the WebSocket URL for connecting.
    pub fn websocket_url(&self) -> Result<String> {
        let base = url::Url::parse(&self.server_url)?;
        let protocol = if base.scheme() == "https" {
            "wss"
        } else {
            "ws"
        };
        let host = base
            .host_str()
            .ok_or_else(|| SensoctoError::InvalidConfig("Server URL must have a host".into()))?;
        let port = base.port().map(|p| format!(":{}", p)).unwrap_or_default();

        Ok(format!("{}://{}{}/socket/websocket", protocol, host, port))
    }
}

/// Builder for SensoctoConfig.
#[derive(Debug, Default)]
pub struct SensoctoConfigBuilder {
    config: SensoctoConfig,
}

impl SensoctoConfigBuilder {
    /// Sets the server URL.
    pub fn server_url(mut self, url: impl Into<String>) -> Self {
        self.config.server_url = url.into();
        self
    }

    /// Sets the connector ID.
    pub fn connector_id(mut self, id: impl Into<String>) -> Self {
        self.config.connector_id = id.into();
        self
    }

    /// Sets the connector name.
    pub fn connector_name(mut self, name: impl Into<String>) -> Self {
        self.config.connector_name = name.into();
        self
    }

    /// Sets the connector type.
    pub fn connector_type(mut self, typ: impl Into<String>) -> Self {
        self.config.connector_type = typ.into();
        self
    }

    /// Sets the bearer token.
    pub fn bearer_token(mut self, token: impl Into<String>) -> Self {
        self.config.bearer_token = Some(token.into());
        self
    }

    /// Sets whether to auto-join the connector channel.
    pub fn auto_join_connector(mut self, auto_join: bool) -> Self {
        self.config.auto_join_connector = auto_join;
        self
    }

    /// Sets the heartbeat interval.
    pub fn heartbeat_interval(mut self, interval: Duration) -> Self {
        self.config.heartbeat_interval = interval;
        self
    }

    /// Sets the connection timeout.
    pub fn connection_timeout(mut self, timeout: Duration) -> Self {
        self.config.connection_timeout = timeout;
        self
    }

    /// Sets whether to auto-reconnect.
    pub fn auto_reconnect(mut self, auto_reconnect: bool) -> Self {
        self.config.auto_reconnect = auto_reconnect;
        self
    }

    /// Sets the maximum reconnection attempts.
    pub fn max_reconnect_attempts(mut self, attempts: u32) -> Self {
        self.config.max_reconnect_attempts = attempts;
        self
    }

    /// Sets the supported features.
    pub fn features(mut self, features: Vec<String>) -> Self {
        self.config.features = features;
        self
    }

    /// Builds the configuration.
    pub fn build(self) -> Result<SensoctoConfig> {
        self.config.validate()?;
        Ok(self.config)
    }
}

/// Configuration for a sensor.
#[derive(Debug, Clone)]
pub struct SensorConfig {
    /// Unique sensor identifier.
    pub sensor_id: String,

    /// Human-readable name for the sensor.
    pub sensor_name: String,

    /// Type of sensor.
    pub sensor_type: String,

    /// List of attributes this sensor will report.
    pub attributes: Vec<String>,

    /// Sampling rate in Hz.
    pub sampling_rate_hz: u32,

    /// Number of measurements to batch.
    pub batch_size: u32,
}

impl SensorConfig {
    /// Creates a new sensor configuration with the given name.
    pub fn new(sensor_name: impl Into<String>) -> Self {
        Self {
            sensor_id: Uuid::new_v4().to_string(),
            sensor_name: sensor_name.into(),
            sensor_type: "generic".to_string(),
            attributes: Vec::new(),
            sampling_rate_hz: 10,
            batch_size: 5,
        }
    }

    /// Sets the sensor ID.
    pub fn with_sensor_id(mut self, id: impl Into<String>) -> Self {
        self.sensor_id = id.into();
        self
    }

    /// Sets the sensor type.
    pub fn with_sensor_type(mut self, sensor_type: impl Into<String>) -> Self {
        self.sensor_type = sensor_type.into();
        self
    }

    /// Sets the attributes.
    pub fn with_attributes(mut self, attributes: Vec<impl Into<String>>) -> Self {
        self.attributes = attributes.into_iter().map(|a| a.into()).collect();
        self
    }

    /// Sets the sampling rate.
    pub fn with_sampling_rate(mut self, hz: u32) -> Self {
        self.sampling_rate_hz = hz;
        self
    }

    /// Sets the batch size.
    pub fn with_batch_size(mut self, size: u32) -> Self {
        self.batch_size = size;
        self
    }
}
