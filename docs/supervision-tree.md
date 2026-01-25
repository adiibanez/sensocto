# Supervision Tree Visualization

This document provides a visual representation of Sensocto's OTP supervision tree architecture.

**Last Updated:** January 2026

## Mermaid Diagram

```mermaid
flowchart TB
    subgraph Root["Sensocto.Supervisor - rest_for_one"]
        subgraph L1["Layer 1: Infrastructure.Supervisor"]
            Telemetry["Telemetry"]
            TaskSup["Task.Supervisor"]
            Repo["Repo (Primary)"]
            RepoReplica["Repo.Replica"]
            DNS["DNSCluster"]
            PubSub["PubSub"]
            Presence["Presence"]
            Finch["Finch"]
        end

        subgraph L2["Layer 2: Registry.Supervisor"]
            subgraph SensorRegs["Sensor Registries"]
                SensorReg["SimpleSensorRegistry"]
                AttrReg["SimpleAttributeRegistry"]
                PairReg["SensorPairRegistry"]
            end
            subgraph RoomRegs["Room Registries"]
                RoomReg["RoomRegistry"]
                JoinReg["RoomJoinCodeRegistry"]
                DistRoomReg["DistributedRoomRegistry (Horde)"]
                DistJoinReg["DistributedJoinCodeRegistry (Horde)"]
            end
            subgraph FeatureRegs["Feature Registries"]
                CallReg["CallRegistry"]
                MediaReg["MediaRegistry"]
                Obj3DReg["Object3DRegistry"]
            end
        end

        subgraph L3["Layer 3: Storage.Supervisor - rest_for_one"]
            IrohStore["Iroh.RoomStore"]
            RoomStore["RoomStore"]
            IrohSync["Iroh.RoomSync"]
            CRDT["RoomStateCRDT"]
            RoomPresence["RoomPresenceServer"]
        end

        subgraph L4["Layer 4: Bio.Supervisor (Biomimetic)"]
            Novelty["NoveltyDetector<br/>(Locus Coeruleus)"]
            LoadBalancer["PredictiveLoadBalancer<br/>(Cerebellum)"]
            Tuner["HomeostaticTuner<br/>(Synaptic Plasticity)"]
            Arbiter["ResourceArbiter<br/>(Lateral Inhibition)"]
            Circadian["CircadianScheduler<br/>(SCN)"]
        end

        subgraph L5["Layer 5: Domain.Supervisor"]
            Attention["AttentionTracker (ETS)"]
            SysLoad["SystemLoadMonitor (ETS)"]
            SensorsState["SensorsStateAgent"]

            subgraph SensorsSup["SensorsDynamicSupervisor"]
                subgraph SensorSup["SensorSupervisor (per sensor)"]
                    Sensor1["SimpleSensor"]
                    Attr1["AttributeStore"]
                end
            end

            subgraph RoomsSup["RoomsDynamicSupervisor (Horde)"]
                Room1["RoomServer"]
            end

            CallSup["CallSupervisor"]
            MediaSup["MediaPlayerSupervisor"]
            Obj3DSup["Object3DPlayerSupervisor"]
            RepoPool["RepoReplicatorPool (8)"]
            SearchIdx["Search.SearchIndex"]
        end

        GuestStore["GuestUserStore (2h TTL)"]
        Endpoint["SensoctoWeb.Endpoint"]
        Auth["AshAuthentication.Supervisor"]

        subgraph Optional["Optional: Simulator.Supervisor"]
            SimMgr["Simulator.Manager"]
            SimConn["ConnectorSupervisor"]
        end
    end

    Finch --> SensorReg
    Obj3DReg --> IrohStore
    CRDT --> Novelty
    Tuner --> Attention
    Obj3DSup --> GuestStore
    GuestStore --> Endpoint
    Endpoint --> Auth
    Auth -.-> SimMgr

    classDef infrastructure fill:#e1f5fe,stroke:#0277bd
    classDef registry fill:#f3e5f5,stroke:#7b1fa2
    classDef storage fill:#fff3e0,stroke:#ef6c00
    classDef bio fill:#e8f5e9,stroke:#2e7d32
    classDef domain fill:#fce4ec,stroke:#c2185b
    classDef endpoint fill:#e0f2f1,stroke:#00695c
    classDef optional fill:#f5f5f5,stroke:#616161,stroke-dasharray:5,5

    class Telemetry,TaskSup,Repo,RepoReplica,PubSub,Presence,DNS,Finch infrastructure
    class SensorReg,AttrReg,PairReg,RoomReg,JoinReg,DistRoomReg,DistJoinReg,CallReg,MediaReg,Obj3DReg registry
    class IrohStore,RoomStore,IrohSync,CRDT,RoomPresence storage
    class Novelty,LoadBalancer,Tuner,Arbiter,Circadian bio
    class Attention,SysLoad,SensorsState,CallSup,MediaSup,Obj3DSup,RepoPool,SearchIdx,Sensor1,Attr1,Room1 domain
    class GuestStore,Endpoint,Auth endpoint
    class SimMgr,SimConn optional
```

## Simplified View

```mermaid
flowchart LR
    subgraph Sensocto
        A[Infrastructure] --> B[Registry]
        B --> C[Storage]
        C --> D[Bio]
        D --> E[Domain]
        E --> F[Endpoint]
        F --> G[Auth]
    end

    style A fill:#e1f5fe
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#e8f5e9
    style E fill:#fce4ec
    style F fill:#e0f2f1
    style G fill:#e0f2f1
```

## Layer Dependencies

```mermaid
flowchart TD
    subgraph Dependencies
        Infra["Infrastructure: PubSub, Repo, Telemetry"]
        Reg["Registry: Process Discovery"]
        Store["Storage: Iroh, CRDT"]
        Bio["Bio: Adaptive Management"]
        Domain["Domain: Sensors, Rooms, Calls"]
        Web["Web: Endpoint, Auth"]
    end

    Domain -->|uses| Reg
    Domain -->|uses| Store
    Domain -->|uses| Infra
    Store -->|uses| Infra
    Bio -->|observes| Domain
    Web -->|serves| Domain

    style Infra fill:#e1f5fe
    style Reg fill:#f3e5f5
    style Store fill:#fff3e0
    style Bio fill:#e8f5e9
    style Domain fill:#fce4ec
    style Web fill:#e0f2f1
```

## Strategy Rationale

| Supervisor | Strategy | Reason |
|------------|----------|--------|
| Root (Sensocto.Supervisor) | `rest_for_one` | Later layers depend on earlier ones |
| Infrastructure | `one_for_one` | Children are independent |
| Registry | `one_for_one` | Registries don't depend on each other |
| Storage | `rest_for_one` | RoomStore depends on Iroh.RoomStore |
| Bio | `one_for_one` | Observers are independent |
| Domain | `one_for_one` | Dynamic supervisors are independent |

## Blast Radius

| Crash Location | Impact | Recovery Time | Affected Users |
|----------------|--------|---------------|----------------|
| Single SimpleSensor | Only that sensor restarts | ~100ms | Users viewing that sensor |
| Single RoomServer | Only that room restarts | ~200ms | Room members |
| Sensor registry | Brief lookup failure | ~500ms | All sensor lookups |
| Room registry | Brief lookup failure | ~500ms | Room joins/lookups |
| Bio.NoveltyDetector | Novelty detection offline | ~100ms | None (advisory only) |
| Iroh.RoomStore | All storage processes restart | ~2s | Room state operations |
| PubSub | Full infrastructure cascade | ~5s | All users |
| Repo | Full infrastructure cascade | ~5s | All users |

## ETS Tables (Fast Path Lookups)

| Table | Owner | Purpose |
|-------|-------|---------|
| `:attention_tracker` | AttentionTracker | O(1) attention level queries |
| `:system_load` | SystemLoadMonitor | O(1) load metrics |
| `:novelty_detector` | NoveltyDetector | O(1) anomaly scores |

## PubSub Topics

| Topic Pattern | Publisher | Subscribers |
|---------------|-----------|-------------|
| `sensor:SENSOR_ID:data` | SimpleSensor | LiveViews |
| `attention:SENSOR_ID` | AttentionTracker | SimpleSensor |
| `system:load` | SystemLoadMonitor | AttentionTracker |
| `rooms:cluster` | RoomsDynamicSupervisor | LiveViews |
| `sensors:global` | SensorsDynamicSupervisor | LiveViews |
| `bio:novelty:SENSOR_ID` | NoveltyDetector | AttentionTracker |
