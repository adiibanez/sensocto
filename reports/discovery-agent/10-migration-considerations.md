# Migration Considerations: Phoenix/Elixir to Dioxus/Rust

## Architecture Mapping

### Server-Client Split

| Phoenix/Elixir | Dioxus/Rust Mobile | Notes |
|----------------|-------------------|-------|
| LiveView | Dioxus components | Reactivity model differs |
| PubSub | Internal event channels | tokio broadcast/mpsc |
| GenServer | Actor pattern (actix) or state management | Consider tokio tasks |
| Phoenix Channels | WebSocket client | tokio-tungstenite |
| Ecto | SQLx or diesel | For local SQLite |
| Ash Framework | Custom domain logic | No direct equivalent |

### What Stays Server-Side

These components remain on the Elixir server:

1. **Room synchronization (Iroh)** - P2P coordination
2. **Multi-user data sharing** - Central relay
3. **User authentication** - JWT validation
4. **Historical data storage** - PostgreSQL
5. **WebRTC signaling** - PubSub relay

### What Moves Client-Side (Dioxus)

1. **BLE connectivity** - Native Bluetooth APIs
2. **Data visualization** - Dioxus components + canvas/wgpu
3. **Local sensor management** - In-app state
4. **Offline data caching** - SQLite
5. **Device sensors (IMU, GPS)** - Platform APIs

## Feature-by-Feature Migration

### 1. BLE Integration

**Current (Web Bluetooth)**:
```javascript
navigator.bluetooth.requestDevice({
  filters: [{namePrefix: "Movesense"}],
  optionalServices: ["heart_rate"]
})
```

**Dioxus/Rust**:
```rust
// Using btleplug crate
use btleplug::api::{Central, Manager, Peripheral, ScanFilter};

async fn scan_devices() -> Result<Vec<Peripheral>> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    let central = adapters.into_iter().next().unwrap();

    central.start_scan(ScanFilter::default()).await?;
    // Filter by name prefix
}
```

**Considerations**:
- btleplug works on macOS, Linux, Windows
- iOS/Android require platform-specific code (CoreBluetooth, Android BLE)
- Consider using uniffi for cross-platform Bluetooth abstraction

### 2. Data Parsing

**Current (JavaScript)**:
```javascript
static decodeHeartRate(data) {
    const flags = data.getUint8(0);
    const heartRateFormatBit = flags & 0x01;
    return heartRateFormatBit === 0
        ? data.getUint8(1)
        : data.getUint16(1, true);
}
```

**Dioxus/Rust**:
```rust
use bytes::Buf;

fn decode_heart_rate(data: &[u8]) -> Option<u16> {
    if data.is_empty() { return None; }
    let flags = data[0];
    if flags & 0x01 == 0 {
        Some(data.get(1).copied()? as u16)
    } else {
        if data.len() < 3 { return None; }
        Some(u16::from_le_bytes([data[1], data[2]]))
    }
}
```

**Considerations**:
- Rust's type system catches parsing errors at compile time
- Use `nom` or `binread` for complex binary parsing
- Create trait `BleDecoder` for consistent interface

### 3. State Management

**Current (GenServer + LiveView)**:
```elixir
# GenServer holds sensor state
def handle_cast({:put_attribute, attr}, state) do
  Phoenix.PubSub.broadcast(PubSub, topic, {:measurement, attr})
  {:noreply, update_state(state, attr)}
end

# LiveView subscribes
def mount(_, _, socket) do
  Phoenix.PubSub.subscribe(PubSub, "data:#{sensor_id}")
  {:ok, assign(socket, ...)}
end
```

**Dioxus/Rust**:
```rust
use dioxus::prelude::*;
use tokio::sync::broadcast;

// Global state with signals
static SENSOR_DATA: GlobalSignal<HashMap<String, SensorState>> = Signal::global(|| HashMap::new());

// Broadcast channel for updates
static UPDATES: Lazy<broadcast::Sender<SensorUpdate>> = Lazy::new(|| {
    let (tx, _) = broadcast::channel(1000);
    tx
});

#[component]
fn SensorView(sensor_id: String) -> Element {
    let data = SENSOR_DATA.read();
    let sensor = data.get(&sensor_id);

    // Subscribe to updates
    use_effect(move || {
        let mut rx = UPDATES.subscribe();
        spawn(async move {
            while let Ok(update) = rx.recv().await {
                if update.sensor_id == sensor_id {
                    // Update local state
                }
            }
        });
    });

    rsx! { /* render */ }
}
```

### 4. Visualizations

**Current (Svelte + Canvas)**:
```javascript
// ECGVisualization.svelte
function render(canvas, data) {
    const ctx = canvas.getContext("2d");
    ctx.beginPath();
    data.forEach((point, i) => {
        const x = i * dx;
        const y = normalize(point.payload);
        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();
}
```

**Dioxus/Rust Options**:

1. **Canvas via web-sys (WASM)**:
```rust
use web_sys::CanvasRenderingContext2d;

fn render_ecg(ctx: &CanvasRenderingContext2d, data: &[DataPoint]) {
    ctx.begin_path();
    for (i, point) in data.iter().enumerate() {
        let x = i as f64 * dx;
        let y = normalize(point.payload);
        if i == 0 {
            ctx.move_to(x, y);
        } else {
            ctx.line_to(x, y);
        }
    }
    ctx.stroke();
}
```

2. **Native with wgpu**:
```rust
use wgpu;
// GPU-accelerated rendering for mobile performance
```

3. **Using plotters crate**:
```rust
use plotters::prelude::*;

fn draw_ecg(data: &[f64]) -> Result<(), Box<dyn Error>> {
    let root = BitMapBackend::new("ecg.png", (800, 400)).into_drawing_area();
    let mut chart = ChartBuilder::on(&root)
        .build_cartesian_2d(0..data.len(), -1.0..2.0)?;
    chart.draw_series(LineSeries::new(
        data.iter().enumerate().map(|(i, &v)| (i, v)),
        &BLUE,
    ))?;
    Ok(())
}
```

### 5. WebSocket Communication

**Current (Phoenix Channel)**:
```javascript
let channel = socket.channel("sensor_data:lobby", {device_id: deviceId});
channel.push('measurement', {type: 'heartrate', value: 72});
channel.on("backpressure_config", (payload) => { ... });
```

**Dioxus/Rust**:
```rust
use tokio_tungstenite::{connect_async, tungstenite::Message};
use serde_json::json;

async fn connect_to_server(device_id: &str) -> Result<()> {
    let (ws_stream, _) = connect_async("wss://server/socket/websocket").await?;
    let (mut write, mut read) = ws_stream.split();

    // Join channel (Phoenix protocol)
    let join_msg = json!({
        "topic": "sensor_data:lobby",
        "event": "phx_join",
        "payload": {"device_id": device_id},
        "ref": "1"
    });
    write.send(Message::Text(join_msg.to_string())).await?;

    // Handle messages
    while let Some(msg) = read.next().await {
        match msg? {
            Message::Text(text) => {
                let parsed: PhoenixMessage = serde_json::from_str(&text)?;
                handle_message(parsed).await;
            }
            _ => {}
        }
    }
    Ok(())
}
```

### 6. Local Storage

**Current (PostgreSQL + ETS)**:
```elixir
# Cold storage
Repo.insert!(%SensorAttributeData{...})

# Hot storage
AttributeStore.put_attribute(sensor_id, attr_id, ts, payload)
```

**Dioxus/Rust**:
```rust
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

// Local SQLite for persistence
async fn store_measurement(pool: &SqlitePool, m: &Measurement) -> Result<()> {
    sqlx::query!(
        "INSERT INTO measurements (sensor_id, attribute_id, timestamp, payload) VALUES (?, ?, ?, ?)",
        m.sensor_id, m.attribute_id, m.timestamp, m.payload_json
    )
    .execute(pool)
    .await?;
    Ok(())
}

// In-memory ring buffer for hot data
use ringbuf::HeapRb;
let rb = HeapRb::<Measurement>::new(1000);
```

## Platform-Specific Considerations

### iOS

- **BLE**: Use CoreBluetooth via objc crate or swift-bridge
- **Background modes**: Request BLE background capability
- **Permissions**: Info.plist entries for Bluetooth, Location
- **UI**: Consider native feel with dioxus-ios or separate SwiftUI layer

### Android

- **BLE**: Use Android BLE APIs via jni
- **Permissions**: Runtime permission requests
- **Services**: Foreground service for continuous sensor reading
- **UI**: Material Design guidelines

### Desktop (macOS/Windows/Linux)

- **BLE**: btleplug works well
- **No special permissions**: Standard user permissions
- **UI**: Can use web-view or native rendering

## Challenges and Solutions

### 1. Real-time Performance

**Challenge**: 512 Hz ECG requires smooth rendering

**Solutions**:
- Use ring buffers with pre-allocated memory
- Render on separate thread with double buffering
- Consider wgpu for GPU-accelerated rendering
- Downsample for display (keep full resolution for storage)

### 2. Offline Operation

**Challenge**: App should work without server

**Solutions**:
- Local SQLite for data persistence
- Queue server syncs for when online
- P2P sync consideration (libp2p in Rust)

### 3. Cross-Platform BLE

**Challenge**: BLE APIs differ by platform

**Solutions**:
- Create platform abstraction layer
- Use uniffi for cross-platform FFI
- Consider capacitor-style plugin system

### 4. UI Responsiveness

**Challenge**: Sensor data shouldn't block UI

**Solutions**:
- Tokio for async operations
- Dedicated threads for data processing
- Signal-based reactivity (Dioxus provides this)

## Recommended Crates

```toml
[dependencies]
# Framework
dioxus = "0.5"

# Async runtime
tokio = { version = "1", features = ["full"] }

# Bluetooth
btleplug = "0.11"

# WebSocket
tokio-tungstenite = "0.20"

# Database
sqlx = { version = "0.7", features = ["sqlite", "runtime-tokio"] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Binary parsing
bytes = "1"
nom = "7"  # For complex parsing

# Visualization
plotters = "0.3"

# Logging
tracing = "0.1"
```

## Migration Phases

### Phase 1: Core Infrastructure
- WebSocket connection to existing server
- Basic data models and parsing
- Simple sensor list UI

### Phase 2: BLE Integration
- Device scanning and connection
- Characteristic notifications
- Data decoding pipeline

### Phase 3: Visualizations
- ECG rendering
- IMU 3D display
- Maps integration

### Phase 4: Full Features
- Room support
- WebRTC calls
- Offline mode

### Phase 5: Platform Polish
- iOS/Android specific features
- Performance optimization
- App store preparation
