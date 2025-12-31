# Scalability Guide

This document analyzes the scalability characteristics of Sensocto's attention tracking system and provides recommendations for high-scale deployments.

## Attention Tracking System Architecture

The attention tracking system (`Sensocto.AttentionTracker`) manages user attention state across sensors and attributes to enable back-pressure control for data transmission rates.

### Core Components

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  JS Hook        │────▶│  LiveView        │────▶│  AttentionTracker│
│  (Browser)      │     │  (per user)      │     │  (GenServer)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                                 ┌─────────────────┐
                                                 │  ETS Tables     │
                                                 │  (concurrent    │
                                                 │   reads)        │
                                                 └─────────────────┘
```

### Data Flow

1. **Browser** → JS hooks detect hover/focus/view events
2. **LiveView** → Each user's socket handles events and calls AttentionTracker
3. **GenServer** → Single process manages all attention state, writes to ETS
4. **ETS** → Provides lock-free concurrent reads for attention levels

## Multi-User Readiness Assessment

### Strengths

| Feature | Implementation | Benefit |
|---------|---------------|---------|
| **ETS Concurrent Reads** | `read_concurrency: true` on ETS tables | Reads bypass GenServer, no bottleneck |
| **Async Writes** | All mutations use `GenServer.cast` | Users don't block waiting for state updates |
| **User Isolation** | `MapSet` tracks each `user_id` separately | Clean per-user state management |
| **Aggregated Attention** | Highest level wins across all users | Fair resource allocation |
| **Automatic Cleanup** | 30-second cleanup cycle, 60-second stale threshold | Prevents memory leaks |
| **Disconnect Handling** | `unregister_all/2` on LiveView terminate | Clean user departure |

### Architecture Details

#### ETS Tables (Fast Reads)

```elixir
# Created in AttentionTracker.init/1
:ets.new(:attention_levels_cache, [:named_table, :public, read_concurrency: true])
:ets.new(:attention_config_cache, [:named_table, :public, read_concurrency: true])
```

The `get_attention_level/2` function reads directly from ETS:

```elixir
def get_attention_level(sensor_id, attribute_id) do
  case :ets.lookup(@attention_levels_table, {sensor_id, attribute_id}) do
    [{_, level}] -> level
    [] -> :none
  end
end
```

This means sensor data batchers querying attention levels don't contend with the GenServer.

#### Async Writes (Non-Blocking)

All state modifications use `cast`:

```elixir
def register_hover(sensor_id, attribute_id, user_id) do
  GenServer.cast(__MODULE__, {:register_hover, sensor_id, attribute_id, user_id})
end
```

Users experience no latency from attention tracking - events are fire-and-forget.

#### Aggregated Attention Levels

Attention is tracked per-user but aggregated for resource allocation:

```elixir
# State structure per attribute
%{
  viewers: MapSet<user_id>,   # Users with attribute in viewport
  hovered: MapSet<user_id>,   # Users hovering over attribute
  focused: MapSet<user_id>,   # Users who clicked/focused attribute
  last_updated: DateTime
}

# Attention level calculation
cond do
  MapSet.size(focused) > 0 -> :high
  MapSet.size(hovered) > 0 -> :high
  MapSet.size(viewers) > 0 -> :medium
  true -> :low
end
```

If **any** user hovers or focuses, the attribute gets `:high` attention (fast updates).

## Scaling Characteristics

### Current Limits

| Metric | Estimated Capacity | Notes |
|--------|-------------------|-------|
| Concurrent users | 100-500 | Single GenServer handles well |
| Sensors | 1000+ | ETS scales linearly |
| Attributes per sensor | 50+ | No practical limit |
| Events/second | 1000+ | Async casts queue efficiently |

### Potential Bottlenecks

#### 1. Single GenServer Process

All write operations go through one Erlang process. With thousands of concurrent users generating rapid events, this could become a bottleneck.

**Symptoms:**
- GenServer message queue growing
- Delayed attention level updates
- Increased memory usage

**Monitoring:**
```elixir
# Check GenServer mailbox size
{:message_queue_len, len} = Process.info(Process.whereis(Sensocto.AttentionTracker), :message_queue_len)
```

#### 2. State Size Growth

The `attention_state` map grows with: `sensors × attributes × active_users`

For example:
- 100 sensors × 5 attributes × 1000 users = potentially 500K MapSet entries

**Monitoring:**
```elixir
# Check state size
state = Sensocto.AttentionTracker.get_state()
:erts_debug.size(state.attention_state) * :erlang.system_info(:wordsize)
```

#### 3. PubSub Broadcast Storm

Every attention level change broadcasts via PubSub. Rapid hover events could create message storms.

**Mitigations already in place:**
- JS-side adaptive debouncing (50-500ms based on system load)
- 2-second hover boost duration prevents rapid leave/enter events

## Recommendations for High Scale

### Tier 1: 100-500 Concurrent Users

**Current architecture is sufficient.** Monitor these metrics:

```elixir
# Add to your monitoring/dashboard
defmodule Sensocto.AttentionMetrics do
  def collect do
    %{
      genserver_mailbox: get_mailbox_size(),
      ets_table_size: :ets.info(:attention_levels_cache, :size),
      active_sensors: count_active_sensors(),
      memory_bytes: :erlang.memory(:total)
    }
  end

  defp get_mailbox_size do
    case Process.whereis(Sensocto.AttentionTracker) do
      nil -> 0
      pid ->
        {:message_queue_len, len} = Process.info(pid, :message_queue_len)
        len
    end
  end

  defp count_active_sensors do
    Sensocto.AttentionTracker.get_state()
    |> Map.get(:attention_state, %{})
    |> map_size()
  end
end
```

### Tier 2: 500-2000 Concurrent Users

Consider these enhancements:

#### A. Server-Side Debouncing

Add debouncing in the GenServer to coalesce rapid events:

```elixir
# Example: batch ETS updates every 100ms instead of per-event
def handle_cast({:register_hover, sensor_id, attribute_id, user_id}, state) do
  # Queue the update
  new_state = queue_attention_update(state, sensor_id, attribute_id, user_id, :add_hover)
  # Actual ETS update happens in periodic flush
  {:noreply, new_state}
end

def handle_info(:flush_attention_updates, state) do
  # Batch update ETS and broadcast
  schedule_flush()
  {:noreply, apply_queued_updates(state)}
end
```

#### B. Rate-Limited Broadcasts

```elixir
# Throttle broadcasts per sensor
defp maybe_broadcast_change(old_state, new_state, sensor_id, attribute_id) do
  # Only broadcast if not recently broadcast for this sensor
  if can_broadcast?(sensor_id) do
    do_broadcast(...)
    record_broadcast(sensor_id)
  end
end
```

### Tier 3: 2000+ Concurrent Users

For very high scale, consider architectural changes:

#### A. Shard by Sensor

Split the single GenServer into multiple processes:

```elixir
defmodule Sensocto.AttentionTrackerSupervisor do
  use DynamicSupervisor

  def get_tracker(sensor_id) do
    # Consistent hash to determine which tracker process
    shard = :erlang.phash2(sensor_id, @num_shards)
    {:via, Registry, {AttentionTrackerRegistry, shard}}
  end
end
```

#### B. Use CRDTs for Distributed State

For multi-node deployments, consider CRDTs (Conflict-free Replicated Data Types):

```elixir
# Each node maintains local state, merged periodically
# Libraries: DeltaCrdt, Horde
```

#### C. Move to External Store

For extreme scale, consider Redis or similar:

```elixir
# Pros: Horizontal scaling, persistence
# Cons: Network latency, operational complexity
```

## Performance Tuning

### BEAM VM Flags

See `docs/beam-vm-tuning.md` for comprehensive BEAM tuning. Key flags for attention tracking:

```bash
# High-performance mode for attention-heavy workloads
ERL_FLAGS="+A 128 +SDio 128 +K true +sbwt very_short"
```

| Flag | Value | Purpose |
|------|-------|---------|
| `+A 128` | 128 async threads | Handle ETS operations efficiently |
| `+SDio 128` | 128 dirty IO schedulers | PubSub broadcasts |
| `+K true` | Kernel poll | Efficient network IO |
| `+sbwt very_short` | Scheduler busy wait | Low-latency response |

### Client-Side Tuning

The JS hook uses adaptive debouncing based on measured latency:

```javascript
// In attention_tracker.js
const HOVER_DEBOUNCE_MIN_MS = 50;   // Fast systems
const HOVER_DEBOUNCE_MAX_MS = 500;  // Loaded systems
const HOVER_BOOST_DURATION_MS = 2000; // Prevents flicker

function getAdaptiveDebounce() {
  const avgLatency = eventLatencies.reduce((a, b) => a + b, 0) / eventLatencies.length;
  return Math.min(HOVER_DEBOUNCE_MAX_MS, Math.max(HOVER_DEBOUNCE_MIN_MS, avgLatency * 2));
}
```

Adjust these constants based on your deployment:

| Scenario | MIN_MS | MAX_MS | BOOST_MS |
|----------|--------|--------|----------|
| Low latency LAN | 30 | 200 | 1000 |
| Standard web | 50 | 500 | 2000 |
| High latency/mobile | 100 | 1000 | 3000 |

## Monitoring Checklist

### Essential Metrics

```elixir
# 1. GenServer health
Process.info(Process.whereis(Sensocto.AttentionTracker), :message_queue_len)

# 2. ETS table size
:ets.info(:attention_levels_cache, :size)

# 3. Memory usage
:erlang.memory()

# 4. Active sensors/attributes
state = Sensocto.AttentionTracker.get_state()
Enum.sum(for {_, attrs} <- state.attention_state, do: map_size(attrs))

# 5. Scheduler utilization
:scheduler.utilization(1000)
```

### Warning Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| GenServer mailbox | > 100 | > 1000 |
| ETS entries | > 10,000 | > 50,000 |
| Memory (total) | > 2GB | > 4GB |
| Scheduler util | > 70% | > 90% |

## Summary

| Scale | Users | Architecture | Changes Needed |
|-------|-------|--------------|----------------|
| Small | 1-100 | Current | None |
| Medium | 100-500 | Current | Monitoring |
| Large | 500-2000 | Enhanced | Server-side debouncing |
| Very Large | 2000+ | Sharded | GenServer sharding or external store |

The current implementation is **production-ready for typical deployments** (up to ~500 concurrent users). The ETS-based read path and async writes provide solid concurrent access patterns. For larger deployments, implement the tiered recommendations above.
