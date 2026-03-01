# Room Persistence Migration Plan: PostgreSQL → In-Memory + Iroh Docs

**Status: PARTIALLY IMPLEMENTED** (IrohConnectionManager done, identity persistence blocked)
**Updated: 2026-02-08**

## Overview

This plan outlines the migration of room persistence from PostgreSQL to an in-memory GenServer architecture with iroh_ex document storage for distributed state synchronization.

## Current Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   Rooms Context (Business Logic)               │
└──────────────┬────────────────────────────────────┬────────────┘
               │                                    │
         ┌─────▼─────┐                        ┌─────▼──────┐
         │ Persisted │                        │ Temporary  │
         │   Rooms   │                        │   Rooms    │
         │ PostgreSQL│                        │ GenServer  │
         │ (Ash/Ecto)│                        │ (RoomServer)
         └───────────┘                        └────────────┘
```

### Key Files:
- `lib/sensocto/sensors/room.ex` - Ash Resource (PostgreSQL)
- `lib/sensocto/sensors/room_membership.ex` - Membership join table
- `lib/sensocto/otp/room_server.ex` - Temporary room GenServer
- `lib/sensocto/otp/rooms_dynamic_supervisor.ex` - Supervisor
- `lib/sensocto/rooms.ex` - Context module

## Target Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   Rooms Context (Business Logic)               │
└──────────────────────────────┬─────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   RoomStore         │
                    │   (GenServer)       │
                    │   - In-Memory State │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │   IrohRoomSync      │
                    │   (Async Sync)      │
                    │   - Docs Storage    │
                    │   - P2P Broadcast   │
                    └─────────────────────┘
```

### Benefits:
1. **Fast reads/writes** - All data in memory
2. **Distributed sync** - Iroh docs provide eventual consistency
3. **P2P communication** - Gossip for real-time updates
4. **Simplified architecture** - Single storage mechanism
5. **Portable** - No database dependency

## Implementation Steps

### Phase 1: Create Iroh Room Store Module

Create a new module `Sensocto.Iroh.RoomStore` that:

1. **Manages an Iroh node** with docs storage
2. **Provides CRUD operations** for rooms using iroh docs
3. **Handles serialization** of room state to binary (JSON)

```elixir
# lib/sensocto/iroh/room_store.ex
defmodule Sensocto.Iroh.RoomStore do
  use GenServer
  alias IrohEx.Native

  defstruct [
    :node_ref,
    :author_id,
    :rooms_namespace,  # iroh doc for rooms
    :memberships_namespace  # iroh doc for memberships
  ]

  # Key structure in iroh docs:
  # rooms_namespace:
  #   "room:{room_id}" => JSON encoded room data
  #   "room_index:all" => JSON list of room IDs
  #   "room_index:public" => JSON list of public room IDs
  #   "room_index:user:{user_id}" => JSON list of user's room IDs
  #
  # memberships_namespace:
  #   "membership:{room_id}:{user_id}" => JSON encoded membership
end
```

### Phase 2: Create Enhanced Room Store GenServer

Enhance `RoomsDynamicSupervisor` to be the single source of truth:

```elixir
# lib/sensocto/otp/room_store.ex (new or merge into existing)
defmodule Sensocto.RoomStore do
  use GenServer

  # In-memory state structure
  defstruct [
    rooms: %{},           # room_id => room_state
    memberships: %{},     # {room_id, user_id} => role
    join_codes: %{},      # join_code => room_id
    user_rooms: %{},      # user_id => [room_ids]
    iroh_sync_pid: nil    # Reference to IrohRoomSync process
  ]

  # API
  def create_room(attrs, owner_id)
  def get_room(room_id)
  def list_user_rooms(user_id)
  def list_public_rooms()
  def join_room(room_id, user_id, role)
  def leave_room(room_id, user_id)
  def update_room(room_id, attrs)
  def delete_room(room_id)

  # All operations:
  # 1. Update in-memory state
  # 2. Async sync to iroh docs (via IrohRoomSync)
  # 3. Return immediately
end
```

### Phase 3: Iroh Sync Worker

Background process for syncing state to iroh docs:

```elixir
# lib/sensocto/iroh/room_sync.ex
defmodule Sensocto.Iroh.RoomSync do
  use GenServer
  alias IrohEx.Native

  # Handles:
  # 1. Batched writes to iroh docs (debounced)
  # 2. Receiving sync events from other nodes
  # 3. Hydrating state on startup from iroh docs
  # 4. Broadcasting changes via gossip

  def sync_room(room_id, room_state)
  def sync_membership(room_id, user_id, role)
  def delete_room(room_id)
  def hydrate_from_iroh() # Load all rooms from iroh docs on startup
end
```

### Phase 4: Room State Structure

Room data structure stored in iroh docs:

```elixir
%{
  id: "uuid",
  name: "Room Name",
  description: "Optional description",
  owner_id: "user_uuid",
  join_code: "ABC12345",
  is_public: true,
  configuration: %{},
  created_at: "2025-01-10T12:00:00Z",
  updated_at: "2025-01-10T12:00:00Z"
}
```

Membership structure:
```elixir
%{
  room_id: "room_uuid",
  user_id: "user_uuid",
  role: "owner" | "admin" | "member",
  joined_at: "2025-01-10T12:00:00Z"
}
```

### Phase 5: Update Rooms Context

Modify `Sensocto.Rooms` to use only in-memory store:

1. Remove all Ash/PostgreSQL references for rooms
2. Route all operations to `Sensocto.RoomStore`
3. Keep user auth (Ash) separate

```elixir
# lib/sensocto/rooms.ex (updated)
defmodule Sensocto.Rooms do
  alias Sensocto.RoomStore

  def create_room(attrs, user) do
    RoomStore.create_room(attrs, user.id)
  end

  def get_room(room_id) do
    RoomStore.get_room(room_id)
  end

  # ... etc
end
```

### Phase 6: Migration Script

One-time migration to move existing PostgreSQL rooms to iroh:

```elixir
# lib/sensocto/migrations/rooms_to_iroh.ex
defmodule Sensocto.Migrations.RoomsToIroh do
  def run do
    # 1. Read all rooms from PostgreSQL
    # 2. Write each to RoomStore (which syncs to iroh)
    # 3. Read all memberships
    # 4. Write each membership to RoomStore
  end
end
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/sensocto/iroh/room_store.ex` | Iroh node management, docs CRUD |
| `lib/sensocto/iroh/room_sync.ex` | Async sync worker |
| `lib/sensocto/otp/room_store.ex` | Main in-memory store |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/sensocto/rooms.ex` | Remove PostgreSQL, use RoomStore |
| `lib/sensocto/application.ex` | Add IrohRoomSync, RoomStore to supervision tree |
| `lib/sensocto/otp/room_server.ex` | Potentially remove or simplify |
| `lib/sensocto/otp/rooms_dynamic_supervisor.ex` | Merge into RoomStore |

## Files to Keep (No Changes)

| File | Reason |
|------|--------|
| `lib/sensocto/sensors/room.ex` | Keep for reference, may remove later |
| `lib/sensocto/graph/*.ex` | Neo4j for analytics (optional) |
| User auth files | Separate concern, keep in PostgreSQL |

## Supervision Tree

```elixir
children = [
  # ... existing children ...

  # Iroh sync (must start before RoomStore)
  {Sensocto.Iroh.RoomSync, []},

  # Main room store (hydrates from iroh on init)
  {Sensocto.RoomStore, []},

  # Remove or keep RoomsDynamicSupervisor based on final design
]
```

## Testing Strategy

1. **Unit tests** for RoomStore operations
2. **Integration tests** for iroh sync
3. **Migration tests** with sample data
4. **Manual verification** of existing functionality

## Rollback Plan

1. Keep Ash resources intact (just unused)
2. Add feature flag to switch between stores
3. Migration script can run in reverse

## Questions for User

1. Should we keep Neo4j for graph analytics, or also migrate to iroh?
2. Should temporary rooms expire, or should all rooms be permanent?
3. Do you want P2P room sync between multiple server instances?

## Next Steps

1. Create `Sensocto.Iroh.RoomSync` module
2. Create `Sensocto.RoomStore` module
3. Update `Sensocto.Rooms` context
4. Test with existing UI
5. Run migration for existing rooms
