# Supervision Tree Visualization

This document provides a visual representation of Sensocto's OTP supervision tree architecture.

## Mermaid Diagram

```mermaid
flowchart TB
    subgraph Root["Sensocto.Supervisor - rest_for_one"]
        subgraph L1["Layer 1: Infrastructure.Supervisor"]
            Telemetry["Telemetry"]
            Repo["Repo"]
            PubSub["PubSub"]
            Presence["Presence"]
            DNS["DNSCluster"]
            Finch["Finch"]
        end

        subgraph L2["Layer 2: Registry.Supervisor"]
            SensorReg["SimpleSensorRegistry"]
            AttrReg["SimpleAttributeRegistry"]
            RoomReg["RoomRegistry"]
            JoinReg["RoomJoinCodeRegistry"]
            CallReg["CallRegistry"]
            MediaReg["MediaRegistry"]
            Obj3DReg["Object3DRegistry"]
        end

        subgraph L3["Layer 3: Storage.Supervisor - rest_for_one"]
            IrohStore["Iroh.RoomStore"]
            RoomStore["RoomStore"]
            IrohSync["Iroh.RoomSync"]
            CRDT["RoomStateCRDT"]
        end

        subgraph L4["Layer 4: Bio.Supervisor"]
            Novelty["NoveltyDetector"]
            LoadBalancer["PredictiveLoadBalancer"]
            Tuner["HomeostaticTuner"]
        end

        subgraph L5["Layer 5: Domain.Supervisor"]
            Attention["AttentionTracker"]

            subgraph SensorsSup["SensorsDynamicSupervisor"]
                Sensor1["SimpleSensor"]
                Attr1["AttributeStore"]
            end

            subgraph RoomsSup["RoomsDynamicSupervisor"]
                Room1["RoomServer"]
            end

            CallSup["CallSupervisor"]
            MediaSup["MediaPlayerSupervisor"]
            Obj3DSup["Object3DPlayerSupervisor"]
        end

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
    Obj3DSup --> Endpoint
    Endpoint --> Auth
    Auth -.-> SimMgr

    classDef infrastructure fill:#e1f5fe,stroke:#0277bd
    classDef registry fill:#f3e5f5,stroke:#7b1fa2
    classDef storage fill:#fff3e0,stroke:#ef6c00
    classDef bio fill:#e8f5e9,stroke:#2e7d32
    classDef domain fill:#fce4ec,stroke:#c2185b
    classDef endpoint fill:#e0f2f1,stroke:#00695c
    classDef optional fill:#f5f5f5,stroke:#616161,stroke-dasharray:5,5

    class Telemetry,Repo,PubSub,Presence,DNS,Finch infrastructure
    class SensorReg,AttrReg,RoomReg,JoinReg,CallReg,MediaReg,Obj3DReg registry
    class IrohStore,RoomStore,IrohSync,CRDT storage
    class Novelty,LoadBalancer,Tuner bio
    class Attention,CallSup,MediaSup,Obj3DSup,Sensor1,Attr1,Room1 domain
    class Endpoint,Auth endpoint
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

| Crash | Impact |
|-------|--------|
| Single sensor | Only that sensor restarts |
| Sensor registry | Brief lookup failure, rooms unaffected |
| Storage layer | All storage restarts, domains continue |
| Infrastructure | Full cascade restart, clean recovery |
