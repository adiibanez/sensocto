//! Error types for the Sensocto client.

use thiserror::Error;

/// Result type alias for Sensocto operations.
pub type Result<T> = std::result::Result<T, SensoctoError>;

/// Errors that can occur when using the Sensocto client.
#[derive(Error, Debug)]
pub enum SensoctoError {
    /// Connection to the server failed.
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    /// WebSocket error.
    #[error("WebSocket error: {0}")]
    WebSocketError(#[from] tokio_tungstenite::tungstenite::Error),

    /// Channel join failed.
    #[error("Failed to join channel '{topic}': {reason}")]
    ChannelJoinFailed { topic: String, reason: String },

    /// Channel not joined.
    #[error("Channel '{0}' is not joined")]
    ChannelNotJoined(String),

    /// Authentication failed.
    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    /// Server returned an error.
    #[error("Server error: {0}")]
    ServerError(String),

    /// Request timed out.
    #[error("Request timed out after {0}ms")]
    Timeout(u64),

    /// Invalid configuration.
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    /// JSON serialization/deserialization error.
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    /// URL parsing error.
    #[error("Invalid URL: {0}")]
    UrlError(#[from] url::ParseError),

    /// Channel send error.
    #[error("Channel send error: {0}")]
    ChannelSendError(String),

    /// The client is disconnected.
    #[error("Client is disconnected")]
    Disconnected,

    /// Invalid attribute ID format.
    #[error("Invalid attribute ID: {0}")]
    InvalidAttributeId(String),

    /// Generic error.
    #[error("{0}")]
    Other(String),
}

impl SensoctoError {
    /// Returns true if this error indicates a connection problem.
    pub fn is_connection_error(&self) -> bool {
        matches!(
            self,
            SensoctoError::ConnectionFailed(_)
                | SensoctoError::WebSocketError(_)
                | SensoctoError::Disconnected
        )
    }

    /// Returns true if this error indicates an authentication problem.
    pub fn is_auth_error(&self) -> bool {
        matches!(self, SensoctoError::AuthenticationFailed(_))
    }

    /// Returns true if this error is recoverable (e.g., by retrying).
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            SensoctoError::Timeout(_)
                | SensoctoError::ConnectionFailed(_)
                | SensoctoError::WebSocketError(_)
        )
    }
}
