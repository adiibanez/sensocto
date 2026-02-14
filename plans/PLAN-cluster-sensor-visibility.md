# Cluster-Wide Sensor Visibility Plan

**Status: PLANNED**
**Created: 2026-01-31**
**Updated: 2026-02-08** (Aligned with sensor-scaling-refactor: pg + local Registry, NOT Horde)
**Priority: HIGH**

## Problem Statement

In a clustered Fly.io deployment with multiple nodes, sensors are only visible on the node they're connected to. When a user joins on a different server, they only see sensors connected to that specific node, not all sensors across the cluster.

## Architecture Decision: pg + Local Registry (NOT Horde)

**Decision**: Use Erlang's `:pg` for cross-node discovery + local `Registry` for fast lookups.

**Why NOT Horde for sensors:**
- Horde uses CRDT-based sync → O(n) sync storms with thousands of sensors
- Eventual consistency causes `:noproc` errors when sensors disconnect
- Full cluster sync every time any sensor changes state
- Sensors are high-churn (connect/disconnect frequently) unlike rooms (long-lived)

**Why pg + local Registry:**
- Local Registry gives instant O(1) lookups for sensors on this node
- `:pg` groups provide lightweight cross-node discovery (built into OTP)
- No CRDT overhead — `:pg` uses direct messaging
- Clear ownership model: sensor lives on one node, period
- Already proven: `ConnectorManager` uses `:pg` successfully

**Horde stays for rooms** (low-churn, long-lived, need process handoff on node failure).

See `plans/PLAN-sensor-scaling-refactor.md` for the full implementation design.

## Current Architecture (Local-Only)

```
┌─────────────────────────────────────────────────────────────────┐
│                         NODE A (Fly.io)                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ SimpleSensorRegistry (local Registry)                       ││
│  │   sensor_1 -> PID<0.123.0>                                  ││
│  │   sensor_2 -> PID<0.124.0>                                  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         NODE B (Fly.io)                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ SimpleSensorRegistry (local Registry)                       ││
│  │   sensor_3 -> PID<0.456.0>  (DIFFERENT REGISTRY!)           ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘

User on Node B only sees sensor_3, not sensor_1 or sensor_2!
```

### What's Already Cluster-Aware

1. **Phoenix.Presence** - Uses PubSub for CRDT-based presence tracking
2. **Phoenix.PubSub** - Broadcasts to all nodes via `Phoenix.PubSub.PG2`
3. **RoomServer** - Uses `Horde.Registry` for distributed room lookup
4. **RoomsDynamicSupervisor** - Uses `Horde.DynamicSupervisor`
5. **ConnectorManager** - Uses `:pg` process groups

## Implementation: pg + Local Registry

### New Module: Sensocto.SensorRegistry

```elixir
defmodule Sensocto.SensorRegistry do
  @moduledoc """
  Hybrid sensor registry using local Registry + pg for discovery.

  - Local Registry: Fast O(1) lookup for sensors on this node
  - pg groups: Cross-node discovery (which nodes have which sensors)
  """

  def register(sensor_id, pid) do
    # Local registration (instant)
    Registry.register(Sensocto.LocalSensorRegistry, sensor_id, pid)

    # Join pg group for cross-node discovery
    :pg.join(:sensors, {node(), sensor_id}, pid)

    # Broadcast for cache updates on other nodes
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "discovery:sensors",
      {:sensor_registered, sensor_id, node()})
  end

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

  def get_all_sensor_ids do
    # Local sensors
    local = Registry.select(Sensocto.LocalSensorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

    # Remote sensors via pg
    remote = :pg.which_groups(:sensors)
      |> Enum.map(fn {_node, sensor_id} -> sensor_id end)

    Enum.uniq(local ++ remote)
  end
end
```

### Migration Steps

1. Add `:pg` scope to application supervision tree
2. Create `Sensocto.LocalSensorRegistry` (standard Registry)
3. Create `Sensocto.SensorRegistry` wrapper module
4. Update `SensorsDynamicSupervisor` to use new registry
5. Update all `SimpleSensor` lookups to use new registry
6. Update `LobbyLive` to fetch sensors from cluster

### Files to Modify

| File | Change |
|------|--------|
| `lib/sensocto/registry/supervisor.ex` | Add LocalSensorRegistry, add :pg scope |
| `lib/sensocto/otp/simple_sensor.ex` | Update `via_tuple` to use new registry |
| `lib/sensocto/otp/sensors_dynamic_supervisor.ex` | Update `get_device_names/0` |
| `lib/sensocto_web/live/lobby_live.ex` | Fetch sensors from cluster |

### Rollback Plan

- Keep local Registry running in parallel during migration
- Feature flag to switch between old and new registry
- Monitor error rates before full cutover

## Testing Strategy

### Local Multi-Node Testing

```bash
# Terminal 1 - Node A
iex --sname a -S mix phx.server

# Terminal 2 - Node B
iex --sname b -S mix

# In node B IEx:
Node.connect(:"a@hostname")
```

## Dependencies

- `:pg` - Built into OTP (no external dep)
- `libcluster` - For Fly.io node discovery

## Related Plans

- `plans/PLAN-sensor-scaling-refactor.md` - Full implementation design (pg + sharded PubSub + sharded ETS)
- `plans/PLAN-distributed-discovery.md` - Higher-level discovery service (depends on this)

## Success Criteria

1. User on Node A sees sensors connected to Node B
2. User on Node B sees sensors connected to Node A
3. Real-time data flows correctly across nodes
4. No CRDT sync overhead for sensor registry
5. No significant latency increase for local sensors
