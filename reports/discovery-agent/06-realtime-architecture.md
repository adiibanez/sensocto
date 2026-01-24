# SensOcto Real-Time Architecture

## Overview

SensOcto implements a sophisticated real-time data pipeline that handles:
1. High-frequency sensor data ingestion (up to 512 Hz for ECG)
2. Multi-client data distribution via PubSub
3. Adaptive backpressure based on UI visibility
4. P2P synchronization across devices via Iroh

## Data Flow Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLIENT DEVICE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  BLE Device ──► Web Bluetooth API ──► BluetoothClient.svelte            │
│                                              │                          │
│                                              ▼                          │
│                                    BackpressureManager                  │
│                                    (client-side batching)               │
│                                              │                          │
│                                              ▼                          │
│                                    Phoenix Channel                      │
│                                    (WebSocket)                          │
└──────────────────────────────────────────────┬──────────────────────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           PHOENIX SERVER                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                     SensorDataChannel                                   │
│                           │                                             │
│         ┌─────────────────┼─────────────────┐                          │
│         ▼                 ▼                 ▼                          │
│   :measurement      :measurements_batch  :discovery                    │
│         │                 │                 │                          │
│         └─────────────────┼─────────────────┘                          │
│                           ▼                                             │
│                    SimpleSensor GenServer                               │
│                    (per sensor process)                                 │
│                           │                                             │
│         ┌─────────────────┼─────────────────┐                          │
│         ▼                 ▼                 ▼                          │
│   AttributeStore    PubSub Broadcast    Telemetry                      │
│   (tiered storage)  (fan-out)           (metrics)                      │
│         │                 │                                             │
│         ▼                 ▼                                             │
│   ┌─────────┐    ┌────────────────┐                                    │
│   │   ETS   │    │  "data:{id}"   │                                    │
│   │  (warm) │    │  :measurement  │                                    │
│   └────┬────┘    │  :measurements │                                    │
│        │         │     _batch     │                                    │
│        ▼         └───────┬────────┘                                    │
│   ┌─────────┐            │                                             │
│   │ Postgres│            ▼                                             │
│   │ (cold)  │    ┌───────────────┐                                    │
│   └─────────┘    │   LiveView    │                                    │
│                  │  Subscribers  │                                    │
│                  └───────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Phoenix PubSub Topics

### Sensor Data Topics

| Topic Pattern | Events | Purpose |
|---------------|--------|---------|
| `data:{sensor_id}` | `:measurement`, `:measurements_batch` | Real-time sensor values |
| `signal:{sensor_id}` | `:new_state` | Sensor state changes (attributes registered/unregistered) |
| `sensors:status` | `:sensor_connected`, `:sensor_disconnected` | Global sensor status |
| `sensors:all` | `:sensor_list_updated` | Sensor inventory changes |

### Room Topics

| Topic Pattern | Events | Purpose |
|---------------|--------|---------|
| `room:{room_id}` | `:member_joined`, `:member_left`, `:sensor_added`, `:settings_updated` | Room membership/config |
| `room:{room_id}:call` | `:peer_joined`, `:peer_left`, `:offer`, `:answer`, `:ice_candidate` | WebRTC signaling |
| `rooms:updates` | `:room_created`, `:room_updated`, `:room_deleted` | Global room changes |

### User Topics

| Topic Pattern | Events | Purpose |
|---------------|--------|---------|
| `user:{user_id}` | `:notification`, `:invitation` | User-specific events |

## Attention-Based Backpressure System

The system implements adaptive data throttling based on UI visibility:

### Client-Side (BackpressureManager in ble.js)

```javascript
class BackpressureManager {
    config = {
        attentionLevel: 'none',   // none|low|medium|high
        batchWindowMs: 5000,      // Time window for batching
        batchSize: 20             // Max messages per batch
    };

    queueMeasurement(measurement) {
        this.messageQueue.push(measurement);
        if (this.messageQueue.length >= this.config.batchSize) {
            this.flush();
        } else {
            this.ensureBatchTimer();
        }
    }
}
```

### Server-Side (SensorDataChannel)

The channel sends backpressure configuration to clients:

```elixir
# When attention level changes
push(socket, "backpressure_config", %{
  attention_level: "high",
  recommended_batch_window: 50,
  recommended_batch_size: 1,
  timestamp: System.system_time(:millisecond)
})
```

### Attention Levels

| Level | Batch Size | Batch Window | Use Case |
|-------|------------|--------------|----------|
| `high` | 1 | 50ms | User actively viewing sensor |
| `medium` | 5 | 200ms | Sensor visible but not focused |
| `low` | 10 | 1000ms | Sensor scrolled out of view |
| `none` | 20 | 5000ms | Tab/window not visible |

### LiveView Integration (StatefulSensorLive)

```elixir
def handle_event("visibility_changed", %{"visible" => visible}, socket) do
  attention_level = if visible, do: :high, else: :none
  # Notify channel to update backpressure config
  {:noreply, assign(socket, :attention_level, attention_level)}
end

def handle_info({:measurement, data}, socket) do
  case socket.assigns.attention_level do
    :high ->
      {:noreply, push_event(socket, "measurement", data)}
    _ ->
      # Buffer and batch
      {:noreply, buffer_measurement(socket, data)}
  end
end
```

## Tiered Data Storage

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Hot Tier                          │
│              (GenServer state map)                   │
│         • Last N values per attribute                │
│         • Immediate access                           │
│         • Auto-eviction on capacity                  │
└──────────────────────┬──────────────────────────────┘
                       │ overflow
                       ▼
┌─────────────────────────────────────────────────────┐
│                   Warm Tier                          │
│                  (ETS tables)                        │
│         • Configurable time window                   │
│         • Fast local access                          │
│         • Per-sensor tables                          │
└──────────────────────┬──────────────────────────────┘
                       │ age out
                       ▼
┌─────────────────────────────────────────────────────┐
│                   Cold Tier                          │
│             (PostgreSQL via Repo)                    │
│         • Unlimited historical data                  │
│         • Batched writes                             │
│         • Time-series queries                        │
└─────────────────────────────────────────────────────┘
```

### AttributeStoreTiered API

```elixir
# Write
AttributeStore.put_attribute(sensor_id, attribute_id, timestamp, payload)

# Read (auto-tier traversal)
AttributeStore.get_attribute(sensor_id, attribute_id, limit)
AttributeStore.get_attribute(sensor_id, attribute_id, from_ts, to_ts, limit)

# Bulk read
AttributeStore.get_attributes(sensor_id, values_per_attribute)

# Cleanup
AttributeStore.cleanup(sensor_id)
```

## P2P Synchronization (Iroh)

### Integration Points

1. **Room Creation**: Generates Iroh document, stores ticket in Room
2. **Room Sync**: RoomSync GenServer batches/debounces changes
3. **Cross-Device**: Members sync room state via Iroh tickets

### Sync Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Device A  │     │    Iroh     │     │   Device B  │
│  RoomStore  │────▶│   Network   │◀────│  RoomStore  │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       │ 1. Local change   │                   │
       │────────────────────────────────────────
       │                   │                   │
       │ 2. Queue for sync │                   │
       │──────────▶        │                   │
       │                   │                   │
       │ 3. Batch & send   │                   │
       │──────────────────▶│                   │
       │                   │                   │
       │                   │ 4. Propagate      │
       │                   │──────────────────▶│
       │                   │                   │
       │                   │ 5. Apply locally  │
       │                   │                   │
```

### RoomSync Debouncing

```elixir
# Changes are batched over a time window
def handle_cast({:queue_sync, operation}, state) do
  new_state = %{state | pending: [operation | state.pending]}
  schedule_flush_if_needed(new_state)
  {:noreply, new_state}
end

defp schedule_flush_if_needed(state) do
  unless state.flush_scheduled do
    Process.send_after(self(), :flush, @debounce_ms)
  end
end
```

## WebRTC Call Architecture

### Signaling via PubSub

```
┌─────────────┐                           ┌─────────────┐
│   User A    │                           │   User B    │
│  LiveView   │                           │  LiveView   │
└──────┬──────┘                           └──────┬──────┘
       │                                         │
       │ 1. push_event("start_call")             │
       │────────────────────────────────────────▶│
       │                                         │
       │ 2. PubSub: room:{id}:call :peer_joined  │
       │◀────────────────────────────────────────│
       │                                         │
       │ 3. Create offer, push via PubSub        │
       │────────────────────────────────────────▶│
       │                                         │
       │ 4. Create answer, push via PubSub       │
       │◀────────────────────────────────────────│
       │                                         │
       │ 5. Exchange ICE candidates              │
       │◀───────────────────────────────────────▶│
       │                                         │
       │ 6. Direct peer connection established   │
       │◀═══════════════════════════════════════▶│
```

## Telemetry & Monitoring

### Metrics Emitted

```elixir
# Sensor throughput
:telemetry.execute(
  [:sensocto, :sensors, :messages, :mps],
  %{value: messages_per_second},
  %{sensor_id: sensor_id}
)

# Channel metrics
:telemetry.execute(
  [:sensocto, :channel, :join],
  %{count: 1},
  %{device_id: device_id}
)
```

### Recommended Monitoring

- Messages per second (MPS) per sensor
- Active channel connections
- PubSub message queue depth
- ETS table memory usage
- PostgreSQL write latency
- Iroh sync lag
