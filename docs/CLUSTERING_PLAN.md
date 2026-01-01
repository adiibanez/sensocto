# Sensocto Clustering Implementation Plan

> Saved: 2026-01-01 | Resume this plan later with Claude Code

## Executive Summary

Make the Sensocto sensor platform clustering-ready with a **resilient demo** focus: killing nodes should have minimal impact on user experience. Target 100s of nodes now, architecture supports 1000s later.

**Primary Goal**: Demonstrate fault tolerance by surviving node failures gracefully.

---

## User Requirements

| Requirement | Choice | Notes |
|-------------|--------|-------|
| Deployment | Fly.io (now), on-premise (later) | Use libcluster with Fly DNS |
| Video calls | Reconnection OK (Option B) | Simpler, outsource later |
| Sensor data | ETS + replication | Not full DB persistence |
| Temporary rooms | Accept loss | No extra complexity |
| Scale target | 100s now, 1000s later | PG2 sufficient to start |

---

## Current State Analysis

### What's Already In Place (Good News)
- **Horde** dependency exists in mix.exs (not activated)
- **DNSCluster** configured (set to `:ignore`)
- **RegistryUtils** abstraction layer for switching between Registry/Horde
- **Phoenix.Presence** already cluster-aware
- **PostgreSQL** for durable state (rooms, sensors, users)

### What Needs Distribution
| Component | Current State | Cluster Impact |
|-----------|--------------|----------------|
| 9 Registries | Local Elixir Registry | Process lookup fails cross-node |
| 3 DynamicSupervisors | Local supervisors | Processes can't failover |
| PubSub | Default in-memory | Messages don't cross nodes |
| ETS Caches | Node-local | Need replication for sensor data |
| RoomServer | In-memory GenServer | State lost on node failure |
| SimpleSensor | In-memory GenServer | Reconnect rebuilds state |

---

## Implementation Plan (Low-Hanging Fruits First)

### Phase 1: Cluster Foundation ⭐ (Start Here)

**Goal**: Nodes discover each other, PubSub works across nodes

**Demo Impact**: Messages broadcast to all connected clients regardless of which node they're on.

1. **Enable libcluster** (`mix.exs:79`)
   ```elixir
   {:libcluster, "~> 3.3"},  # Uncomment this line
   ```

2. **Configure Fly.io cluster topology** (`config/runtime.exs`)
   ```elixir
   config :libcluster,
     topologies: [
       fly: [
         strategy: Cluster.Strategy.DNSPoll,
         config: [
           query: System.get_env("FLY_APP_NAME", "sensocto") <> ".internal",
           node_basename: System.get_env("FLY_APP_NAME", "sensocto"),
           poll_interval: 5_000
         ]
       ]
     ]
   ```

3. **Start Cluster.Supervisor** (`application.ex:58`)
   ```elixir
   {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: Sensocto.ClusterSupervisor]]},
   ```

4. **Configure PubSub PG2 adapter** (`config/config.exs`)
   ```elixir
   config :sensocto, Sensocto.PubSub,
     adapter: Phoenix.PubSub.PG2,
     pool_size: 10
   ```

**Files to modify**:
- `mix.exs` (line 79)
- `config/runtime.exs`
- `config/config.exs`
- `lib/sensocto/application.ex` (line 58)

**Verification**:
```bash
# Local testing with 2 nodes
PORT=4000 iex --sname a -S mix phx.server
PORT=4001 iex --sname b -S mix
# On node b:
Node.connect(:"a@$(hostname)")
Node.list()  # Should show [:a@hostname]
```

---

### Phase 2: Distributed Registry Migration ⭐

**Goal**: Processes can be found from any node, auto-failover on node death

**Demo Impact**: Kill a node → processes restart on surviving nodes automatically.

1. **Replace Registry with Horde.Registry** (`application.ex:36-45`)

   ```elixir
   # Replace these 6 registries:
   {Horde.Registry, [keys: :unique, name: Sensocto.SimpleSensorRegistry, members: :auto]},
   {Horde.Registry, [keys: :unique, name: Sensocto.SimpleAttributeRegistry, members: :auto]},
   {Horde.Registry, [keys: :unique, name: Sensocto.SensorPairRegistry, members: :auto]},
   {Horde.Registry, [keys: :unique, name: Sensocto.RoomRegistry, members: :auto]},
   {Horde.Registry, [keys: :unique, name: Sensocto.RoomJoinCodeRegistry, members: :auto]},
   {Horde.Registry, [keys: :unique, name: Sensocto.CallRegistry, members: :auto]},
   ```

2. **Update via_tuple functions** in each GenServer:

   `room_server.ex:36-38`:
   ```elixir
   def via_tuple(room_id) do
     {:via, Horde.Registry, {Sensocto.RoomRegistry, room_id}}
   end
   ```

   `simple_sensor.ex` (similar pattern):
   ```elixir
   def via_tuple(sensor_id) do
     {:via, Horde.Registry, {Sensocto.SimpleSensorRegistry, sensor_id}}
   end
   ```

3. **Replace DynamicSupervisors with Horde** (`application.ex:70-72`)

   ```elixir
   # Replace SensorsDynamicSupervisor initialization
   {Horde.DynamicSupervisor, [
     name: Sensocto.SensorsDynamicSupervisor,
     strategy: :one_for_one,
     distribution_strategy: Horde.UniformDistribution,
     members: :auto
   ]},

   # Similar for RoomsDynamicSupervisor
   {Horde.DynamicSupervisor, [
     name: Sensocto.RoomsDynamicSupervisor,
     strategy: :one_for_one,
     distribution_strategy: Horde.UniformDistribution,
     members: :auto
   ]},
   ```

4. **Update supervisor modules** to use Horde API:

   `sensors_dynamic_supervisor.ex`:
   ```elixir
   # Change: DynamicSupervisor.start_child(...)
   # To:     Horde.DynamicSupervisor.start_child(...)
   ```

**Files to modify**:
- `lib/sensocto/application.ex`
- `lib/sensocto/otp/room_server.ex` (via_tuple)
- `lib/sensocto/otp/simple_sensor.ex` (via_tuple)
- `lib/sensocto/otp/attribute_store.ex` (via_tuple)
- `lib/sensocto/otp/sensors_dynamic_supervisor.ex` (use Horde API)
- `lib/sensocto/otp/rooms_dynamic_supervisor.ex` (use Horde API)
- `lib/sensocto/calls/call_server.ex` (via_tuple)

**Verification**:
```elixir
# Create room on node A
{:ok, room_id, _} = Sensocto.RoomsDynamicSupervisor.create_room(owner_id: "test", name: "Test")

# Access from node B
Sensocto.RoomServer.get_state(room_id)  # Works cross-node!

# Kill node A (Ctrl+C twice) → Room restarts on node B
```

---

### Phase 3: Sensor Data Replication (ETS + PubSub)

**Goal**: Sensor data (AttributeStore) replicated across nodes via ETS + PubSub

**Demo Impact**: Sensor data visible from any node, survives single node failure.

**Approach**: Use `delta_crdt` (already in deps) for distributed ETS-like storage.

1. **Create distributed sensor data store** (`lib/sensocto/otp/distributed_attribute_store.ex`):

   ```elixir
   defmodule Sensocto.DistributedAttributeStore do
     @moduledoc """
     Distributed sensor attribute storage using DeltaCRDT.
     Replicates latest N measurements across cluster.
     """
     use GenServer

     @max_entries_per_attribute 1000  # Reduced from 10K for replication
     @sync_interval :timer.seconds(5)

     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: __MODULE__)
     end

     def init(_opts) do
       # Create CRDT for sensor data
       {:ok, crdt} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap)

       # Join cluster CRDTs
       for node <- Node.list() do
         DeltaCrdt.set_neighbours(crdt, [{__MODULE__, node}])
       end

       # Monitor cluster changes
       :net_kernel.monitor_nodes(true)

       schedule_sync()
       {:ok, %{crdt: crdt}}
     end

     def put_measurement(sensor_id, attr_id, timestamp, payload) do
       GenServer.cast(__MODULE__, {:put, sensor_id, attr_id, timestamp, payload})
     end

     def get_measurements(sensor_id, attr_id, limit \\ 100) do
       GenServer.call(__MODULE__, {:get, sensor_id, attr_id, limit})
     end

     # ... handle_cast/call implementations
   end
   ```

2. **Update AttributeStore to delegate to distributed store**:

   ```elixir
   # In attribute_store.ex - add delegation for recent data
   def put_attribute(sensor_id, attr_id, timestamp, payload) do
     # Local storage (fast)
     Agent.update(via_tuple(sensor_id), ...)

     # Also replicate to distributed store (async)
     Sensocto.DistributedAttributeStore.put_measurement(sensor_id, attr_id, timestamp, payload)
   end
   ```

3. **Alternative: Simpler PubSub-based replication**

   If DeltaCRDT feels heavy, use PubSub for real-time sync:

   ```elixir
   # Each node subscribes to sensor data
   Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

   # On receive, store locally
   def handle_info({:measurement, data}, state) do
     AttributeStore.put_attribute(data.sensor_id, data.attr_id, data.timestamp, data.payload)
     {:noreply, state}
   end
   ```

   This is already partially implemented - just ensure all nodes subscribe.

**Files to modify**:
- `lib/sensocto/otp/distributed_attribute_store.ex` (new file)
- `lib/sensocto/otp/attribute_store.ex` (add delegation)
- `lib/sensocto/application.ex` (add to supervision tree)

**Recommendation**: Start with PubSub-based replication (simpler). Add DeltaCRDT later if needed.

---

### Phase 4: Graceful Client Reconnection

**Goal**: Clients (sensors, browsers) seamlessly reconnect when their node dies

**Demo Impact**: Kill a node → clients automatically reconnect to another node.

1. **WebSocket channel reconnection** (`sensor_data_channel.ex`):

   ```elixir
   # Monitor sensor process
   def join("sensocto:sensor:" <> sensor_id, params, socket) do
     # ... existing join logic ...

     # Monitor the sensor GenServer
     case Horde.Registry.lookup(Sensocto.SimpleSensorRegistry, sensor_id) do
       [{pid, _}] -> Process.monitor(pid)
       [] -> :ok
     end

     {:ok, socket}
   end

   # Handle sensor process death (node failure)
   def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
     # Tell client to reconnect - they'll hit another node
     push(socket, "control", %{action: "reconnect", delay_ms: 1000})
     {:stop, :normal, socket}
   end
   ```

2. **LiveView reconnection** (already handled by Phoenix):
   - LiveView sockets auto-reconnect on disconnect
   - State rebuilt from assigns on reconnect
   - No changes needed - this works out of the box

3. **Load balancer sticky sessions** (Fly.io):
   ```toml
   # fly.toml - disable sticky sessions for failover
   [http_service]
     force_https = true
     auto_stop_machines = false
     auto_start_machines = true
     [http_service.concurrency]
       type = "connections"
       soft_limit = 1000
       hard_limit = 2500
   ```

**Files to modify**:
- `lib/sensocto_web/channels/sensor_data_channel.ex`
- `fly.toml` (deployment config)

---

### Phase 5: ETS Caches (Keep Local - No Changes)

**Goal**: Confirm attention/load caches can stay node-local

| Cache | Keep Local? | Reason |
|-------|-------------|--------|
| `attention_levels_cache` | ✅ Yes | Per-user attention, eventual consistency OK |
| `attention_config_cache` | ✅ Yes | Static config, same everywhere |
| `sensor_attention_cache` | ✅ Yes | Aggregated per-node |
| `system_load_cache` | ✅ Yes | Node-specific metrics |

**No changes needed** - these caches work correctly with eventual consistency.

---

## Architecture Decisions Summary

### Is PubSub Enough?

**Yes for most data, enhanced with Horde for process state:**

| Data Type | Strategy | Why |
|-----------|----------|-----|
| Sensor measurements | PubSub | Ephemeral, resent on reconnect |
| Sensor data history | PubSub → local ETS | Each node stores what it receives |
| Room state | Horde failover | Restart on surviving node |
| Call state | Horde + reconnect | Participants rejoin on failover |

### Room Server Groups (Future)

**For demo: Single owner via Horde is sufficient.**

Master/standby pattern can be added later for:
- Rooms with active video/voice calls
- Rooms with > 10 members
- Explicit "high availability" flag

---

## Implementation Priority (Demo Focus)

| Priority | Phase | Effort | Demo Value |
|----------|-------|--------|------------|
| 1️⃣ | Phase 1: Cluster Foundation | ~2 hours | PubSub works cross-node |
| 2️⃣ | Phase 2: Distributed Registry | ~4 hours | Processes survive node death |
| 3️⃣ | Phase 4: Client Reconnection | ~1 hour | Seamless failover UX |
| 4️⃣ | Phase 3: Data Replication | ~3 hours | Data visible everywhere |
| ⏸️ | Phase 5: ETS Caches | 0 | No changes needed |

**Total estimated effort: ~10 hours for resilient demo**

---

## Critical Files Summary

| File | Changes |
|------|---------|
| `mix.exs:79` | Uncomment libcluster |
| `config/runtime.exs` | Add libcluster Fly topology |
| `config/config.exs` | Configure PubSub PG2 adapter |
| `lib/sensocto/application.ex` | Replace Registry → Horde, add Cluster.Supervisor |
| `lib/sensocto/otp/room_server.ex:36-38` | Update via_tuple to Horde |
| `lib/sensocto/otp/simple_sensor.ex` | Update via_tuple to Horde |
| `lib/sensocto/otp/attribute_store.ex` | Update via_tuple to Horde |
| `lib/sensocto/otp/sensors_dynamic_supervisor.ex` | Use Horde.DynamicSupervisor |
| `lib/sensocto/otp/rooms_dynamic_supervisor.ex` | Use Horde.DynamicSupervisor |
| `lib/sensocto/calls/call_server.ex` | Update via_tuple to Horde |
| `lib/sensocto_web/channels/sensor_data_channel.ex` | Add process monitoring + reconnect |

---

## Demo Script: Killing Nodes

```bash
# Terminal 1: Start node A
PORT=4000 iex --sname a -S mix phx.server

# Terminal 2: Start node B
PORT=4001 iex --sname b -S mix phx.server

# Terminal 3: Connect nodes
iex --sname admin
Node.connect(:"a@$(hostname)")
Node.connect(:"b@$(hostname)")
Node.list()  # Should show both nodes

# Open browser to http://localhost:4000
# Create sensors, rooms, etc.

# Kill node A (Ctrl+C twice in Terminal 1)
# Watch: sensors and rooms restart on node B
# Watch: browser reconnects automatically
# Experience: minimal disruption
```

---

## Future Scaling Path

| Scale | Solution |
|-------|----------|
| 2-10 nodes | This plan (Horde + PG2) |
| 10-100 nodes | Add Redis PubSub adapter |
| 100-1000 nodes | Partition by room/region |
| 1000+ nodes | P2P architecture (future) |

---

## Answers to Your Questions

1. **Is PubSub enough?** → Yes for data streams. Horde provides process-level state failover.

2. **Master/standby rooms?** → Not needed for demo. Horde single-owner with auto-restart is sufficient. Add later for calls.

3. **How to scale further?** → This plan handles 100s of nodes. Add Redis PubSub for 1000s. P2P is the long-term path.
