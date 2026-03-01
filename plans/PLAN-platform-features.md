# Platform Features Plan — Collaboration, Identity, Knowledge Graph & Economy

## Vision

Evolve Sensocto from a real-time sensor monitoring tool into a **collaborative platform** where users can vote on decisions, chat with each other (and AI agents), navigate rich profiles, persist complex relationships in a knowledge graph, and participate in a token-based economy.

---

## 1. Voting & Collaborative Decision-Making

### Current State
Nothing exists. A `Rating` UI component (1-5 stars) exists but is not wired to any backend.

### Design

**Ash Resources:**

```
Sensocto.Collaboration.Poll
  - id (uuid)
  - title (string)
  - description (string)
  - poll_type (:single_choice | :multiple_choice | :ranked | :weighted)
  - status (:draft | :open | :closed | :archived)
  - visibility (:public | :room | :private)
  - room_id (optional belongs_to Room)
  - creator_id (belongs_to User)
  - closes_at (utc_datetime, optional)
  - results_visible (:always | :after_close | :creator_only)
  - timestamps

Sensocto.Collaboration.PollOption
  - id (uuid)
  - poll_id (belongs_to Poll)
  - label (string)
  - position (integer)

Sensocto.Collaboration.Vote
  - id (uuid)
  - poll_id (belongs_to Poll)
  - option_id (belongs_to PollOption)
  - user_id (belongs_to User)
  - weight (integer, default 1) — for weighted/token-gated voting
  - timestamps
  - identity: unique on [poll_id, user_id, option_id] (prevent double-vote)
```

**Real-time:**
- PubSub topic: `"poll:#{poll_id}"` — broadcasts vote counts live
- LiveView component shows results updating in real-time (bar chart / pie)

**Token-Weighted Voting (Phase 2):**
- Users can stake tokens on votes (conviction voting)
- Weight field on Vote resource enables quadratic voting or token-weighted schemes

**Implementation Steps:**
1. Create `Sensocto.Collaboration` Ash domain with Poll, PollOption, Vote resources
2. Migration for `polls`, `poll_options`, `votes` tables
3. LiveComponent `PollComponent` — create poll form, vote UI, live results
4. Embed in chat sidebar + room views
5. PubSub integration for real-time result updates

---

## 2. User Identity & Navigation

### Current State
- User has only `email` + `id`. No display name, avatar, bio, or skills.
- `/settings` page shows email, ID, language picker. No profile page exists.
- Guest users have `display_name` via `GuestSession`.

### Design

**Extend User resource:**

```
# New attributes on Sensocto.Accounts.User
  - display_name (string, nullable) — falls back to email prefix
  - avatar_url (string, nullable) — URL or upload path
  - bio (string, nullable, max 500)
  - status_emoji (string, nullable) — e.g. "🎵" "🔬"
  - timezone (string, default "Europe/Berlin")
  - is_public (boolean, default true)

# New Ash resource
Sensocto.Accounts.UserSkill
  - user_id (belongs_to User)
  - skill_name (string) — e.g. "elixir", "biosignal-processing", "music"
  - level (:beginner | :intermediate | :expert)
  - endorsed_by_count (integer, computed aggregate)
```

**New Routes:**

```
GET /profile              → own profile (edit mode)
GET /users/:id            → public profile view
GET /users                → user directory (searchable, filterable by skill)
GET /dashboard            → personal dashboard (rooms, sensors, activity feed)
```

**Navigation Redesign:**
- Top nav: Home | Lobby | Rooms | Users | Dashboard
- User avatar dropdown (top-right): Profile, Settings, Sign Out
- Breadcrumb trail for nested views (Room > Sensor > Attribute)

**Activity Feed (Phase 2):**
- Track key events: joined room, started sensor, voted, sent chat message
- `Sensocto.Accounts.ActivityLog` resource — append-only event log
- Feed on dashboard + profile pages

**Implementation Steps:**
1. Add profile fields to User resource + migration
2. Create UserSkill resource + migration
3. Build `ProfileLive` (edit own) and `UserShowLive` (view others)
4. Build `UserDirectoryLive` with search/filter
5. Update nav component in `app.html.heex`
6. Create `DashboardLive` with activity summary

---

## 3. Chat — Persistence, Threads & AI Agents

### Current State
- Fully functional ephemeral chat (ETS, 24h TTL, 100 msgs/room)
- `@ai` triggers local Ollama streaming
- `ChatSidebarLive` + `ChatComponent` exist
- PubSub topic: `"chat:#{room_id}"`

### Design

**Phase 1 — Database Persistence:**

```
Sensocto.Chat.Message (Ash resource, PostgreSQL)
  - id (uuid)
  - room_id (string) — "global" or room UUID
  - user_id (belongs_to User, nullable for AI)
  - role (:user | :ai | :system)
  - content (string)
  - parent_id (self-referential, nullable) — for threads
  - ai_model (string, nullable) — which model responded
  - metadata (map, nullable) — structured data, tool calls, etc.
  - timestamps

  # Indexes: room_id + inserted_at, parent_id
```

- Migrate from ETS-only to DB + ETS cache (hot messages in ETS, history from DB)
- Load last N messages from DB on room entry, new messages via PubSub as before

**Phase 2 — Threads & Reactions:**

```
Sensocto.Chat.Reaction
  - message_id (belongs_to Message)
  - user_id (belongs_to User)
  - emoji (string)
  - identity: unique on [message_id, user_id, emoji]
```

- Thread UI: click reply → shows thread panel
- Unread counts per room (track last-read timestamp per user)

**Phase 3 — Altruistic AI Agents:**

Multiple AI personalities that join discussions with different perspectives:

```
Sensocto.Chat.AiAgent
  - id (string) — e.g. "scientist", "philosopher", "critic"
  - name (string) — "Dr. Signal", "The Philosopher", "Devil's Advocate"
  - system_prompt (text) — personality + expertise definition
  - model (string) — which LLM model to use
  - avatar_url (string)
  - trigger (:mention | :auto | :invited)
  - cooldown_seconds (integer) — prevent spamming
```

**AI Agent Behavior:**
- `@scientist` / `@philosopher` / `@critic` — triggers specific agent
- `@all-ai` — all agents respond (staggered, 2-5s apart)
- Auto-join mode: agents listen to conversation and chime in when their domain is relevant (keyword matching + LLM classification)
- Each agent has a personality-defining system prompt and domain expertise
- Agents can reference sensor data context (`SensorContext`) for informed responses
- Rate-limited per agent per room (cooldown)

**Cloud LLM Support:**
- Extend `Sensocto.AI.LLM` to support multiple backends: Ollama (local), Anthropic (Claude), OpenAI
- Config-driven: `config :sensocto, :ai_providers, [ollama: [...], anthropic: [...]]`
- Agent resource specifies which provider/model to use

**Implementation Steps:**
1. Create `Sensocto.Chat.Message` Ash resource + migration
2. Migrate `ChatStore` to use DB with ETS cache layer
3. Add `parent_id` for threading + thread UI
4. Create `Sensocto.Chat.Reaction` resource
5. Create `Sensocto.Chat.AiAgent` resource + seed data for 3-4 personalities
6. Build agent dispatch system (GenServer per active agent)
7. Add cloud LLM provider support

---

## 4. Knowledge Graph — Complex Relationship Persistence

### Current State
- PostgreSQL with Ash resources. Relationships: User→Room, Room→Sensor→Attribute
- Client-side Sigma.js graph for visualization only
- CozoDB was explored but commented out in `mix.exs`
- No skills, resources, or temporal relationships modeled

### Why a Graph DB?

The relationships we need to model:
- User **has_skill** Skill (with level, endorsements)
- User **owns/participates_in** Room
- User **uses** Sensor
- Sensor **produces** AttributeType
- Sensor **located_in** Room
- Room **requires_skill** Skill
- User **recorded** Recording **in** Room **at** Time
- User **voted_on** Poll
- User **earned** Token **for** Action
- Recording **contains** SensorData **of_type** AttributeType
- User **endorses** User **for** Skill

This is a highly interconnected graph with traversal queries like:
- "Find users with skill X who are available now"
- "What sensors are compatible with this room's requirements?"
- "Show me the collaboration history between these two users"
- "What's the shortest skill-path between this user and this project's needs?"

### Design Options

**Option A: CozoDB (Datalog engine, embedded)**
- Pros: Embedded (no separate server), Datalog queries are natural for graph traversal, supports time-travel queries, Rust-based (fast), has an Elixir binding
- Cons: Less mature ecosystem, Elixir binding is community-maintained, no Ash integration
- Best for: Complex recursive queries, temporal data, rule-based reasoning

**Option B: PostgreSQL with recursive CTEs + materialized views**
- Pros: No new dependency, works with Ash, battle-tested
- Cons: Graph traversals are verbose (recursive CTEs), no native path queries
- Best for: Simple relationship modeling, if graph complexity stays moderate

**Option C: Apache AGE (PostgreSQL extension for graph)**
- Pros: Adds Cypher query support to existing PostgreSQL, no separate server
- Cons: Extension management, limited Ash integration, fewer Elixir bindings
- Best for: If we want graph queries without leaving PostgreSQL

**Recommendation: Hybrid — PostgreSQL (Ash) for entities + CozoDB for graph traversals**

Use PostgreSQL/Ash as the source of truth for all resources (users, rooms, sensors, skills, recordings, tokens). Sync relevant relationships into CozoDB for complex graph queries. CozoDB excels at:
- Datalog rules (transitive skill matching, recommendation engines)
- Temporal queries (what did the graph look like at time T?)
- Recursive traversals (degrees of separation, skill paths)

### Schema (PostgreSQL/Ash side)

```
# New Ash domain: Sensocto.Knowledge

Sensocto.Knowledge.Skill
  - id (uuid)
  - name (string, unique)
  - category (string) — "technical", "biosignal", "music", "research"
  - description (string)

Sensocto.Knowledge.Recording
  - id (uuid)
  - name (string)
  - room_id (belongs_to Room)
  - creator_id (belongs_to User)
  - started_at (utc_datetime)
  - ended_at (utc_datetime)
  - duration_seconds (integer)
  - sensor_ids (array of uuid) — which sensors participated
  - metadata (map) — attribute types captured, sample rates, etc.

Sensocto.Knowledge.ResourceTag
  - id (uuid)
  - resource_type (string) — "room", "sensor", "recording", "user"
  - resource_id (uuid)
  - tag (string) — freeform tagging
```

### CozoDB Graph Schema (Datalog relations)

```
# Entities (synced from PostgreSQL)
:user {id: String, name: String, email: String}
:skill {id: String, name: String, category: String}
:room {id: String, name: String}
:sensor {id: String, name: String, type: String}
:recording {id: String, name: String, started: Int, ended: Int}

# Relationships
:has_skill {user_id: String, skill_id: String, level: String}
:endorses {endorser_id: String, user_id: String, skill_id: String, at: Int}
:member_of {user_id: String, room_id: String, role: String}
:room_needs_skill {room_id: String, skill_id: String, level: String}
:sensor_in_room {sensor_id: String, room_id: String, since: Int}
:recorded_by {recording_id: String, user_id: String}
:recording_in_room {recording_id: String, room_id: String}
:recording_has_sensor {recording_id: String, sensor_id: String}
:earned_token {user_id: String, amount: Int, reason: String, at: Int}
```

### Sync Strategy
- Ash `after_action` callbacks on creates/updates push to CozoDB
- Periodic full sync job (every 5 min) ensures consistency
- CozoDB runs embedded in the BEAM via NIF

**Implementation Steps:**
1. Add CozoDB dependency, get Elixir binding working
2. Create `Sensocto.Knowledge` domain with Skill, Recording, ResourceTag
3. Build sync layer: Ash notifiers → CozoDB
4. Create graph query API module (`Sensocto.Knowledge.Graph`)
5. Build graph explorer LiveView (extend existing Sigma.js view)
6. Add temporal queries for "state at time T"

---

## 5. Economy — Tokens, Bitcoin & Incentives

### Current State
Nothing exists.

### Design

**Internal Token: "Sense Tokens" (SNS)**

A platform currency earned through participation, spendable on premium features or convertible to Bitcoin via Lightning Network.

```
Sensocto.Economy.Wallet
  - id (uuid)
  - user_id (belongs_to User, unique)
  - balance (integer) — SNS tokens (integer to avoid float rounding)
  - lifetime_earned (integer)
  - lifetime_spent (integer)
  - timestamps

Sensocto.Economy.Transaction
  - id (uuid)
  - wallet_id (belongs_to Wallet)
  - amount (integer) — positive = credit, negative = debit
  - balance_after (integer) — snapshot for audit trail
  - type (:earn | :spend | :transfer | :deposit | :withdrawal)
  - reason (string) — human-readable
  - reference_type (string, nullable) — "vote", "chat_message", "recording", etc.
  - reference_id (uuid, nullable) — the entity that triggered this
  - counterparty_wallet_id (uuid, nullable) — for transfers
  - timestamps
```

**Earning Mechanisms:**
| Action | Reward (SNS) |
|--------|-------------|
| Daily login | 10 |
| Send chat message | 1 |
| Create a poll | 5 |
| Vote on a poll | 2 |
| Start a recording session | 10 |
| Share a recording | 15 |
| Get a skill endorsement | 20 |
| AI agent triggered by your message | 3 |
| Contribute sensor data (per hour) | 5 |

**Spending Mechanisms:**
| Action | Cost (SNS) |
|--------|-----------|
| Create private room | 50 |
| Weighted vote (extra weight) | variable |
| Priority AI response | 10 |
| Extended recording storage | 20/month |
| Custom AI agent personality | 100 |

**Bitcoin Integration (Phase 2):**

```
Sensocto.Economy.BitcoinWallet
  - id (uuid)
  - user_id (belongs_to User)
  - lightning_address (string, nullable) — e.g. user@getalby.com
  - onchain_address (string, nullable) — for larger amounts
  - last_withdrawal_at (utc_datetime, nullable)

Sensocto.Economy.ExchangeRate
  - id (uuid)
  - sns_per_sat (integer) — how many SNS = 1 satoshi
  - effective_at (utc_datetime)
```

**Lightning Network Integration:**
- Use LNbits or BTCPay Server API for Lightning payments
- Deposit: User pays Lightning invoice → SNS credited at exchange rate
- Withdrawal: User requests withdrawal → platform pays their Lightning address
- Minimum withdrawal: 1000 SNS
- Hex packages: `bitcoinex` for address validation, HTTP client for LNbits API

**Security Considerations:**
- All balance mutations through `Transaction` resource (append-only ledger)
- Double-entry: every transfer creates two transactions (debit + credit)
- Wallet balance is computed from transaction sum (verify periodically)
- Rate limiting on earning actions (prevent gaming)
- Withdrawal cooldown + daily limits

**Implementation Steps:**
1. Create `Sensocto.Economy` domain with Wallet, Transaction resources
2. Build `EconomyService` GenServer for atomic balance operations
3. Create earning hooks (Ash notifiers on Chat.Message, Vote, etc.)
4. Build wallet UI in profile/dashboard
5. Phase 2: LNbits integration for Lightning deposits/withdrawals
6. Phase 2: Exchange rate management

---

## 6. Essential Supporting Features

### 6a. Notifications System

```
Sensocto.Notifications.Notification
  - id (uuid)
  - user_id (belongs_to User)
  - type (:vote_result | :chat_mention | :endorsement | :token_earned | :room_invite)
  - title (string)
  - body (string)
  - read (boolean, default false)
  - action_url (string, nullable)
  - metadata (map)
  - timestamps
```

- PubSub: `"notifications:#{user_id}"` for real-time delivery
- Bell icon in nav with unread count badge
- Toast notifications for high-priority items

### 6b. Search

- Full-text search across: users (name, skills), rooms (name, description), chat messages, polls, recordings
- PostgreSQL `tsvector` + GIN indexes (no external search engine needed initially)
- `/search?q=...` route with tabbed results (Users | Rooms | Messages | Recordings)

### 6c. Permissions & Authorization

Extend existing room roles for new features:
- Room owner: can create polls, manage AI agents, control economy settings
- Room admin: can moderate chat, close polls
- Room member: can vote, chat, trigger AI
- Public viewer: read-only access to public rooms

Use Ash authorization policies throughout.

### 6d. Recording System

The Knowledge graph includes Recordings, but we also need the capture mechanism:

- "Record" button in room view → captures all sensor data streams for duration
- Stores metadata in PostgreSQL, raw data in `AttributeStoreTiered` warm tier (or S3 for long-term)
- Playback: re-stream recorded data through the same visualization pipeline
- Export: CSV, JSON, or domain-specific formats

---

## Implementation Phases

### Phase 1 — Foundation (4-6 weeks)
1. **User profiles** — Add fields, profile page, user directory
2. **Chat persistence** — Migrate to DB, add threading
3. **Navigation overhaul** — New routes, updated nav, breadcrumbs
4. **Notifications** — Basic notification system
5. **Wallet & Tokens** — Internal economy, earning/spending

### Phase 2 — Collaboration (4-6 weeks)
1. **Voting system** — Polls, real-time results
2. **AI agents** — Multiple personalities, auto-join
3. **Skill system** — User skills, endorsements
4. **Search** — Full-text across entities
5. **Recording** — Capture and playback

### Phase 3 — Knowledge Graph (4-6 weeks)
1. **CozoDB integration** — Embedded graph engine
2. **Sync layer** — Ash → CozoDB
3. **Graph queries** — Skill matching, recommendations
4. **Graph explorer** — Extended Sigma.js visualization
5. **Temporal queries** — Historical state navigation

### Phase 4 — Economy & Bitcoin (4-6 weeks)
1. **Bitcoin wallet** — Lightning address integration
2. **LNbits/BTCPay** — Deposit/withdrawal flows
3. **Token-weighted voting** — Conviction voting with SNS
4. **Marketplace** — Trade recordings, AI agent configs
5. **Exchange rate** — SNS ↔ sats pricing

---

## Technical Decisions Needed

| Decision | Options | Recommendation |
|----------|---------|---------------|
| Graph DB | CozoDB / PostgreSQL-only / Apache AGE | CozoDB (embedded, temporal queries) |
| Cloud LLM | Anthropic / OpenAI / both | Anthropic (Claude) primary, Ollama fallback |
| Bitcoin layer | LNbits / BTCPay / custom | LNbits (simpler API, self-hosted) |
| File storage | Local / S3 / both | S3 for recordings, local for dev |
| Search | PostgreSQL FTS / Meilisearch | PostgreSQL FTS (simplicity first) |
| Real-time voting | PubSub / LiveView streams | PubSub + LiveView (consistent with existing patterns) |

---

## New Dependencies

```elixir
# mix.exs additions (by phase)

# Phase 1
# (no new deps — Ash + PostgreSQL cover it)

# Phase 2
# (possibly cloud LLM client)
{:req, "~> 0.5"}  # already likely present for HTTP

# Phase 3
{:cozodb, git: "https://github.com/leapsight/cozodb.git"}

# Phase 4
{:bitcoinex, "~> 0.2"}  # Bitcoin address validation
# LNbits accessed via HTTP API (Req)
```

---

## Database Migration Count Estimate

- Phase 1: ~5 migrations (user profile fields, chat messages, notifications, wallets, transactions)
- Phase 2: ~4 migrations (polls, poll_options, votes, reactions, ai_agents, skills)
- Phase 3: ~2 migrations (recordings, resource_tags)
- Phase 4: ~2 migrations (bitcoin_wallets, exchange_rates)
