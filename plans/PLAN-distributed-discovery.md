# Distributed User/Room/Sensor Discovery System

**Status: PLANNED**
**Created: 2026-01-31**
**Updated: 2026-02-08** (Aligned: pg + local Registry for sensors, NOT Horde)
**Priority: HIGH**
**Dependencies: PLAN-cluster-sensor-visibility.md**

## Problem Statement

The system needs a solid distributed discovery mechanism so that:
1. All nodes can show their view of the "world" (users, rooms, sensors) to connected clients
2. Information distributes without breaking stability/performance
3. A slow client/node does NOT slow down others
4. The system maintains consistency while tolerating partial failures

## Current State Analysis

### Already Distributed (Working)
| Component | Technology | Notes |
|-----------|------------|-------|
| **Rooms** | Horde.Registry + Horde.DynamicSupervisor | Full cluster-wide visibility |
| **Connectors** | :pg groups + PubSub | Cluster-wide discovery via `ConnectorManager` |
| **Presence** | Phoenix.Presence (CRDT) | Cluster-aware real-time tracking |
| **PubSub** | Phoenix.PubSub (PG2) | All broadcasts reach all nodes |

### Not Distributed (Gap)
| Component | Current | Issue |
|-----------|---------|-------|
| **SimpleSensorRegistry** | Local `Registry` | Each node has separate registry |
| **SensorsDynamicSupervisor** | Local `DynamicSupervisor` | Only manages local sensors |
| **SimpleAttributeRegistry** | Local `Registry` | Attribute stores are node-local |

## Architecture Design

### Core Principles

1. **Isolation**: Slow nodes/clients must not block others
2. **Graceful Degradation**: Show what's available, don't fail completely
3. **Eventual Consistency**: Use CRDTs where possible
4. **Backpressure**: Push back on overloaded components
5. **Node Affinity**: Keep sensor processes on their original node

### Discovery Service Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DISTRIBUTED DISCOVERY SERVICE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Layer 1: ENTITY REGISTRIES                                      │   │
│  │                                                                   │   │
│  │  SensorRegistry (pg + local Registry -- NOT Horde)               │   │
│  │    ├── sensor_1 → {PID on node_a, metadata}  (local Registry)   │   │
│  │    ├── sensor_2 → {PID on node_b, metadata}  (pg discovery)     │   │
│  │    └── sensor_3 → {PID on node_a, metadata}  (local Registry)   │   │
│  │                                                                   │   │
│  │  RoomRegistry (Horde -- stays, rooms are low-churn)              │   │
│  │  ConnectorRegistry (:pg -- already works)                        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              ↓                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Layer 2: DISCOVERY CACHE (per-node, eventually consistent)      │   │
│  │                                                                   │   │
│  │  DiscoveryCache (ETS + CRDT sync)                                │   │
│  │    ├── sensors: %{id => view_state}    ← Updated via PubSub     │   │
│  │    ├── rooms: %{id => view_state}      ← Updated via PubSub     │   │
│  │    ├── users: %{id => presence_info}   ← From Phoenix.Presence  │   │
│  │    └── last_sync: timestamp                                      │   │
│  │                                                                   │   │
│  │  Benefits:                                                        │   │
│  │    - Fast local reads (no cross-node calls for listing)          │   │
│  │    - Stale data preferred over blocking                          │   │
│  │    - Each node has complete world view                           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              ↓                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Layer 3: DISCOVERY API (client-facing)                          │   │
│  │                                                                   │   │
│  │  Discovery.list_sensors(opts)   → Fast ETS read                  │   │
│  │  Discovery.list_rooms(opts)     → Fast ETS read                  │   │
│  │  Discovery.list_users(opts)     → Presence.list()                │   │
│  │                                                                   │   │
│  │  Discovery.get_sensor_state(id) → Try cache, fallback to PID     │   │
│  │  Discovery.subscribe(entity)    → PubSub subscription            │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              ↓                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Layer 4: SYNC MECHANISM (background, non-blocking)              │   │
│  │                                                                   │   │
│  │  DiscoverySyncWorker                                             │   │
│  │    ├── Subscribes to "discovery:*" PubSub topics                 │   │
│  │    ├── Receives entity create/update/delete events               │   │
│  │    ├── Updates local ETS cache                                   │   │
│  │    └── Periodic full sync (safety net, every 30s)                │   │
│  │                                                                   │   │
│  │  Backpressure:                                                    │   │
│  │    - Debounces rapid updates (100ms window)                      │   │
│  │    - Drops stale updates when overloaded                         │   │
│  │    - Priority: deletes > creates > updates                       │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow: Sensor Registration

```
Sensor connects to Node A
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ 1. SensorsDynamicSupervisor.start_child(SimpleSensor, opts)   │
│    (Local DynamicSupervisor -- sensor stays on this node)     │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ 2. SimpleSensor registers in local Registry + joins pg group  │
│    (pg notifies other nodes; local lookup is instant)         │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ 3. SimpleSensor broadcasts to "discovery:sensors"             │
│    {:sensor_registered, sensor_id, view_state, node()}        │
└───────────────────────────────────────────────────────────────┘
        │
        ├──────────────────────────────────────┐
        ▼                                      ▼
┌───────────────────────┐           ┌───────────────────────┐
│ Node A                │           │ Node B                │
│ DiscoverySyncWorker   │           │ DiscoverySyncWorker   │
│ updates local cache   │           │ updates local cache   │
└───────────────────────┘           └───────────────────────┘
        │                                      │
        ▼                                      ▼
┌───────────────────────┐           ┌───────────────────────┐
│ LiveView on Node A    │           │ LiveView on Node B    │
│ sees sensor via       │           │ sees sensor via       │
│ Discovery.list()      │           │ Discovery.list()      │
└───────────────────────┘           └───────────────────────┘
```

### Handling Slow Nodes

```
Client on Node A requests sensor state from Node B (slow)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ Discovery.get_sensor_state(sensor_id, timeout: 2_000)         │
│                                                               │
│ 1. Check local cache → if fresh (<5s), return immediately    │
│ 2. If stale, try remote call with timeout                     │
│ 3. If timeout, return stale cached data + :stale flag         │
│ 4. Background refresh queued (non-blocking)                   │
└───────────────────────────────────────────────────────────────┘

Result: Client NEVER blocks indefinitely
        Worst case: slightly stale data
```

### Backpressure Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BACKPRESSURE POINTS                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. SENSOR DATA FLOW (already implemented via attention levels)          │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ SimpleSensor tracks attention_level: :none | :low | :high    │    │
│     │ - :none → hibernate (no data processing)                     │    │
│     │ - :low  → throttled updates (1/sec)                          │    │
│     │ - :high → full rate updates                                  │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  2. DISCOVERY CACHE SYNC                                                 │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ DiscoverySyncWorker                                          │    │
│     │ - Debounce: 100ms coalescing window                          │    │
│     │ - Drop: if queue > 1000 messages, drop oldest non-deletes    │    │
│     │ - Priority: deletes processed first (consistency)            │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  3. CLIENT SUBSCRIPTIONS                                                 │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ Per-LiveView subscription manager                            │    │
│     │ - Subscribe to specific sensors, not "all"                   │    │
│     │ - Viewport-based: only subscribe to visible sensors          │    │
│     │ - Disconnect slow clients (heartbeat timeout)                │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  4. CROSS-NODE CALLS                                                     │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ All GenServer.call() with explicit timeouts                  │    │
│     │ - get_state: 2s timeout, fallback to cache                   │    │
│     │ - list operations: local cache only (no blocking)            │    │
│     │ - Circuit breaker: if node fails 3x, mark as degraded        │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Migrate Sensor Registry to pg + local Registry (Foundation)

**Goal**: Enable cluster-wide sensor process lookup without CRDT overhead

**Architecture decision (2026-02-08)**: Use pg + local Registry, NOT Horde.
Rationale: Sensors are high-churn. Horde's CRDT sync causes O(n) storms at scale.
See `PLAN-cluster-sensor-visibility.md` and `PLAN-sensor-scaling-refactor.md`.

**Files to modify**:
1. `lib/sensocto/registry/supervisor.ex` - Add pg scope, keep local Registry
2. `lib/sensocto/otp/simple_sensor.ex` - Register in both local Registry + pg
3. `lib/sensocto/otp/sensors_dynamic_supervisor.ex` - Keep local DynamicSupervisor

**Changes**:

```elixir
# New: lib/sensocto/sensor_registry.ex
defmodule Sensocto.SensorRegistry do
  def register(sensor_id, pid) do
    Registry.register(Sensocto.LocalSensorRegistry, sensor_id, pid)
    :pg.join(:sensors, {node(), sensor_id}, pid)
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
    :pg.which_groups(:sensors)
    |> Enum.find_value({:error, :not_found}, fn
      {_node, ^sensor_id} = group ->
        case :pg.get_members(:sensors, group) do
          [pid | _] -> {:ok, pid}
          [] -> nil
        end
      _ -> nil
    end)
  end
end
```

### Phase 2: Discovery Cache Service

**Goal**: Fast, non-blocking discovery queries

**New files**:
1. `lib/sensocto/discovery/discovery_cache.ex` - ETS-backed cache
2. `lib/sensocto/discovery/sync_worker.ex` - Background sync worker
3. `lib/sensocto/discovery/discovery.ex` - Public API

```elixir
defmodule Sensocto.Discovery.DiscoveryCache do
  @moduledoc """
  ETS-backed cache for entity discovery.
  Provides fast local reads without cross-node calls.
  """
  use GenServer

  @sensors_table :discovery_sensors
  @rooms_table :discovery_rooms
  @staleness_threshold_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Create ETS tables
    :ets.new(@sensors_table, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@rooms_table, [:named_table, :public, :set, read_concurrency: true])

    # Initial sync
    send(self(), :initial_sync)

    {:ok, %{}}
  end

  # Fast reads directly from ETS (no GenServer bottleneck)
  def list_sensors do
    :ets.tab2list(@sensors_table)
    |> Enum.map(fn {_id, data} -> data end)
  end

  def get_sensor(sensor_id) do
    case :ets.lookup(@sensors_table, sensor_id) do
      [{^sensor_id, data, updated_at}] ->
        stale? = System.monotonic_time(:millisecond) - updated_at > @staleness_threshold_ms
        {:ok, data, stale?}
      [] ->
        {:error, :not_found}
    end
  end

  # Updates via GenServer (serialized writes)
  def put_sensor(sensor_id, data) do
    GenServer.cast(__MODULE__, {:put_sensor, sensor_id, data})
  end

  def delete_sensor(sensor_id) do
    GenServer.cast(__MODULE__, {:delete_sensor, sensor_id})
  end

  # Similar for rooms...
end
```

```elixir
defmodule Sensocto.Discovery.SyncWorker do
  @moduledoc """
  Background worker that syncs discovery cache with cluster state.
  Uses PubSub for real-time updates and periodic full sync as safety net.
  """
  use GenServer
  require Logger

  @pubsub Sensocto.PubSub
  @sync_interval_ms 30_000
  @debounce_ms 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Subscribe to discovery events
    Phoenix.PubSub.subscribe(@pubsub, "discovery:sensors")
    Phoenix.PubSub.subscribe(@pubsub, "discovery:rooms")
    Phoenix.PubSub.subscribe(@pubsub, "rooms:cluster")

    # Schedule periodic full sync
    schedule_full_sync()

    {:ok, %{pending_updates: [], debounce_timer: nil}}
  end

  # Handle PubSub events
  def handle_info({:sensor_registered, sensor_id, view_state, _node}, state) do
    # Debounce updates
    state = queue_update({:sensor, :put, sensor_id, view_state}, state)
    {:noreply, state}
  end

  def handle_info({:sensor_unregistered, sensor_id, _node}, state) do
    # Deletes are high priority, process immediately
    Sensocto.Discovery.DiscoveryCache.delete_sensor(sensor_id)
    {:noreply, state}
  end

  def handle_info(:flush_updates, state) do
    # Process queued updates
    Enum.each(state.pending_updates, fn
      {:sensor, :put, id, data} -> Sensocto.Discovery.DiscoveryCache.put_sensor(id, data)
      {:room, :put, id, data} -> Sensocto.Discovery.DiscoveryCache.put_room(id, data)
    end)

    {:noreply, %{state | pending_updates: [], debounce_timer: nil}}
  end

  def handle_info(:full_sync, state) do
    Logger.debug("[SyncWorker] Running full sync")

    # Sync sensors from all nodes
    sync_sensors()
    sync_rooms()

    schedule_full_sync()
    {:noreply, state}
  end

  defp queue_update(update, state) do
    state = %{state | pending_updates: [update | state.pending_updates]}

    # Start debounce timer if not running
    if state.debounce_timer == nil do
      timer = Process.send_after(self(), :flush_updates, @debounce_ms)
      %{state | debounce_timer: timer}
    else
      state
    end
  end

  defp sync_sensors do
    # Get all sensors from Horde registry
    sensor_ids = Horde.Registry.select(
      Sensocto.DistributedSensorRegistry,
      [{{:"$1", :_, :_}, [], [:"$1"]}]
    )

    # Fetch states in parallel with timeout
    sensor_ids
    |> Task.async_stream(
      fn id -> {id, fetch_sensor_state(id)} end,
      max_concurrency: 20,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {id, {:ok, state}}} ->
        Sensocto.Discovery.DiscoveryCache.put_sensor(id, state)
      {:ok, {id, {:error, _}}} ->
        Logger.warning("[SyncWorker] Failed to sync sensor #{id}")
      {:exit, :timeout} ->
        Logger.warning("[SyncWorker] Timeout syncing sensor")
    end)
  end

  defp fetch_sensor_state(sensor_id) do
    try do
      {:ok, Sensocto.SimpleSensor.get_view_state(sensor_id)}
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  defp schedule_full_sync do
    Process.send_after(self(), :full_sync, @sync_interval_ms)
  end
end
```

```elixir
defmodule Sensocto.Discovery do
  @moduledoc """
  Public API for distributed entity discovery.

  Provides fast, non-blocking access to cluster-wide entity lists.
  Uses local ETS cache for reads, with background sync for updates.

  ## Usage

      # List all sensors (fast, from local cache)
      sensors = Discovery.list_sensors()

      # Get specific sensor with fallback
      case Discovery.get_sensor_state(sensor_id) do
        {:ok, state, :fresh} -> state
        {:ok, state, :stale} -> state  # Cached, but might be outdated
        {:error, :not_found} -> nil
      end

      # Subscribe to updates
      Discovery.subscribe(:sensors)
  """

  alias Sensocto.Discovery.DiscoveryCache

  @doc """
  Lists all sensors in the cluster.
  Returns immediately from local cache.
  """
  def list_sensors(opts \\ []) do
    sensors = DiscoveryCache.list_sensors()

    # Optional filtering
    sensors
    |> maybe_filter_by_type(opts[:type])
    |> maybe_filter_by_connector(opts[:connector_id])
  end

  @doc """
  Gets sensor state with staleness indicator.

  Returns:
  - `{:ok, state, :fresh}` - Recent data
  - `{:ok, state, :stale}` - Cached data, may be outdated
  - `{:error, :not_found}` - Sensor not in cluster
  """
  def get_sensor_state(sensor_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2_000)

    case DiscoveryCache.get_sensor(sensor_id) do
      {:ok, data, false} ->
        {:ok, data, :fresh}

      {:ok, data, true} ->
        # Stale data - try to refresh but don't block
        spawn(fn -> refresh_sensor(sensor_id, timeout) end)
        {:ok, data, :stale}

      {:error, :not_found} ->
        # Try direct lookup
        try do
          state = Sensocto.SimpleSensor.get_view_state(sensor_id)
          DiscoveryCache.put_sensor(sensor_id, state)
          {:ok, state, :fresh}
        catch
          :exit, _ -> {:error, :not_found}
        after
          timeout -> {:error, :not_found}
        end
    end
  end

  @doc """
  Lists all rooms in the cluster.
  """
  def list_rooms(opts \\ []) do
    # For rooms, we can use the existing Horde registry directly
    # since room state is relatively static
    Sensocto.RoomsDynamicSupervisor.list_rooms_with_state()
    |> maybe_filter_public(opts[:public_only])
    |> maybe_filter_by_owner(opts[:owner_id])
  end

  @doc """
  Lists all online users using Presence.
  """
  def list_users do
    Sensocto.Presence.list("presence:all")
  end

  @doc """
  Subscribe to discovery updates for a specific entity type.
  """
  def subscribe(entity_type) when entity_type in [:sensors, :rooms, :users] do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "discovery:#{entity_type}")
  end

  @doc """
  Get cluster health information for discovery.
  """
  def cluster_health do
    nodes = [node() | Node.list()]

    %{
      nodes: length(nodes),
      sensors: length(list_sensors()),
      rooms: length(list_rooms()),
      users: map_size(list_users())
    }
  end

  # Private helpers

  defp refresh_sensor(sensor_id, timeout) do
    try do
      state = Sensocto.SimpleSensor.get_view_state(sensor_id)
      DiscoveryCache.put_sensor(sensor_id, state)
    catch
      :exit, _ -> :ok
    after
      timeout -> :ok
    end
  end

  defp maybe_filter_by_type(sensors, nil), do: sensors
  defp maybe_filter_by_type(sensors, type) do
    Enum.filter(sensors, &(&1.sensor_type == type))
  end

  defp maybe_filter_by_connector(sensors, nil), do: sensors
  defp maybe_filter_by_connector(sensors, connector_id) do
    Enum.filter(sensors, &(&1.connector_id == connector_id))
  end

  defp maybe_filter_public(rooms, nil), do: rooms
  defp maybe_filter_public(rooms, true) do
    Enum.filter(rooms, & &1.is_public)
  end

  defp maybe_filter_by_owner(rooms, nil), do: rooms
  defp maybe_filter_by_owner(rooms, owner_id) do
    Enum.filter(rooms, &(&1.owner_id == owner_id))
  end
end
```

### Phase 3: Broadcast Sensor Events

**Goal**: Propagate sensor lifecycle events cluster-wide

**Modify** `lib/sensocto/otp/simple_sensor.ex`:

```elixir
def init(state) do
  # ... existing init code ...

  # Broadcast registration to cluster
  broadcast_registration(state)

  {:ok, state}
end

def terminate(reason, state) do
  # Broadcast unregistration to cluster
  broadcast_unregistration(state.sensor_id)

  # ... existing terminate code ...
end

defp broadcast_registration(state) do
  Phoenix.PubSub.broadcast(
    Sensocto.PubSub,
    "discovery:sensors",
    {:sensor_registered, state.sensor_id, build_view_state(state), node()}
  )
end

defp broadcast_unregistration(sensor_id) do
  Phoenix.PubSub.broadcast(
    Sensocto.PubSub,
    "discovery:sensors",
    {:sensor_unregistered, sensor_id, node()}
  )
end

# Also broadcast significant state changes
defp maybe_broadcast_update(old_state, new_state) do
  if state_changed_significantly?(old_state, new_state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "discovery:sensors",
      {:sensor_updated, new_state.sensor_id, build_view_state(new_state), node()}
    )
  end
end
```

### Phase 4: Update LiveViews to Use Discovery API

**Modify** `lib/sensocto_web/live/lobby_live.ex`:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    # Subscribe to discovery updates
    Sensocto.Discovery.subscribe(:sensors)
    Sensocto.Discovery.subscribe(:rooms)
  end

  # Fast read from local cache (non-blocking)
  sensors = Sensocto.Discovery.list_sensors()
  rooms = Sensocto.Discovery.list_rooms(public_only: true)

  # Subscribe to per-sensor updates for visible sensors
  Enum.each(sensors, fn sensor ->
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor.id}")
  end)

  socket =
    socket
    |> assign(:sensors, sensors)
    |> assign(:rooms, rooms)
    |> assign(:loading, false)

  {:ok, socket}
end

def handle_info({:sensor_registered, sensor_id, state, _node}, socket) do
  sensors = Map.put(socket.assigns.sensors, sensor_id, state)
  Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
  {:noreply, assign(socket, :sensors, sensors)}
end

def handle_info({:sensor_unregistered, sensor_id, _node}, socket) do
  sensors = Map.delete(socket.assigns.sensors, sensor_id)
  Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "signal:#{sensor_id}")
  {:noreply, assign(socket, :sensors, sensors)}
end
```

### Phase 5: Circuit Breaker for Node Health

**Goal**: Prevent cascading failures from slow/dead nodes

**New file**: `lib/sensocto/discovery/node_health.ex`

```elixir
defmodule Sensocto.Discovery.NodeHealth do
  @moduledoc """
  Tracks node health and implements circuit breaker pattern.
  Prevents repeated calls to slow/dead nodes.
  """
  use GenServer

  @failure_threshold 3
  @recovery_timeout_ms 30_000
  @check_interval_ms 10_000

  defstruct [
    failures: %{},      # node => failure_count
    degraded: MapSet.new(), # nodes in degraded state
    last_check: %{}     # node => timestamp
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :net_kernel.monitor_nodes(true)
    schedule_health_check()
    {:ok, %__MODULE__{}}
  end

  @doc """
  Check if a node is healthy (not in degraded state).
  """
  def healthy?(node) do
    GenServer.call(__MODULE__, {:healthy?, node})
  end

  @doc """
  Report a failure when calling a node.
  """
  def report_failure(node) do
    GenServer.cast(__MODULE__, {:failure, node})
  end

  @doc """
  Report success when calling a node (resets failure count).
  """
  def report_success(node) do
    GenServer.cast(__MODULE__, {:success, node})
  end

  @doc """
  Get current cluster health status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Callbacks

  def handle_call({:healthy?, node}, _from, state) do
    healthy = not MapSet.member?(state.degraded, node)
    {:reply, healthy, state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      degraded_nodes: MapSet.to_list(state.degraded),
      failure_counts: state.failures,
      healthy_nodes: Node.list() -- MapSet.to_list(state.degraded)
    }
    {:reply, status, state}
  end

  def handle_cast({:failure, node}, state) do
    failures = Map.update(state.failures, node, 1, &(&1 + 1))

    state = %{state | failures: failures}

    # Check if should mark as degraded
    state =
      if Map.get(failures, node, 0) >= @failure_threshold do
        Logger.warning("[NodeHealth] Marking node #{node} as degraded")
        %{state | degraded: MapSet.put(state.degraded, node)}
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast({:success, node}, state) do
    state = %{state |
      failures: Map.delete(state.failures, node),
      degraded: MapSet.delete(state.degraded, node)
    }
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.info("[NodeHealth] Node #{node} went down")
    state = %{state | degraded: MapSet.put(state.degraded, node)}
    {:noreply, state}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("[NodeHealth] Node #{node} came up")
    # Don't immediately trust - let health checks verify
    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    # Try to recover degraded nodes
    state =
      Enum.reduce(state.degraded, state, fn node, acc ->
        if check_node_health(node) do
          Logger.info("[NodeHealth] Node #{node} recovered")
          %{acc |
            degraded: MapSet.delete(acc.degraded, node),
            failures: Map.delete(acc.failures, node)
          }
        else
          acc
        end
      end)

    schedule_health_check()
    {:noreply, state}
  end

  defp check_node_health(node) do
    try do
      :rpc.call(node, :erlang, :node, [], 5_000) == node
    catch
      _, _ -> false
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @check_interval_ms)
  end
end
```

## Supervision Tree Updates

Add to `lib/sensocto/application.ex`:

```elixir
# In domain supervisor children
children = [
  # ... existing children ...

  # Discovery system (after registries, before dynamic supervisors)
  Sensocto.Discovery.NodeHealth,
  Sensocto.Discovery.DiscoveryCache,
  Sensocto.Discovery.SyncWorker,
]
```

## Testing Strategy

### Local Multi-Node Testing

```bash
# Terminal 1 - Node A
iex --sname a -S mix phx.server

# Terminal 2 - Node B
iex --sname b -S mix

# In Node B IEx:
Node.connect(:"a@hostname")

# Verify cluster
Node.list()  # Should show node A

# Test discovery
Sensocto.Discovery.list_sensors()  # Should show sensors from both nodes
```

### Integration Tests

```elixir
defmodule Sensocto.Discovery.IntegrationTest do
  use ExUnit.Case, async: false

  describe "cross-node discovery" do
    test "sensors on node A visible from node B" do
      # Create sensor on node A
      {:ok, sensor_id, _pid} = Sensocto.SensorsDynamicSupervisor.start_sensor(...)

      # Wait for sync
      Process.sleep(500)

      # Query from any node
      sensors = Sensocto.Discovery.list_sensors()
      assert Enum.any?(sensors, &(&1.id == sensor_id))
    end

    test "slow node doesn't block discovery" do
      # Simulate slow node response
      # Discovery should return cached data within timeout
    end
  end
end
```

## Rollback Plan

If issues occur:

1. **Revert registry changes** - Return to local Registry
2. **Disable discovery cache** - Use direct Horde calls
3. **Fall back to single-node** - Scale to 1 instance temporarily

## Success Criteria

1. User on Node A sees sensors connected to Node B
2. User on Node B sees sensors connected to Node A
3. Slow node doesn't block other nodes (timeout + cache fallback)
4. Sensor presence updates propagate within 500ms
5. No significant latency increase for local sensors
6. Discovery queries complete in <50ms (from cache)
7. System gracefully degrades when nodes are unhealthy

## Migration Path

1. Deploy Phase 1 (Horde migration) - sensor registration changes
2. Monitor for issues, rollback if needed
3. Deploy Phase 2 (Discovery cache) - adds caching layer
4. Deploy Phase 3 (Event broadcasts) - enables real-time updates
5. Deploy Phase 4 (LiveView updates) - client-facing changes
6. Deploy Phase 5 (Circuit breaker) - resilience improvements

Each phase can be deployed independently and rolled back if needed.
