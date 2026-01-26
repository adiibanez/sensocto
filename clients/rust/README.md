# Sensocto Rust SDK

[![Rust SDK CI](https://github.com/sensocto/sensocto/actions/workflows/rust-sdk.yml/badge.svg)](https://github.com/sensocto/sensocto/actions/workflows/rust-sdk.yml)
[![Crates.io](https://img.shields.io/crates/v/sensocto.svg)](https://crates.io/crates/sensocto)
[![Documentation](https://docs.rs/sensocto/badge.svg)](https://docs.rs/sensocto)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![MSRV](https://img.shields.io/badge/MSRV-1.70.0-blue.svg)](https://blog.rust-lang.org/2023/06/01/Rust-1.70.0.html)

Rust client library for connecting to the Sensocto sensor platform. Stream real-time sensor data, join video/voice calls, and manage rooms.

## Features

- Async-first design using Tokio
- Real-time sensor data streaming via Phoenix WebSocket channels
- Video/voice call support via WebRTC signaling
- Automatic backpressure handling
- Type-safe API with comprehensive error handling

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
sensocto = "0.1"
tokio = { version = "1", features = ["full"] }
```

## Quick Start

### Basic Connection

```rust
use sensocto::{SensoctoClient, SensorConfig};
use std::collections::HashMap;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Create client with builder pattern
    let client = SensoctoClient::builder()
        .server_url("https://your-sensocto-server.com")
        .connector_name("Rust Sensor Device")
        .bearer_token("your-auth-token")
        .build()?;

    // Connect to server
    client.connect().await?;

    println!("Connected to Sensocto!");

    // Keep running...
    tokio::signal::ctrl_c().await?;

    client.disconnect().await;
    Ok(())
}
```

### Streaming Sensor Data

```rust
use sensocto::{SensoctoClient, SensorConfig};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let client = SensoctoClient::builder()
        .server_url("https://your-server.com")
        .bearer_token("your-token")
        .build()?;

    client.connect().await?;

    // Configure sensor
    let sensor_config = SensorConfig::new("Temperature Sensor")
        .with_sensor_type("temperature")
        .with_attributes(vec!["celsius", "fahrenheit", "humidity"])
        .with_sampling_rate(10)  // 10 Hz
        .with_batch_size(5);

    // Register sensor
    let (sensor, mut events) = client.register_sensor(sensor_config).await?;

    // Handle backpressure events in background
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            match event {
                sensocto::SensorEvent::BackpressureConfig(config) => {
                    println!("Backpressure update: {:?}", config.attention_level);
                }
                _ => {}
            }
        }
    });

    // Send measurements
    loop {
        // Single measurement
        sensor.send_measurement(
            "celsius",
            serde_json::json!({"value": 23.5, "unit": "C"})
        ).await?;

        // Or use batching for efficiency
        sensor.add_to_batch("celsius", serde_json::json!({"value": 23.6})).await;
        sensor.add_to_batch("humidity", serde_json::json!({"value": 45.2})).await;

        // Batch is automatically flushed when it reaches the configured size
        // Or flush manually:
        // sensor.flush_batch().await?;

        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
}
```

### IMU Sensor Data

```rust
use sensocto::{SensoctoClient, SensorConfig};

async fn stream_imu_data(client: &SensoctoClient) -> anyhow::Result<()> {
    let sensor_config = SensorConfig::new("IMU Sensor")
        .with_sensor_type("imu")
        .with_attributes(vec!["accelerometer", "gyroscope", "magnetometer"])
        .with_sampling_rate(100)  // 100 Hz for IMU
        .with_batch_size(10);

    let (sensor, _events) = client.register_sensor(sensor_config).await?;

    loop {
        // Simulated IMU data - replace with actual sensor readings
        let accel = serde_json::json!({
            "x": 0.01,
            "y": 0.02,
            "z": 9.81
        });

        let gyro = serde_json::json!({
            "x": 0.001,
            "y": -0.002,
            "z": 0.0005
        });

        sensor.add_to_batch("accelerometer", accel).await;
        sensor.add_to_batch("gyroscope", gyro).await;

        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    }
}
```

### Video/Voice Calls

```rust
use sensocto::{SensoctoClient, CallEvent};
use std::collections::HashMap;

async fn join_video_call(client: &SensoctoClient) -> anyhow::Result<()> {
    // Join call channel
    let user_info = HashMap::from([
        ("name".to_string(), serde_json::json!("Alice")),
        ("avatar".to_string(), serde_json::json!("https://example.com/avatar.png")),
    ]);

    let (call, mut events) = client.join_call(
        "room-123",
        "user-456",
        Some(user_info)
    ).await?;

    // Handle call events
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            match event {
                CallEvent::ParticipantJoined(p) => {
                    println!("Participant joined: {}", p.user_id);
                }
                CallEvent::ParticipantLeft { user_id, crashed } => {
                    println!("Participant left: {} (crashed: {})", user_id, crashed);
                }
                CallEvent::MediaEvent(data) => {
                    // Handle WebRTC signaling (SDP offers/answers, ICE candidates)
                    println!("Media event: {:?}", data);
                }
                CallEvent::CallEnded => {
                    println!("Call ended");
                    break;
                }
                _ => {}
            }
        }
    });

    // Actually join the call
    let join_result = call.join_call().await?;
    println!("Joined call with endpoint: {:?}", join_result.get("endpoint_id"));

    // Get ICE servers for WebRTC
    println!("ICE servers: {:?}", call.ice_servers());

    // Toggle audio/video
    call.toggle_audio(true).await?;
    call.toggle_video(false).await?;

    // Send WebRTC signaling data
    call.send_media_event(serde_json::json!({
        "type": "offer",
        "sdp": "..."
    })).await?;

    // Get participants
    let participants = call.get_participants().await?;
    println!("Participants: {:?}", participants);

    // Leave call when done
    call.leave_call().await?;

    Ok(())
}
```

## Configuration Options

```rust
use sensocto::SensoctoClient;
use std::time::Duration;

let client = SensoctoClient::builder()
    // Required
    .server_url("https://sensocto.example.com")

    // Authentication
    .bearer_token("your-jwt-token")

    // Connector identity
    .connector_name("My Rust Device")
    .connector_type("iot")
    .connector_id("custom-id")  // Auto-generated if not set

    // Connection behavior
    .auto_join_connector(true)
    .auto_reconnect(true)
    .max_reconnect_attempts(5)

    // Timing
    .heartbeat_interval(Duration::from_secs(30))
    .connection_timeout(Duration::from_secs(10))

    // Features
    .features(vec!["streaming".to_string(), "calls".to_string()])

    .build()?;
```

## Error Handling

```rust
use sensocto::{SensoctoClient, SensoctoError};

async fn handle_errors() {
    let client = SensoctoClient::builder()
        .server_url("https://server.com")
        .build()
        .unwrap();

    match client.connect().await {
        Ok(()) => println!("Connected!"),
        Err(SensoctoError::ConnectionFailed(msg)) => {
            eprintln!("Connection failed: {}", msg);
        }
        Err(SensoctoError::AuthenticationFailed(msg)) => {
            eprintln!("Auth failed: {}", msg);
        }
        Err(SensoctoError::Timeout(ms)) => {
            eprintln!("Connection timed out after {}ms", ms);
        }
        Err(e) => {
            eprintln!("Other error: {}", e);

            // Check error properties
            if e.is_recoverable() {
                println!("This error might be recoverable by retrying");
            }
        }
    }
}
```

## Backpressure Handling

The server sends backpressure configuration to help you adjust data transmission rates:

```rust
use sensocto::{SensorEvent, AttentionLevel};

// In your event handler
match event {
    SensorEvent::BackpressureConfig(config) => {
        match config.attention_level {
            AttentionLevel::High => {
                // Server wants fast updates - send more frequently
                println!("High attention - increasing update rate");
            }
            AttentionLevel::Medium => {
                // Normal operation
            }
            AttentionLevel::Low | AttentionLevel::None => {
                // Server has low attention - can batch more aggressively
                println!("Low attention - batching more data");
            }
        }

        // Use recommended settings
        println!("Recommended batch size: {}", config.recommended_batch_size);
        println!("Recommended batch window: {}ms", config.recommended_batch_window);
    }
    _ => {}
}
```

## Attribute ID Rules

Attribute IDs must:
- Start with a letter (a-z, A-Z)
- Contain only alphanumeric characters, underscores, or hyphens
- Be 1-64 characters long

Valid examples: `heart_rate`, `accelerometer`, `gps-location`, `temp1`

## License

MIT License - see LICENSE file for details.

## Support

- Documentation: https://docs.sensocto.com
- Issues: https://github.com/sensocto/rust-sdk/issues
- Email: support@sensocto.com
