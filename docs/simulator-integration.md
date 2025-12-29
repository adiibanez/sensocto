# Simulator Integration Plan

## Current State

### Main Application (`lib/sensocto/`)
- Uses `SensorsDynamicSupervisor` to manage sensor processes
- Each sensor has `SimpleSensor` (GenServer) + `AttributeStore` (Agent) under `SensorSupervisor`
- Data flows through `SensorDataChannel` via Phoenix channels
- Multiple registries: `SensorPairRegistry`, `SimpleAttributeRegistry`, etc.

### Simulator (`simulator/sensocto_elixir_simulator/`)
- Standalone Elixir application connecting via WebSocket
- Hierarchical: `Manager` → `ConnectorGenServer` → `SensorGenServer` → `AttributeGenServer`
- Uses `PhoenixClient` to connect externally to `ws://localhost:4000/socket/websocket`
- Configuration via YAML (`config/simulators.yaml`)
- Data generation via `BiosenseData` module (Python scripts + fake data)

---

## Integration Options

### Option A: Keep Separate (Current State)
**Pros:** No code changes, clean separation
**Cons:** Separate deployment, external connection overhead, duplicate registries

### Option B: Embed as Library Dependency
**Pros:** Single deployment, shared supervision
**Cons:** Namespace conflicts, still connects via WebSocket

### Option C: Full Integration (Recommended)
**Pros:** Single app, internal process communication, shared infrastructure
**Cons:** More refactoring required

---

## Recommended Approach: Option C - Full Integration

### Phase 1: Module Migration

Move simulator code to main app under `lib/sensocto/simulator/`:

```
lib/sensocto/simulator/
├── simulator.ex              # Module entry point
├── manager.ex               # Config management (from manager.ex)
├── connector_server.ex      # ConnectorGenServer renamed
├── sensor_server.ex         # SensorGenServer renamed
├── attribute_server.ex      # AttributeGenServer renamed
├── data_generator.ex        # BiosenseData module
├── data_server.ex           # BiosenseData.GenServer pool
└── config/
    └── simulators.yaml      # Move config here or to config/
```

**Namespace changes:**
- `Sensocto.Simulator.Manager` → `Sensocto.Simulator.Manager`
- `Sensocto.Simulator.ConnectorGenServer` → `Sensocto.Simulator.ConnectorServer`
- `Sensocto.Simulator.SensorGenServer` → `Sensocto.Simulator.SensorServer`
- `Sensocto.Simulator.AttributeGenServer` → `Sensocto.Simulator.AttributeServer`

### Phase 2: Connection Strategy Change

**Current:** Simulator → WebSocket → Phoenix Channel → SimpleSensor
**New:** Simulator → Direct GenServer calls → SimpleSensor

Instead of using `PhoenixClient` to connect via WebSocket, the simulator will:

1. Use `SensorsDynamicSupervisor.add_sensor/2` to create real sensors
2. Call `SimpleSensor.put_attribute/2` or `SimpleSensor.put_batch_attributes/2` directly
3. Share the same registries and PubSub infrastructure

### Phase 3: Supervision Tree Integration

Add to `lib/sensocto/application.ex`:

```elixir
children = [
  # ... existing children ...

  # Simulator (optional, controlled by config)
  {Sensocto.Simulator.Supervisor, []}  # Only if simulator enabled
]
```

New supervisor structure:
```
Sensocto.Simulator.Supervisor
├── Sensocto.Simulator.DataServerPool (1-5 workers)
├── Sensocto.Simulator.Manager
└── Sensocto.Simulator.ConnectorSupervisor (DynamicSupervisor)
    └── Sensocto.Simulator.ConnectorServer (per connector)
        └── DynamicSupervisor (per connector)
            └── Sensocto.Simulator.SensorServer (per sensor)
                └── DynamicSupervisor (per sensor)
                    └── Sensocto.Simulator.AttributeServer (per attribute)
```

### Phase 4: Configuration

Add to `config/dev.exs`:
```elixir
config :sensocto, :simulator,
  enabled: true,
  config_path: "config/simulators.yaml"
```

Add to `config/prod.exs`:
```elixir
config :sensocto, :simulator,
  enabled: false
```

### Phase 5: Remove WebSocket Dependency

In `ConnectorServer` and `SensorServer`:
- Remove `phoenix_client` dependency
- Replace `PhoenixClient.Socket` with direct process communication
- Replace `Channel.push_async` with `SimpleSensor.put_batch_attributes/2`

---

## Detailed File Changes

### New Files to Create

1. **`lib/sensocto/simulator/supervisor.ex`**
   - Top-level simulator supervisor
   - Conditionally started based on config

2. **`lib/sensocto/simulator/manager.ex`**
   - Adapted from `simulator/lib/manager.ex`
   - Loads YAML config, manages connector lifecycle

3. **`lib/sensocto/simulator/connector_server.ex`**
   - Adapted from `connector_genserver.ex`
   - Removes WebSocket, directly creates sensors via `SensorsDynamicSupervisor`

4. **`lib/sensocto/simulator/sensor_server.ex`**
   - Adapted from `sensor_genserver.ex`
   - Removes channel join, gets `SimpleSensor` pid from registry
   - Pushes data via `SimpleSensor.put_batch_attributes/2`

5. **`lib/sensocto/simulator/attribute_server.ex`**
   - Adapted from `attribute_genserver.ex`
   - Sends batched data to parent `SensorServer`

6. **`lib/sensocto/simulator/data_generator.ex`**
   - Adapted from `biosense_data.ex`
   - Data generation logic (Python integration or fake data)

7. **`lib/sensocto/simulator/data_server.ex`**
   - Adapted from `biosense_data_server.ex`
   - GenServer pool for parallel data generation

### Files to Modify

1. **`lib/sensocto/application.ex`**
   - Add conditional simulator supervisor startup

2. **`mix.exs`**
   - Add `yaml_elixir` dependency (for YAML config)
   - Add `nimble_csv` dependency (if using Python CSV data)
   - Remove any `phoenix_client` from simulator

3. **`config/dev.exs`**
   - Add simulator configuration

4. **`config/config.exs`**
   - Add default simulator config (disabled)

### Files to Delete (after migration)

- `simulator/sensocto_elixir_simulator/` entire directory (or archive)

---

## Migration Steps

### Step 1: Add Dependencies
```elixir
# mix.exs
{:yaml_elixir, "~> 2.11"},
{:nimble_csv, "~> 1.1"}
```

### Step 2: Create Simulator Module Structure
- Create `lib/sensocto/simulator/` directory
- Copy and adapt files one by one

### Step 3: Update Supervisor Integration
- Create `Sensocto.Simulator.Supervisor`
- Add to main application conditionally

### Step 4: Refactor Connection Logic
- Replace WebSocket with direct GenServer communication
- Use existing registries for process discovery

### Step 5: Test & Validate
- Start simulator via config flag
- Verify data flows to UI correctly
- Test start/stop/reload functionality

### Step 6: Cleanup
- Remove old simulator directory
- Update any documentation

---

## Key Architectural Decisions

1. **Direct vs Channel Communication**
   - Using direct GenServer calls is faster and simpler
   - No need for WebSocket serialization/deserialization
   - Simulator data appears identical to real sensor data

2. **Shared vs Separate Sensors**
   - Simulator creates real `SimpleSensor` processes
   - Same data path as physical sensors
   - UI cannot distinguish simulated from real (by design)

3. **Configuration Management**
   - Keep YAML config for easy editing
   - Add environment-based enable/disable
   - Support hot-reload via `Manager.reload_config/0`

4. **Data Generation**
   - Keep Python integration for complex waveforms
   - Fallback to fake data when Python unavailable
   - GenServer pool for parallel generation

---

## Estimated Effort

| Phase | Files | Complexity | Effort |
|-------|-------|------------|--------|
| Phase 1: Module Migration | 7 new | Medium | 2-3 hours |
| Phase 2: Connection Refactor | 2 modified | High | 2-3 hours |
| Phase 3: Supervision Tree | 2 modified | Medium | 1 hour |
| Phase 4: Configuration | 3 modified | Low | 30 min |
| Phase 5: Testing & Cleanup | - | Medium | 1-2 hours |

**Total: ~7-10 hours**

---

## Questions for User

1. Do you want to keep Python data generation or switch to pure Elixir fake data?
2. Should the simulator be controllable via a LiveView admin UI?
3. Do you need to distinguish simulated sensors from real ones in the UI?
4. Should we preserve backward compatibility (keep old simulator working during migration)?
