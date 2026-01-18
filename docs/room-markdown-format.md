# Room Markdown Format

Rooms in Sensocto can be represented as markdown files with YAML frontmatter. This format enables:

- **P2P synchronization** via Iroh gossip and Automerge CRDTs
- **Offline-first storage** with eventual consistency
- **Human-readable backups** stored in Tigris (S3-compatible)
- **Version control friendly** structure

## File Structure

```
rooms/
  {room-id}/
    room.md           # Main room document
    versions/
      2025-01-17T12-00-00Z.md  # Version history
```

## Document Format

A room document consists of two parts:

1. **YAML Frontmatter** - Structured metadata between `---` delimiters
2. **Markdown Body** - Custom content for the room

### Complete Example

```markdown
---
id: "550e8400-e29b-41d4-a716-446655440000"
name: "Engineering Team Room"
description: "Daily standups and collaboration"
owner_id: "user-uuid-12345"
join_code: "ABC12345"
version: 42
created_at: "2025-01-15T09:00:00Z"
updated_at: "2025-01-17T14:30:00Z"

features:
  is_public: false
  calls_enabled: true
  media_playback_enabled: true
  object_3d_enabled: false

admins:
  signature: "base64-encoded-ed25519-signature"
  updated_by: "admin-uuid-67890"
  members:
    - id: "user-uuid-12345"
      role: owner
    - id: "admin-uuid-67890"
      role: admin
    - id: "member-uuid-11111"
      role: member

configuration:
  theme: "dark"
  layout: "grid"
  max_participants: 50
---

# Engineering Team Room

Welcome to our team collaboration space!

## Quick Links

- [Sprint Board](https://...)
- [Documentation](https://...)

## Room Rules

1. Mute when not speaking
2. Use reactions for quick feedback

<!-- PROTECTED:admin_notes -->
Admin-only notes: Budget approved for Q2 expansion.
<!-- /PROTECTED:admin_notes -->
```

## Frontmatter Fields

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID string | Unique room identifier |
| `name` | string | Room display name (1-100 chars) |
| `owner_id` | UUID string | User ID of room owner |
| `join_code` | string | 8-char alphanumeric code for joining |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | string | `null` | Room description (max 500 chars) |
| `version` | integer | `1` | Document version for conflict resolution |
| `created_at` | ISO 8601 | now | Creation timestamp |
| `updated_at` | ISO 8601 | now | Last modification timestamp |

### Features Object

Controls room capabilities:

```yaml
features:
  is_public: true           # Visible in public room list
  calls_enabled: true       # Voice/video calls allowed
  media_playback_enabled: true  # Synchronized media playback
  object_3d_enabled: false  # 3D object viewing (Gaussian splats)
```

| Feature | Type | Default | Description |
|---------|------|---------|-------------|
| `is_public` | boolean | `true` | Room visibility |
| `calls_enabled` | boolean | `true` | WebRTC calls |
| `media_playback_enabled` | boolean | `true` | YouTube/media sync |
| `object_3d_enabled` | boolean | `false` | 3D splat viewer |

### Admins Object

Manages room membership and permissions:

```yaml
admins:
  signature: "base64-sig"   # Ed25519 signature (see Admin Protection)
  updated_by: "user-id"     # Who last modified admin section
  members:
    - id: "user-uuid"
      role: owner           # owner | admin | member
```

#### Member Roles

| Role | Permissions |
|------|-------------|
| `owner` | Full control, cannot be removed, can delete room |
| `admin` | Manage members, update settings, moderate |
| `member` | Participate, view content |

### Configuration Object

Extensible key-value settings:

```yaml
configuration:
  theme: "dark"
  layout: "grid"
  custom_css: null
  max_participants: 100
  welcome_message: "Hello!"
```

Configuration is freeform - add any settings your application needs.

## Markdown Body

The body section supports standard GitHub-flavored Markdown:

- Headers, lists, links, images
- Code blocks with syntax highlighting
- Tables
- Task lists

### Protected Sections

Use HTML comments to mark admin-only content:

```markdown
<!-- PROTECTED:section_name -->
Content only admins can edit.
Changes to this section require signature verification.
<!-- /PROTECTED:section_name -->
```

Protected sections are:
- Visible to all members
- Editable only by owners/admins
- Verified during CRDT merge

## Admin Protection (Signatures)

Admin section changes are cryptographically signed to prevent unauthorized modifications in P2P sync.

### Signature Format

The signature covers a canonical message:

```
{room_id}:{sorted_member_ids_with_roles}:{timestamp}
```

Example:
```
550e8400-e29b-41d4-a716-446655440000:admin-uuid:admin,member-uuid:member,user-uuid:owner:2025-01-17T14:30:00Z
```

### Verification Flow

1. Peer receives CRDT update with admin changes
2. Extract `signature` and `updated_by` from admins section
3. Look up signer's public key
4. Verify signature against canonical message
5. Reject merge if signature invalid

### Key Generation

```elixir
# Generate keypair for a user
{public_key, private_key} = Sensocto.RoomMarkdown.AdminProtection.generate_keypair()

# Store public key with user profile
encoded = AdminProtection.encode_public_key(public_key)
```

## Storage Locations

### Tigris (S3) Structure

```
bucket/
  rooms/
    {room-id}/
      room.md                    # Current version
      versions/
        2025-01-17T12-00-00Z.md  # Historical versions
```

### PostgreSQL (Index)

PostgreSQL maintains a searchable index with:
- Room metadata for queries
- Membership for access control
- Join codes for lookup

The markdown format is authoritative; PostgreSQL is synchronized.

## CRDT Synchronization

Room documents sync via Automerge CRDT over Iroh gossip:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Client A   │◄───►│   Gossip     │◄───►│  Client B   │
│ (Automerge) │     │   Topic      │     │ (Automerge) │
└─────────────┘     └──────────────┘     └─────────────┘
       │                                        │
       ▼                                        ▼
┌─────────────┐                         ┌─────────────┐
│   Tigris    │                         │   Tigris    │
│  (Backup)   │                         │  (Backup)   │
└─────────────┘                         └─────────────┘
```

### Gossip Topics

Each room has a dedicated topic: `room:{room_id}:crdt`

### Message Types

| Type | Code | Description |
|------|------|-------------|
| `crdt_update` | `0x01` | Automerge document bytes |
| `document_update` | `0x02` | Full JSON document |
| `sync_request` | `0x03` | Request full state from peers |

## Version History

Versions are saved:
- Before significant changes
- Periodically by backup worker
- On explicit save

Filename format: `{ISO8601-timestamp}.md` with colons replaced by dashes.

## Parsing & Serialization

### Elixir API

```elixir
alias Sensocto.RoomMarkdown.{Parser, Serializer, RoomDocument}

# Parse markdown to struct
{:ok, doc} = Parser.parse(markdown_string)

# Create from attributes
doc = RoomDocument.new(%{
  name: "My Room",
  owner_id: "user-uuid"
})

# Serialize to markdown
markdown = Serializer.serialize(doc)

# Serialize to JSON (for CRDT)
json = Serializer.to_json(doc)

# Get storage key
key = Serializer.storage_key(doc)  # "rooms/{id}/room.md"
```

### Converting from RoomStore

```elixir
# From in-memory store format
room_data = %{
  id: "uuid",
  name: "Room",
  members: %{"user-1" => :owner, "user-2" => :member}
}

doc = RoomDocument.from_room_store(room_data)

# Back to store format
store_data = RoomDocument.to_room_store(doc)
```

## Migration

### PostgreSQL to Tigris

```elixir
alias Sensocto.RoomMarkdown.Migration

# Migrate all rooms
{:ok, %{migrated: 42, failed: 0}} = Migration.migrate_all_to_tigris()

# Migrate single room
{:ok, room_id} = Migration.migrate_room_to_tigris("room-uuid")

# Generate migration report
report = Migration.generate_report()
# %{
#   total_rooms: 100,
#   in_memory: 95,
#   in_postgres: 100,
#   in_tigris: 80,
#   in_all_three: 75
# }
```

### Restore from Tigris

```elixir
# Restore all rooms (disaster recovery)
{:ok, %{restored: 80}} = Migration.restore_all_from_tigris()

# Restore single room
{:ok, doc} = Migration.restore_room_from_tigris("room-uuid")
```

## Configuration

### Environment Variables

```bash
# Tigris Storage
TIGRIS_BUCKET=my-bucket
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
TIGRIS_ENDPOINT=https://fly.storage.tigris.dev  # optional

# Backup Worker
BACKUP_INTERVAL_MS=300000  # 5 minutes
BACKUP_BATCH_SIZE=10
```

### Fly.io Setup

```bash
# Create Tigris bucket (auto-configures credentials)
fly storage create

# Credentials are auto-injected as:
# - BUCKET_NAME
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_ENDPOINT_URL_S3
```

## Best Practices

1. **Version bumping**: Call `RoomDocument.bump_version/1` before saving changes
2. **Signature freshness**: Re-sign admin sections when members change
3. **Backup frequency**: Default 5 minutes balances durability and cost
4. **Body content**: Keep markdown body lightweight; use links for large content
5. **Configuration**: Use typed values when possible for CRDT compatibility
