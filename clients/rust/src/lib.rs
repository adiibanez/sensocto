// Allow certain clippy lints for SDK usability
#![allow(clippy::result_large_err)]
#![allow(dead_code)]

//! # Sensocto Rust SDK
//!
//! Rust client library for connecting to the Sensocto sensor platform.
//!
//! ## Features
//!
//! - Real-time sensor data streaming via Phoenix WebSocket channels
//! - Video/voice call support via WebRTC signaling
//! - Automatic reconnection and backpressure handling
//! - Both async and blocking APIs
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use sensocto::{SensoctoClient, SensorConfig};
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     // Create configuration
//!     let config = SensoctoClient::builder()
//!         .server_url("https://your-server.com")
//!         .connector_name("Rust Sensor")
//!         .bearer_token("your-token")
//!         .build()?;
//!
//!     // Create client
//!     let client = SensoctoClient::new(config)?;
//!
//!     // Connect
//!     client.connect().await?;
//!
//!     // Register a sensor
//!     let sensor_config = SensorConfig::new("temperature-sensor")
//!         .with_sensor_type("temperature")
//!         .with_attributes(vec!["celsius", "fahrenheit"]);
//!
//!     let (sensor, _event_rx) = client.register_sensor(sensor_config).await?;
//!
//!     // Send measurements
//!     sensor.send_measurement("celsius", serde_json::json!({"value": 23.5})).await?;
//!
//!     // Or use batch sending
//!     sensor.add_to_batch("celsius", serde_json::json!({"value": 23.6})).await;
//!     sensor.flush_batch().await?;
//!
//!     Ok(())
//! }
//! ```

pub mod channel;
pub mod client;
pub mod config;
pub mod error;
pub mod models;
pub mod socket;

// Re-exports
pub use client::SensoctoClient;
pub use config::{SensoctoConfig, SensorConfig};
pub use error::{Result, SensoctoError};
pub use models::*;

/// Returns the version of the Sensocto SDK.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        let v = version();
        assert!(!v.is_empty());
        assert!(v.contains('.'));
    }
}
