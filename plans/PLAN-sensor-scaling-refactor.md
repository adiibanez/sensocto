# Sensor Scaling Refactor Plan

**Status: PLANNED**
**Updated: 2026-02-08** (Aligned: pg + local Registry for sensors, NOT Horde)

## Overview

This plan addresses scaling the sensor platform to handle thousands of sensors with varying attention/priority requirements while maintaining data integrity and system responsiveness.

## Current Architecture Issues

### 1. Horde Registry (CRDT-based)
- **Problem**: Eventual consistency causes `:noproc` errors when sensors disconnect
- **Problem**: CRDT sync overhead grows with sensor count (O(n) sync storms)
- **Problem**: Full cluster sync every time any sensor changes

### 2. PubSub Fanout
- **Problem**: All sensor data flows through `data:global` topic
- **Problem**: 1000 sensors × 10 Hz = 10,000 messages/second to ALL subscribers
- **Problem**: No attention-aware routing at source

### 3. ETS Buffer Structure
- **Problem**: Single ETS table for all socket buffers
- **Problem**: Flush iterates all entries, not just relevant ones
- **Problem**: 1000 sensors × 100 viewers × 5 attrs = 500,000 entries

---

## Phase 1: Registry Migration (pg + Local Registry)

### Goals
- Immediate consistency for local lookups
- Eliminate CRDT sync overhead
- Clear ownership model (sensor lives on one node)

### Implementation

```elixir
# New module: Sensocto.SensorRegistry
defmodule Sensocto.SensorRegistry do
  @moduledoc """
  Hybrid sensor registry using local Registry + pg for discovery.

  - Local Registry: Fast O(1) lookup for sensors on this node
  - pg groups: Cross-node discovery (which nodes have which sensors)
  """

  # Register sensor on this node
  def register(sensor_id, pid) do
    # Local registration (instant)
    Registry.register(Sensocto.LocalSensorRegistry, sensor_id, pid)

    # Join pg group for cross-node discovery
    :pg.join(:sensors, {node(), sensor_id}, pid)

    # Broadcast for cache updates
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "discovery:sensors",
      {:sensor_registered, sensor_id, node()})
  end

  # Lookup - check local first, then ask pg
  def whereis(sensor_id) do
    case Registry.lookup(Sensocto.LocalSensorRegistry, sensor_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> whereis_remote(sensor_id)
    end
  end

  defp whereis_remote(sensor_id) do
    case :pg.get_members(:sensors, {node(), sensor_id}) do
      [] -> {:error, :not_found}
      [pid | _] -> {:ok, pid}
    end
  end
end
```

### Migration Steps
1. Add `pg` to application supervision tree
2. Create `Sensocto.LocalSensorRegistry` (standard Registry)
3. Create `Sensocto.SensorRegistry` wrapper module
4. Update `SensorsDynamicSupervisor` to use new registry
5. Update all `SimpleSensor` lookups to use new registry
6. Remove Horde dependency (or keep for other uses)

### Rollback Plan
- Keep Horde running in parallel during migration
- Feature flag to switch between registries
- Monitor error rates before full cutover

---

## Phase 2: Sharded PubSub Topics

### Goals
- Reduce message fanout
- Route data only to interested subscribers
- Enable attention-based topic selection

### Implementation

```elixir
# Topic structure
"data:attention:high"      # Focused/pinned sensors (immediate)
"data:attention:medium"    # In-viewport sensors (batched 50ms)
"data:attention:low"       # Loaded but hidden (batched 200ms)
"data:sensor:{sensor_id}"  # Direct subscription for specific sensor

# In SimpleSensor - route based on attention
defp broadcast_measurement(sensor_id, measurement) do
  attention = AttentionTracker.get_sensor_attention_level(sensor_id)

  topic = case attention do
    :high -> "data:attention:high"
    :medium -> "data:attention:medium"
    :low -> "data:attention:low"
    :none -> nil  # Don't broadcast, buffer locally
  end

  if topic do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, topic,
      {:measurement, sensor_id, measurement})
  end

  # Always broadcast to sensor-specific topic (for direct subscribers)
  Phoenix.PubSub.broadcast(Sensocto.PubSub, "data:sensor:#{sensor_id}",
    {:measurement, measurement})
end
```

### Viewer Subscription Logic
```elixir
# In LobbyLive or PriorityLens
def subscribe_to_attention_levels(socket_id, attention_config) do
  # Subscribe to appropriate topics based on viewer's needs
  if attention_config.wants_high do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
  end
  if attention_config.wants_medium do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
  end
  # Low attention viewers only get batched digests, not raw data
end
```

---

## Phase 3: Sharded ETS Buffers

### Goals
- Isolate viewer state
- O(sensors_watched) flush instead of O(all_entries)
- Clean table deletion on disconnect

### Implementation

```elixir
# Current: Single table
:priority_lens_buffers  # All sockets mixed together

# New: Per-socket tables
:lens_buffer_{socket_id}  # Each socket has own table

defmodule Sensocto.Lenses.SocketBuffer do
  def create(socket_id) do
    table_name = :"lens_buffer_#{socket_id}"
    :ets.new(table_name, [:set, :public, :named_table])
    table_name
  end

  def destroy(socket_id) do
    table_name = :"lens_buffer_#{socket_id}"
    :ets.delete(table_name)
  end

  def put(table_name, sensor_id, attr_id, measurement) do
    :ets.insert(table_name, {{sensor_id, attr_id}, measurement})
  end

  def flush(table_name) do
    # Iterate only this socket's entries
    entries = :ets.tab2list(table_name)
    :ets.delete_all_objects(table_name)
    entries
  end
end
```

---

## Phase 4: Sensor-Side Data Management

### Goals
- Sensors manage their own data lifecycle
- Historical data available on-demand
- Memory-bounded buffers

### Implementation

```elixir
# In SimpleSensor state
defstruct [
  # ... existing fields ...
  :ring_buffer,        # Circular buffer for recent data
  :buffer_size,        # Configurable per sensor type
  :attention_level,    # Current attention (cached)
  :last_broadcast_at,  # For rate limiting
]

# Ring buffer implementation
defmodule Sensocto.RingBuffer do
  defstruct [:size, :data, :index]

  def new(size), do: %__MODULE__{size: size, data: :array.new(size), index: 0}

  def push(%{size: size, data: data, index: idx} = buffer, item) do
    new_idx = rem(idx + 1, size)
    new_data = :array.set(idx, item, data)
    %{buffer | data: new_data, index: new_idx}
  end

  def get_range(buffer, from_timestamp, to_timestamp) do
    # Return items in time range
  end

  def get_latest(buffer, count) do
    # Return most recent N items
  end
end
```

### On-Demand Data Fetch
```elixir
# When viewer requests historical data
def handle_call({:get_buffered_data, from, to}, _from, state) do
  data = RingBuffer.get_range(state.ring_buffer, from, to)
  {:reply, {:ok, data}, state}
end

# When attention increases (viewer shows up)
def handle_info({:attention_changed, :none, :high}, state) do
  # Start broadcasting immediately
  {:noreply, %{state | attention_level: :high}}
end
```

---

## Phase 5: Attention-Aware Routing Architecture

### Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Sensor Processes                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│  │Sensor 1 │ │Sensor 2 │ │Sensor 3 │ │Sensor N │               │
│  │ Buffer  │ │ Buffer  │ │ Buffer  │ │ Buffer  │               │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘               │
│       │attention   │attention  │attention  │no attention        │
│       │= high      │= medium   │= low      │(buffer only)       │
└───────┼────────────┼───────────┼───────────┼────────────────────┘
        │            │           │           │
        ▼            ▼           ▼           X (no broadcast)
┌─────────────────────────────────────────────────────────────────┐
│                    Attention Router                              │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐      │
│  │ High Priority  │ │ Medium Priority│ │ Low Priority   │      │
│  │ Immediate      │ │ 50ms batch     │ │ 200ms batch    │      │
│  └───────┬────────┘ └───────┬────────┘ └───────┬────────┘      │
└──────────┼──────────────────┼──────────────────┼────────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                Per-Viewer Lens (Sharded ETS)                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Viewer 1 ETS │ │ Viewer 2 ETS │ │ Viewer N ETS │             │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LiveView Rendering                            │
│  - Virtual scrolling (existing)                                  │
│  - Attention-based render throttling                            │
│  - Incremental updates                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Priority

| Phase | Effort | Impact | Dependencies |
|-------|--------|--------|--------------|
| Quick Wins (done separately) | Low | Medium | None |
| Phase 1: Registry Migration | Medium | High | None |
| Phase 2: Sharded Topics | Medium | High | Phase 1 |
| Phase 3: Sharded ETS | Low | Medium | None |
| Phase 4: Sensor Buffering | Medium | High | None |
| Phase 5: Full Architecture | High | Very High | Phases 1-4 |

## Metrics to Track

- Messages/second through PubSub
- ETS table sizes
- LiveView render times
- Memory usage per sensor
- Latency from sensor emit to viewer display
- Registry lookup times

## Rollback Strategy

Each phase should be:
1. Feature-flagged
2. Deployable independently
3. Reversible without data loss
4. Monitored with metrics

---

## Notes

- Keep Horde for other distributed state (rooms, whiteboards) if needed
- Consider pg2 replacement if targeting OTP 23+ (pg is the successor)
- Test with realistic load (1000+ simulated sensors) before production
