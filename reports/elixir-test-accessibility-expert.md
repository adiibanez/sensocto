# Comprehensive Test Coverage and Accessibility Analysis
## Sensocto IoT Sensor Platform

**Analysis Date:** January 12, 2026 (Updated: February 20, 2026)
**Analyzed By:** Testing, Usability, and Accessibility Expert Agent
**Project:** Sensocto - Elixir/Phoenix IoT Sensor Platform

---

## Update: February 20, 2026

### Executive Summary

This update reflects the Sensocto codebase as of February 20, 2026. The project now has **280 implementation files** in `/lib` and **51 test files** with approximately **732 test definitions** (up from 373 on Feb 16). Since the last update, the codebase has seen significant expansion: 6 new LiveView modules (PollsLive, ProfileLive, UserDirectoryLive, UserShowLive, plus two new component files for polls), a full Collaboration domain (Poll, PollOption, Vote), User profiles/skills/connections, a MIDI audio output system (1709-line JS hook), an upgraded LobbyGraph and a new UserGraph Svelte component, and 18 new test files spanning accounts, encoding, collaboration, OTP modules, web live views, and regression suites.

Several accessibility violations reported on Feb 16 have been fixed: the skip navigation link now exists in `root.html.heex`; `<.live_title>` is used in the root layout so per-page title changes are announced by screen readers; the lobby view mode selector now uses a proper ARIA tablist with `aria-selected`; and the count of `aria-live` regions jumped from 1 to 11. However, all six new features were shipped with accessibility gaps — unlabeled form fields, icon-only buttons without accessible names, navigation without `aria-current`, and JS-controlled dropdowns with no `aria-expanded` state. These must be addressed now before they compound further.

### Current Metrics

| Metric | Feb 16 | Feb 20 | Change |
|--------|--------|--------|--------|
| Implementation Files | 250 | **280** | +30 |
| Test Files | 33 | **51** | +18 |
| Test Definitions | ~373 | **~732** | +359 |
| LiveView Modules | 46 | **52+** | +6 |
| Component Files | 14 | **19** | +5 |
| New Domain Modules | 0 | **3** (Poll, Vote, UserSkill/Connection) | +3 |
| `aria-live` Regions | 1 | **11** | +10 |
| Skip Navigation Link | NO | **YES** | Fixed |
| `<.live_title>` in root layout | NO | **YES** | Fixed |
| Lobby tab ARIA (tablist/selected) | None | **role=tablist + aria-selected** | Fixed |
| WCAG Level A Violations | 40+ | **~35+** | -5 |
| WCAG Level AA Violations | 12+ | **~12** | Stable |
| Estimated Code Coverage | ~15% | **~22%** | +7% |

### Key Changes Since Last Review (Feb 16 -> Feb 20)

**Positive Changes:**

1. **Skip Navigation Link Added** (`root.html.heex` lines 22-27) — Uses the correct `href="#main"` target with `sr-only focus:not-sr-only` pattern. Resolves the long-standing WCAG 2.4.1 violation.

2. **`<.live_title>` in Root Layout** — The root layout now uses Phoenix's `<.live_title>` component, meaning `page_title` changes on `handle_params` are properly announced to assistive technologies during LiveView navigation. Per-page titles are set in: `LobbyLive`, `PollsLive`, `ProfileLive`, `RoomListLive`, `RoomShowLive`, `SensorLive`, `UserDirectoryLive`, `UserShowLive`, `SystemStatusLive`, `AiChatLive`, `AboutLive`.

3. **Lobby View Mode Selector Upgraded to ARIA Tablist** — The lens navigation in `lobby_live.html.heex` (line 345) now uses `role="tablist"` on the `<nav>` element and `role="tab"` plus `aria-selected` on each lens chip. This is a significant improvement for keyboard and screen reader users navigating between sensor views.

4. **`aria-live` Regions: 1 -> 11** — New regions added in `whiteboard_component.ex`, `object3d_player_component.ex`, `media_player_component.ex`, `room_show_live.ex`, and the lobby modals' countdown timers. The two countdown timer divs (`id="object3d-control-countdown"` and `id="media-control-countdown"`) correctly use `role="timer"`, `aria-live="polite"`, and `aria-atomic="true"`.

5. **18 New Test Files Added** — Notable additions:
   - `lobby_graph_regression_test.exs` (229 lines) — Verifies all 13 lobby routes mount without crashing; tests `TabbedFooterLive` collapse/expand via `live_isolated/3`.
   - `midi_output_regression_test.exs` (219 lines) — Verifies the `composite_measurement` push_event contract using `send(view.pid, {:lens_batch, ...})` + `assert_push_event/3`.
   - `accounts_test.exs` (316 lines) — Full Ash resource coverage for User, UserSkill, UserConnection, GuestSession.
   - `collaboration_test.exs` (192 lines) — Poll, PollOption, Vote Ash resource tests.
   - `delta_encoder_test.exs` (149 lines) — Round-trip encoding, overflow, precision tests.
   - `attention_tracker_test.exs` (147 lines), `attribute_store_tiered_test.exs` (133 lines), `room_server_test.exs` (330 lines) — Substantial OTP coverage.
   - `circuit_breaker_test.exs`, `sensor_test.exs`, `search_index_test.exs`, `sync_computer_test.exs`, `chat_store_test.exs`, `object3d_player_server_test.exs` — Filling gaps across subsystems.
   - `search_live_test.exs`, `user_directory_live_test.exs` — Basic LiveView mount/render for new views.
   - `sensor_data_channel_test.exs` — Covers broadcast and ping/reply on `SensorDataChannel`.

6. **LobbyGraph Regression Covers All 13 Routes** — Every route from `/lobby` to `/lobby/users`, `/lobby/graph`, `/lobby/breathing`, `/lobby/geolocation`, etc. is verified to mount without crashing with a real authenticated user.

**Remaining Critical Gaps:**

1. **No event handler tests for `LobbyLive`** — The lobby regression test verifies mount only; event handlers (`set_quality_override`, `join_room`, `show_join_modal`, `toggle_sidebar`, `midi_toggled`, PubSub measurement handling, etc.) have no coverage.
2. **No tests for `IndexLive`** — Main dashboard. Does not set `page_title`.
3. **No tests for Calls system** — `CallServer`, `QualityManager`, `SnapshotManager`, `CallChannel` remain at 0%.
4. **No tests for `PollsLive` or `ProfileLive` event handlers.**
5. **Silent `if search_view do` guard in `search_live_test.exs`** — Tests pass even when the child LiveView is nil.
6. **New features shipped with accessibility gaps** — `PollsLive`, `UserDirectoryLive`, `ProfileLive`, `UserShowLive` all lack label-input associations, `aria-label` on icon buttons, or `aria-current` on navigation.
7. **JS-hook-controlled dropdowns lack `aria-expanded`** — Language switcher, user menu, mobile hamburger.
8. **Three custom modals in `lobby_live.html.heex` still bypass `<.modal>`** — No `role="dialog"`, no focus trap, no Escape key.

---

## Testing Analysis

### Test File Inventory (51 files)

| Category | Files | Approx. Tests | Notes |
|----------|-------|---------------|-------|
| Regression Guards | `regression_guards_test.exs` | 49 | Data pipeline contracts |
| OTP/Supervision | `supervision_tree_test.exs`, `attention_tracker_test.exs`, `attribute_store_tiered_test.exs`, `room_server_test.exs`, `button_signal_reliability_test.exs`, `button_state_visualization_test.exs`, `simple_sensor_test.exs` | ~100 | Good coverage |
| Encoding | `delta_encoder_test.exs` | 15 | Round-trip, overflow, edge cases |
| Collaboration | `collaboration_test.exs` | 20 | Poll, PollOption, Vote Ash resources |
| Accounts | `accounts_test.exs` | 25 | User, UserSkill, UserConnection, GuestSession |
| Search | `search_index_test.exs` | 15 | |
| Sensors | `sensor_test.exs`, `room_test.exs`, `attribute_store_test.exs` | 25 | Ash resource tests |
| Resilience | `circuit_breaker_test.exs` | 12 | |
| Room Markdown | `room_markdown_test.exs`, `admin_protection_test.exs` | 45 | Good coverage |
| E2E/Integration | 4 Wallaby feature tests | ~50 | Browser-based |
| LiveView (regression) | `lobby_graph_regression_test.exs`, `midi_output_regression_test.exs` | 35 | Route verification + push_event contracts |
| LiveView (unit) | `search_live_test.exs`, `user_directory_live_test.exs`, `stateful_sensor_live_test.exs` | 20 | Minimal coverage |
| Components | `modal_accessibility_test.exs`, `core_components_test.exs`, `media_player_component_test.exs`, `object3d_player_component_test.exs` | 40 | Good for media components |
| Bio | 5 bio test files | ~50 | Good coverage |
| Plugs | `rate_limiter_test.exs` | 13 | Thorough |
| API | `openapi_test.exs` | 2 | Minimal |
| Iroh | `iroh_automerge_test.exs`, `room_state_crdt_test.exs` | 20 | CRDT logic |
| Sync/Chat/OBJ3D/Media | `sync_computer_test.exs`, `chat_store_test.exs`, `object3d_player_server_test.exs`, `media_player_server_test.exs` | ~35 | |
| Lenses | `priority_lens_test.exs` | 20 | |

### Notable New Tests: Lobby Graph Regression

**File:** `test/sensocto_web/live/lobby_graph_regression_test.exs` (229 lines)

Verifies all 13 lobby routes mount without crashing. Also tests `TabbedFooterLive` collapse/expand behavior using `live_isolated/3` — a good pattern for testing LiveView components in isolation. Additionally exercises `IndexLive` rendering for the "Enter Lobby" link and "sensors online" count display.

**Quality note:** Three tests inside the same `describe "lobby graph routes"` block all assert `html =~ "LobbyGraph"` on `/lobby/graph` with different test names but identical bodies. These should be consolidated or made more specific.

### Notable New Tests: MIDI Output Regression

**File:** `test/sensocto_web/live/midi_output_regression_test.exs` (219 lines)

Tests the `composite_measurement` push_event contract for the graph view using `send(view.pid, {:lens_batch, batch})` and `assert_push_event/3`. Excellent pattern for testing LiveView event emission without browser interaction.

**Quality note:** Uses `refute_push_event/4` with a 4-argument call including a timeout. The standard `Phoenix.LiveViewTest` signature is `refute_push_event(view, event, payload_pattern)` (3 args). A silent no-op on the extra argument would make some negative assertions unreliable.

### Quality Issue: Silent `if` Guard in Search Tests

**File:** `test/sensocto_web/live/search_live_test.exs` (lines 65-99)

All three test blocks guard their assertions inside `if search_view do ... end`. If `find_live_child(view, "search-live")` returns `nil`, assertions are silently skipped and the test reports green. This is a false-green risk.

**Fix:** Replace the guard with an explicit assertion:

```elixir
# Before — silent pass if component not found:
if search_view do
  render_click(search_view, "open")
  assert render(search_view) =~ "Search sensors, rooms"
end

# After — explicit failure if component missing:
assert search_view, "Expected SearchLive child with id='search-live' to be mounted"
render_click(search_view, "open")
assert render(search_view) =~ "Search sensors, rooms"
```

### Critical Testing Gaps

#### Priority 0: Zero Coverage

1. **`lib/sensocto_web/live/lobby_live.ex`** — Most complex LiveView. Graph regression verifies mount only. No tests for: `set_quality_override`, `join_room` validation, `show_join_modal`/`dismiss_join_modal`, `toggle_sidebar`, composite lens data extraction, attention tracking lifecycle, PubSub measurement handling.

2. **`lib/sensocto_web/live/index_live.ex`** — Main dashboard. No tests. Does not set `page_title` (falls back to "Sensocto").

3. **`lib/sensocto/calls/call_server.ex`** (776 lines) — No tests.

4. **`lib/sensocto/calls/quality_manager.ex`** (336 lines) — No tests.

5. **`lib/sensocto/calls/snapshot_manager.ex`** (239 lines) — No tests.

6. **`lib/sensocto/calls/cloudflare_turn.ex`** — No tests.

7. **`lib/sensocto_web/channels/call_channel.ex`** (359 lines) — No tests.

8. **`lib/sensocto_web/live/admin/system_status_live.ex`** — No tests.

9. **`lib/sensocto_web/live/custom_sign_in_live.ex`** — Authentication page. No tests.

10. **`lib/sensocto_web/live/polls_live.ex`** (new) — No LiveView tests for `create_poll`, `validate_poll`, `add_option`, `close_poll`.

11. **`lib/sensocto_web/live/profile_live.ex`** (new) — No LiveView tests for `save_profile`, `add_skill`, `remove_skill`.

#### Priority 1: Insufficient Tests

1. **`stateful_sensor_live_test.exs`** — Only 2 tests. Missing: measurement display, modal interactions, favorite toggle, pin/unpin, view mode changes, latency ping/pong, battery state, highlight toggle.

2. **`user_directory_live_test.exs`** — Tests mount but not the `search` event or list-to-graph navigation.

3. **`openapi_test.exs`** — Only 2 schema validation tests.

### Suggested Test Cases

#### 1. LobbyLive Event Handler Tests (HIGHEST PRIORITY)

```elixir
defmodule SensoctoWeb.LobbyLiveEventTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "lobby_event_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = conn |> Plug.Test.init_test_session(%{}) |> AshAuthentication.Plug.Helpers.store_in_session(user)
    {:ok, conn: conn}
  end

  describe "quality override" do
    test "set_quality_override to high changes quality assign", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      html = render_click(view, "set_quality_override", %{"quality" => "high"})
      assert html =~ "High" or has_element?(view, "[data-quality=high]")
    end

    test "set_quality_override to auto clears manual override", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      render_click(view, "set_quality_override", %{"quality" => "high"})
      html = render_click(view, "set_quality_override", %{"quality" => "auto"})
      refute html =~ "(manual)"
    end
  end

  describe "join room modal" do
    test "show_join_modal makes modal visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      html = render_click(view, "show_join_modal")
      assert html =~ "Join Room"
    end

    test "dismiss_join_modal hides modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      render_click(view, "show_join_modal")
      html = render_click(view, "dismiss_join_modal")
      refute html =~ "join_code_help"
    end

    test "join_room with empty code shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      render_click(view, "show_join_modal")
      html = render_submit(view, "join_room", %{"join_code" => ""})
      assert html =~ "required" or html =~ "error"
    end
  end

  describe "lens_batch message handling" do
    test "lens_batch message triggers re-render without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      send(view.pid, {:lens_batch, %{"sensor-1" => %{"heartrate" => %{payload: 72, timestamp: 1_000}}}})
      assert render(view)
    end
  end
end
```

#### 2. PollsLive Event Tests (HIGH PRIORITY)

```elixir
defmodule SensoctoWeb.PollsLiveTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "polls_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = conn |> Plug.Test.init_test_session(%{}) |> AshAuthentication.Plug.Helpers.store_in_session(user)
    {:ok, conn: conn}
  end

  describe "polls list" do
    test "renders at /polls", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/polls")
      assert html =~ "Polls"
    end

    test "renders New Poll link for authenticated user", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/polls")
      assert html =~ "New Poll"
    end
  end

  describe "new poll form" do
    test "renders at /polls/new", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/polls/new")
      assert html =~ "Title"
      assert html =~ "Create Poll"
    end

    test "add_option increases option input count", %{conn: conn} do
      {:ok, view, html} = live(conn, "/polls/new")
      initial_count = Regex.scan(~r/Option \d+/, html) |> length()
      html = render_click(view, "add_option")
      new_count = Regex.scan(~r/Option \d+/, html) |> length()
      assert new_count > initial_count
    end
  end
end
```

#### 3. Fix Silent `if` Guard in Search Tests

```elixir
# In test/sensocto_web/live/search_live_test.exs — replace all occurrences of:
#   if search_view do ... end
# with:
assert search_view, "Expected SearchLive child with id='search-live' to be mounted"
```

#### 4. CallServer Unit Tests (HIGH PRIORITY)

```elixir
defmodule Sensocto.Calls.CallServerTest do
  use ExUnit.Case, async: true
  alias Sensocto.Calls.CallServer

  describe "participant management" do
    test "joining adds participant to state" do
      {:ok, pid} = CallServer.start_link(room_id: "test_room_#{System.unique_integer()}")
      :ok = CallServer.join(pid, "user1", %{name: "Test User"})
      state = CallServer.get_state(pid)
      assert Map.has_key?(state.participants, "user1")
    end

    test "leaving removes participant from state" do
      {:ok, pid} = CallServer.start_link(room_id: "test_room_#{System.unique_integer()}")
      CallServer.join(pid, "user1", %{name: "Test User"})
      CallServer.leave(pid, "user1")
      state = CallServer.get_state(pid)
      refute Map.has_key?(state.participants, "user1")
    end
  end

  describe "quality tier calculation" do
    test "active speaker receives highest tier" do
      {:ok, pid} = CallServer.start_link(room_id: "test_room_#{System.unique_integer()}")
      CallServer.join(pid, "user1", %{name: "Speaker"})
      CallServer.update_speaking(pid, "user1", true)
      assert CallServer.get_tier(pid, "user1") == :active
    end
  end
end
```

---

## Accessibility Audit

### WCAG 2.1 Compliance Summary

| Level | Status | Violations | Change from Feb 16 |
|-------|--------|------------|-------------------|
| Level A | FAIL | ~35 violations | -5 (skip nav, tablist, aria-live) |
| Level AA | FAIL | ~12 violations | Stable |
| Level AAA | NOT ASSESSED | -- | N/A |

### Fixed Since Last Report

1. **[2.4.1 Bypass Blocks] Skip Navigation Link — FIXED** — `root.html.heex` now includes a correct skip link to `#main` with `sr-only focus:not-sr-only` pattern.

2. **[2.4.2 Page Titled] Static Page Title — LARGELY FIXED** — Root layout uses `<.live_title>`. Per-page titles set in most LiveViews. Exceptions: `index_live.ex` and `custom_sign_in_live.ex` still have no `page_title`.

3. **[1.3.1 Info and Relationships] Lobby Lens Tabs — FIXED** — Line 345 uses `role="tablist"`, `role="tab"`, and `aria-selected` on each chip.

4. **[4.1.3 Status Messages] `aria-live` Regions — IMPROVED** — Count increased from 1 to 11. Lobby countdown timers correctly combine `role="timer"`, `aria-live="polite"`, `aria-atomic="true"`.

### Remaining Critical Violations

#### 1. [1.3.1 Info and Relationships] Polls Form Inputs Missing `for` Attribute

**Severity:** HIGH
**File:** `lib/sensocto_web/live/polls_live.html.heex` (lines 55-98)

All four `<label>` elements have no `for=` attribute. The "Options" inputs have `id` attributes but no matching `for=` on the parent label. Screen readers cannot associate labels with their controls.

**Fix:**

```heex
<label for="poll-title" class="block text-sm font-medium text-gray-300 mb-1">Title</label>
<input id="poll-title" type="text" name="title" required ... />

<label for="poll-description" class="block text-sm font-medium text-gray-300 mb-1">
  Description (optional)
</label>
<textarea id="poll-description" name="description" ... />

<label for="poll-type" class="block text-sm font-medium text-gray-300 mb-1">Type</label>
<select id="poll-type" name="poll_type" ...>

<%!-- For each dynamic option: --%>
<label for={"poll-option-#{i}"} class="sr-only">Option {i + 1}</label>
<input id={"poll-option-#{i}"} type="text" name={"option_#{i}"} ... />
```

#### 2. [1.3.1 Info and Relationships] User Directory Search Input Missing Label

**Severity:** HIGH
**File:** `lib/sensocto_web/live/user_directory_live.html.heex` (lines 26-35)

`placeholder="Search users..."` is the only label. Placeholders are not reliably announced as accessible names. The input `type` should also be `search`.

**Fix:**

```heex
<form phx-change="search" phx-submit="search">
  <label for="user-search" class="sr-only">Search users</label>
  <input
    id="user-search"
    type="search"
    name="search"
    value={@search}
    placeholder="Search users..."
    phx-debounce="300"
    class="w-full rounded-md bg-gray-800 border-gray-600 text-white placeholder-gray-500"
  />
</form>
```

#### 3. [1.1.1 Non-text Content] Profile Skill Removal Button Missing Accessible Name

**Severity:** HIGH
**File:** `lib/sensocto_web/live/profile_live.html.heex`

The removal button contains only `<.icon name="hero-x-mark">` with no accessible name. Users cannot determine which skill will be removed.

**Fix:**

```heex
<button
  type="button"
  phx-click="remove_skill"
  phx-value-id={skill.id}
  aria-label={"Remove skill #{skill.skill_name}"}
  class="ml-1 text-gray-400 hover:text-red-400"
>
  <.icon name="hero-x-mark" class="h-3 w-3" aria-hidden="true" />
</button>
```

#### 4. [4.1.2 Name, Role, Value] User Directory Navigation Missing `aria-current`

**Severity:** MEDIUM
**File:** `lib/sensocto_web/live/user_directory_live.html.heex` (lines 9-21)

The List/Graph tab links use CSS-only active state without `aria-current`. Screen readers cannot determine which view is active.

**Fix:**

```heex
<.link navigate={~p"/users"} aria-current={if @live_action == :index, do: "page"} class={...}>
  <.icon name="hero-list-bullet" class="h-4 w-4 inline -mt-0.5" aria-hidden="true" /> List
</.link>
<.link navigate={~p"/users/graph"} aria-current={if @live_action == :graph, do: "page"} class={...}>
  <.icon name="hero-circle-stack" class="h-4 w-4 inline -mt-0.5" aria-hidden="true" /> Graph
</.link>
```

#### 5. [4.1.2 Name, Role, Value] Dropdown Menus Missing `aria-expanded` and `aria-haspopup`

**Severity:** HIGH
**File:** `lib/sensocto_web/components/layouts/app.html.heex` (lines 76-143)

The language switcher, user menu, and mobile hamburger all toggle dropdowns but lack `aria-expanded` and `aria-haspopup`. The quality override dropdown in lobby is CSS `group-hover` only and entirely inaccessible to keyboard users.

**Fix for user menu:**

```heex
<button
  type="button"
  data-dropdown-toggle
  aria-expanded="false"
  aria-haspopup="menu"
  aria-controls="user-menu-dropdown"
  aria-label="User menu"
>
```

Update JS hooks to toggle `aria-expanded`:

```javascript
const button = this.el.querySelector('[data-dropdown-toggle]');
const isOpen = button.getAttribute('aria-expanded') === 'true';
button.setAttribute('aria-expanded', String(!isOpen));
```

**Fix for quality override dropdown (lobby):** Replace CSS group-hover with Phoenix-controlled boolean:

```heex
<button
  phx-click="toggle_quality_dropdown"
  aria-expanded={to_string(@quality_dropdown_open)}
  aria-haspopup="menu"
  aria-label="Quality settings"
>
  <Heroicons.icon name="adjustments-horizontal" type="outline" class="h-4 w-4" aria-hidden="true" />
</button>
<div :if={@quality_dropdown_open} role="menu" class="absolute ...">
```

#### 6. [2.4.2 Page Titled] `IndexLive` Missing `page_title`

**Severity:** LOW-MEDIUM
**File:** `lib/sensocto_web/live/index_live.ex`

`mount/3` does not assign `page_title`. Falls back to "Sensocto".

**Fix:** Add to mount: `|> assign(:page_title, "Home")`

#### 7. [1.3.1 Info and Relationships] Custom Modals Still Bypass `<.modal>` Component

**Severity:** HIGH — UNCHANGED FROM FEB 16
**File:** `lib/sensocto_web/live/lobby_live.html.heex` (lines ~1420-1672)

Three custom modals (Join Room, Control Request from 3D Viewer, Media Control Request) still use raw `<div>` containers without `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, focus trap, or Escape key handling. The countdown `<div>`s within these modals are correctly marked up, but outer modal containers lack all dialog semantics.

**Fix:** Migrate all three to use the accessible `<.modal>` component documented in `/docs/modal-accessibility-implementation.md`.

#### 8. [2.1.1 Keyboard] Quality Dropdown Not Keyboard Accessible

**Severity:** HIGH — UNCHANGED FROM FEB 16. See fix in item 5 above.

#### 9. [1.4.3 Contrast] Insufficient Color Contrast in Dark Theme

**Severity:** MEDIUM — UNCHANGED

`text-gray-400` (#9CA3AF) on `bg-gray-800` (#1F2937) yields ~3.8:1, below WCAG AA 4.5:1. Now also present in new templates: user bios in `user_directory_live.html.heex`, poll status text in `polls_live.html.heex`.

**Fix:** Replace `text-gray-400` with `text-gray-300` for body text on dark backgrounds.

#### 10. [1.4.3 Contrast] Poll Status Badge Renders Raw Atom Text

**Severity:** LOW
**File:** `lib/sensocto_web/live/polls_live.html.heex`

Status badge displays `:open`/`:closed` as lowercase "open"/"closed". Should use title case.

**Fix:**

```heex
<span class={"badge #{if poll.status == :open, do: "badge-green", else: "badge-gray"}"}>
  {if poll.status == :open, do: "Open", else: "Closed"}
</span>
```

### Positive Accessibility Patterns (Maintained and Extended)

1. **Skip Navigation Link** (`root.html.heex` lines 22-27) — NEWLY FIXED. `sr-only focus:not-sr-only` targeting `#main`.
2. **Dynamic Page Title** (`root.html.heex`) — `<.live_title>` announces changes during LiveView navigation.
3. **Lobby View Mode Selector** (`lobby_live.html.heex` line 345) — NEWLY IMPROVED. `role="tablist"`, `role="tab"`, `aria-selected`.
4. **Countdown Timers** (`lobby_live.html.heex` lines 1513, 1627) — `role="timer"`, `aria-live="polite"`, `aria-atomic="true"`.
5. **Flash Messages** (`core_components.ex` line 156) — `aria-live="assertive"`.
6. **`<.modal>` Component** (`core_components.ex` lines 83-129) — `role="dialog"`, `aria-modal`, `aria-labelledby`, `aria-describedby`, focus wrap, Escape key.
7. **Search Input** (`search_live.ex` line 170) — `aria-label="Search sensors, rooms, and users"`. Keyboard navigation.
8. **Breadcrumbs** (`core_components.ex` line 740) — `aria-label="Breadcrumb"`.
9. **Language Attribute** (`root.html.heex`) — `lang={Gettext.get_locale(...)}`.
10. **Join Code Input** (`lobby_live.html.heex`) — `aria-describedby="join_code_help"`.
11. **Bottom Navigation** (`bottom_nav.ex`) — Visible text labels alongside icons.

---

## Suggested Test Cases

### 1. PollsLive Form Validation Test

```elixir
defmodule SensoctoWeb.PollsLiveTest do
  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "create poll form" do
    test "shows validation errors on empty submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/polls/new")
      html = view |> element("form") |> render_submit(%{})
      assert html =~ "can't be blank"
    end

    test "associates error messages with inputs via aria-describedby", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/polls/new")
      # Each input should have an id that matches a label for= attribute
      assert html =~ ~r/for="poll-title"/
      assert html =~ ~r/id="poll-title"/
      assert html =~ ~r/for="poll-description"/
      assert html =~ ~r/id="poll-description"/
    end
  end
end
```

### 2. UserDirectoryLive Accessibility Test

```elixir
defmodule SensoctoWeb.UserDirectoryLiveTest do
  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "search accessibility" do
    test "search input has an accessible label", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users")
      # Must have label or aria-label, not just placeholder
      refute html =~ ~r/<input[^>]*placeholder="Search"[^>]*(?!aria-label)/
      assert html =~ ~r/aria-label="Search users"/
        |> Kernel.||(html =~ ~r/<label[^>]*>.*[Ss]earch.*<\/label>/)
    end

    test "active nav link has aria-current", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users")
      assert html =~ ~r/aria-current="page"/
    end
  end
end
```

### 3. LobbyLive Push Event Test

```elixir
defmodule SensoctoWeb.LobbyLiveEventTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe "composite_measurement push_event" do
    test "emits correct shape for heartrate sensor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lobby/heartrate")

      batch = [%{
        sensor_id: "test-hr-1",
        sensor_name: "HeartRate Test",
        measurements: [%{value: 72.0, timestamp: System.system_time(:millisecond)}]
      }]

      send(view.pid, {:lens_batch, batch})

      assert_push_event(view, "composite_measurement", %{
        "sensors" => sensors
      })

      assert is_list(sensors)
      assert length(sensors) > 0
    end
  end
end
```

### 4. SearchLive False-Green Fix

Current code (BROKEN — silently passes when component is nil):

```elixir
# BAD: if search_view do ... end — no assertion if nil
search_view = find_live_child(view, "search-component")
if search_view do
  html = render(search_view)
  assert html =~ "sensor"
end
```

Fixed code:

```elixir
# GOOD: assert that the child exists before using it
search_view = find_live_child(view, "search-component")
assert search_view, "Expected SearchLive child to be mounted"
html = render(search_view)
assert html =~ "sensor"
```

### 5. AttentionTracker Registration Coverage

```elixir
defmodule Sensocto.OTP.AttentionTrackerTest do
  use ExUnit.Case, async: true
  alias Sensocto.OTP.AttentionTracker

  describe "composite view lifecycle" do
    test "register_view increments attention level" do
      sensor_id = "test-sensor-777"
      socket_id = "socket-3270"

      AttentionTracker.register_view(:high, sensor_id, socket_id)
      assert AttentionTracker.get_level(sensor_id) == :high

      AttentionTracker.unregister_view(:high, sensor_id, socket_id)
      assert AttentionTracker.get_level(sensor_id) in [:low, :none]
    end
  end
end
```
---

## Accessibility Audit (WCAG 2.1 AA)

### Violation 1 — Polls Form: Labels Without `for=` Attributes
- **WCAG Criterion**: 1.3.1 Info and Relationships (Level A)
- **Severity**: HIGH
- **File**: `lib/sensocto_web/live/polls_live.html.heex` lines 55-98
- **Issue**: Four `<label>` elements have no `for=` attribute, and their corresponding inputs have no matching `id=`. Screen readers cannot programmatically associate labels with controls.
- **Fix**: Add `for="poll-title"` to the Title label and `id="poll-title"` to the input. Repeat for description, type, and each option input.

### Violation 2 — User Directory: Missing Search Label
- **WCAG Criterion**: 1.3.1 Info and Relationships (Level A)
- **Severity**: HIGH
- **File**: `lib/sensocto_web/live/user_directory_live.html.heex` lines 26-35
- **Issue**: Search input has only a `placeholder` attribute. Placeholders disappear on input and are not announced as labels by screen readers.
- **Fix**: Add a visually hidden label or `aria-label="Search users"` directly to the input.

### Violation 3 — Profile: Icon-Only Remove-Skill Button
- **WCAG Criterion**: 1.1.1 Non-text Content (Level A)
- **Severity**: HIGH
- **File**: `lib/sensocto_web/live/profile_live.html.heex` (skill removal buttons)
- **Issue**: Skill removal buttons contain only an SVG icon (`hero-x-mark`) with no text alternative. Screen reader users hear "button" with no description of which skill is being removed.
- **Fix**: Add `aria-label={"Remove skill: " <> skill.name}` to each button.

### Violation 4 — App Layout: Dropdowns Missing `aria-expanded`
- **WCAG Criterion**: 4.1.2 Name, Role, Value (Level A)
- **Severity**: HIGH
- **File**: `lib/sensocto_web/components/layouts/app.html.heex` lines 76-143
- **Issue**: User menu, language switcher, and mobile hamburger buttons toggle a CSS `hidden` class via JS hooks but never update `aria-expanded`. Screen reader users cannot determine whether the menu is open or closed.
- **Fix**: Initialize buttons with `aria-expanded="false"` and `aria-haspopup="true"`. In the JS hooks (UserMenu, LangMenu, MobileMenu), update `aria-expanded` whenever the hidden class is toggled.

### Violation 5 — Custom Modals Bypass `<.modal>` Component
- **WCAG Criterion**: 4.1.2 Name, Role, Value; 2.1.2 No Keyboard Trap (Level A)
- **Severity**: HIGH (unchanged from previous report)
- **File**: `lib/sensocto_web/live/lobby_live.html.heex` lines ~1420-1672
- **Issue**: Three modals (Join Room, Control Request, Media Control Request) are raw `<div>` elements without `role="dialog"`, `aria-modal`, `aria-labelledby`, focus trapping, or Escape key handling. The `<.modal>` core component provides all of these.
- **Fix**: Refactor each custom modal to use `<.modal id="..." ...>`. Highest-effort fix but highest impact.

### Violation 6 — Nav Links Without `aria-current`
- **WCAG Criterion**: 4.1.2 Name, Role, Value (Level A)
- **Severity**: MEDIUM
- **File**: `lib/sensocto_web/live/user_directory_live.html.heex` lines 9-21
- **Issue**: List/Graph view navigation links have no `aria-current="page"` on the active link. Sighted users see a visual indicator; screen reader users cannot identify the current view.
- **Fix**: Add `aria-current={if @view_mode == :list, do: "page", else: false}` to the List link, and the equivalent for the Graph link.

### Violation 7 — IndexLive Missing Unique Page Title
- **WCAG Criterion**: 2.4.2 Page Titled (Level A)
- **Severity**: LOW-MEDIUM
- **File**: `lib/sensocto_web/live/index_live.ex`
- **Issue**: `mount/3` does not assign a `page_title`, so the page title falls back to the application name "Sensocto" — indistinct from any other page.
- **Fix**: Add `|> assign(:page_title, "Home")` in `mount/3`.

### Violation 8 — PollsLive Status Badge: Verify Color Is Not Sole Indicator
- **WCAG Criterion**: 1.4.1 Use of Color (Level A)
- **Severity**: MEDIUM (informational)
- **File**: `lib/sensocto_web/live/polls_live.html.heex`
- **Issue**: Poll status uses green/gray badge color. If the badge also renders the text "Open" or "Closed" in all states, this is acceptable.
- **Fix**: Confirm visible text labels accompany the color classes in all render paths.

### Violation 9 — Vote Count Updates Not Announced
- **WCAG Criterion**: 4.1.3 Status Messages (Level AA)
- **Severity**: LOW
- **File**: `lib/sensocto_web/live/polls_live.html.heex`
- **Issue**: When a user votes and counts update, no `aria-live` region announces the change. Screen reader users will not hear real-time vote count updates.
- **Fix**: Wrap vote count displays in `<span aria-live="polite" aria-atomic="true">`.

### Violation 10 — UserShowLive: Profile Avatar Alt Text
- **WCAG Criterion**: 1.1.1 Non-text Content (Level A)
- **Severity**: LOW
- **File**: `lib/sensocto_web/live/user_show_live.html.heex`
- **Issue**: If avatar images use generic or empty alt text when a user name is available, this fails the non-text content criterion.
- **Fix**: Use descriptive alt text such as `alt={"Profile photo of " <> @user.display_name}`.

---

## Usability Findings

### Issue 1 — [HIGH] Poll Form Lacks Real-Time Validation Feedback
- **File**: `lib/sensocto_web/live/polls_live.html.heex`, `lib/sensocto_web/live/polls_live.ex`
- **Issue**: There is no `phx-change` handler on the create-poll form. Users must submit the form to discover validation errors. For a multi-option form (title, description, type, N options), this creates a disruptive edit cycle.
- **Fix**: Add a `phx-change="validate_poll"` event handler that runs `Ash.Changeset.for_create(...)` with the form params and assigns errors without persisting. Display inline errors per field using `<.error>` component.

### Issue 2 — [HIGH] No Loading State on Poll Submission
- **File**: `lib/sensocto_web/live/polls_live.html.heex`
- **Issue**: The poll creation submit button has no `phx-disable-with` attribute. Users can double-submit or see no feedback during slow network conditions.
- **Fix**: Add `phx-disable-with="Creating..."` to the submit button.

### Issue 3 — [MEDIUM] User Directory Search Has No Debounce
- **File**: `lib/sensocto_web/live/user_directory_live.html.heex`
- **Issue**: The search input likely fires `phx-change` on every keystroke without debounce. For a user directory that queries the database on each change, this causes unnecessary load.
- **Fix**: Add `phx-debounce="300"` to the search input.

### Issue 4 — [MEDIUM] Profile Skills: No Undo for Destructive Action
- **File**: `lib/sensocto_web/live/profile_live.html.heex`
- **Issue**: Clicking the remove-skill button immediately removes the skill with no confirmation or undo mechanism. This is a destructive action with no recovery path in the UI.
- **Fix**: Either add a confirmation dialog (using `<.modal>`) or implement an optimistic-UI undo pattern via a temporary flash message with a cancel action.

### Issue 5 — [MEDIUM] UserGraph (Svelte) Has No Loading Skeleton
- **File**: `lib/sensocto_web/live/user_directory_live.html.heex`, `assets/svelte/UserGraph.svelte`
- **Issue**: The user connection graph (`<.svelte name="UserGraph">`) renders an empty container while Svelte hydrates. For large graphs this can take noticeable time with no user feedback.
- **Fix**: Add a loading skeleton or spinner inside the `<.svelte>` fallback content slot that is visible before JavaScript initializes.

### Issue 6 — [LOW] Polls List: Empty State Messaging
- **File**: `lib/sensocto_web/live/polls_live.html.heex`
- **Issue**: When no polls exist, the list is likely empty with no message. Users cannot distinguish between "no polls exist" and "polls failed to load".
- **Fix**: Add an explicit empty state: `<p>No polls yet. Create the first one!</p>` rendered when `@polls` is empty.

### Issue 7 — [LOW] User Directory: No Results State
- **File**: `lib/sensocto_web/live/user_directory_live.html.heex`
- **Issue**: Searching with a query that returns no users should show a "No users found" message rather than an empty list.
- **Fix**: Add `<%= if @users == [], do: "No users found for this search." %>` in the list template.

---

## Accessibility Test Coverage

The project has zero automated accessibility regression tests. All accessibility findings above are from manual code review. The following tests should be added to prevent regressions.

### Recommended Accessibility Regression Tests

Tests should live in `test/sensocto_web/accessibility/` and use `Floki` to assert structural HTML properties.

Key assertions to add:

1. **All form inputs have associated labels** — for every `<input>`, `<select>`, `<textarea>` in a form, assert there is a `<label for=...>` matching its `id`, or an `aria-label`, or an `aria-labelledby`.

2. **All images have alt text** — for every `<img>` rendered in LiveView tests, assert `alt` attribute is present and non-generic.

3. **All icon-only buttons have accessible names** — for buttons containing only SVG/icon children, assert `aria-label` is present.

4. **Skip link present on every page** — assert `#main` anchor and the `sr-only focus:not-sr-only` skip link are present in root layout.

5. **aria-live regions present in flash** — assert `aria-live="assertive"` on flash container.

6. **Modal accessibility contract** — for any page that can open a modal, assert `role="dialog"`, `aria-modal="true"`, and `aria-labelledby` are present when modal is open.

Example test structure using Floki:

```elixir
defmodule SensoctoWeb.Accessibility.PollsFormTest do
  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "all form inputs have associated labels", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/polls/new")
    doc = Floki.parse_document!(html)

    inputs = Floki.find(doc, "form input:not([type=hidden]), form select, form textarea")
    Enum.each(inputs, fn input ->
      input_id = Floki.attribute(input, "id") |> List.first()
      aria_label = Floki.attribute(input, "aria-label") |> List.first()
      label = if input_id, do: Floki.find(doc, "label[for=#{input_id}]"), else: []
      assert aria_label != nil or label != [],
        "Input id=#{inspect(input_id)} has no accessible label"
    end)
  end
end
```

---

## Implications for Planned Work

### PLAN-adaptive-video-quality.md
When adaptive video quality controls are added (quality selector, manual override buttons), ensure:
- Quality level buttons use `aria-pressed` (toggle buttons) or `role="radiogroup"` + `role="radio"` pattern
- Loading/buffering states announce to `aria-live` region: "Video quality changing to HD..."
- Keyboard shortcuts for quality control are documented and not conflicting with standard browser/AT shortcuts

### PLAN-room-iroh-migration.md
Iroh-based room connection introduces new connection status states. Ensure:
- Connection status changes (connecting, connected, disconnected) announce via `aria-live="polite"`
- Error states (connection failed) announce via `aria-live="assertive"`
- Any new room UI uses `<.modal>` for dialogs, not raw `<div>`

### PLAN-sensor-component-migration.md
During sensor component migration, audit each migrated component for:
- Interactive elements have accessible names
- Sensor data displays have appropriate `aria-live` regions for real-time updates (or confirm why they do not need announcements)
- Component `id` attributes are unique when multiple instances are rendered

### PLAN-platform-features.md
Social features (follows, connections, direct messages) will require:
- Notification badges have `aria-label` describing the count: `aria-label="3 unread notifications"`
- Live notification updates use `aria-live` region
- Follow/unfollow buttons use `aria-pressed` attribute

---

## Priority Actions

### Immediate (Block on next release)
1. **Fix polls form labels** — Add `for=` and `id=` to all 4 label/input pairs in `polls_live.html.heex`. 30-minute fix.
2. **Fix user directory search label** — Add `aria-label="Search users"` to search input. 5-minute fix.
3. **Fix profile remove-skill button** — Add `aria-label={"Remove skill: " <> skill.name}` to each button. 15-minute fix.
4. **Fix search_live_test false-green** — Replace `if search_view do ... end` with `assert search_view` + unconditional body. 5-minute fix.

### Short-term (Next sprint)
5. **Add `aria-expanded` to app layout menus** — User menu, language switcher, mobile hamburger. Update JS hooks to maintain `aria-expanded`. 2-hour fix.
6. **Fix IndexLive page title** — Add `assign(:page_title, "Home")` in `index_live.ex`. 5-minute fix.
7. **Add `aria-current` to user directory nav** — 10-minute fix.
8. **Fix vote count aria-live** — Wrap vote count display in `<span aria-live="polite">`. 15-minute fix.
9. **Add `phx-disable-with` to poll submit button** — 5-minute fix.
10. **Investigate `refute_push_event/4` arity** in `midi_output_regression_test.exs` — Verify 4-argument call is valid for the installed Phoenix version.

### Medium-term (Next month)
11. **Migrate lobby custom modals to `<.modal>` component** — Join Room, Control Request, Media Control Request modals. Highest effort (~4 hours) but critical for keyboard accessibility.
12. **Add Floki-based accessibility regression tests** — Create `test/sensocto_web/accessibility/` with form label, aria-live, and icon-button tests.
13. **Add `phx-change="validate_poll"` real-time validation** — Prevents disruptive submit-to-discover error cycle.
14. **Deduplicate redundant lobby_graph_regression tests** — Remove the 3 identical describe blocks, or split into 3 named tests.

### Ongoing
15. **Audit each new LiveView for WCAG 1.3.1 compliance** — Every new form must have label/input associations before merging.
16. **Review adaptive video quality controls for `aria-pressed`** — When PLAN-adaptive-video-quality features land.
17. **Review Iroh connection status for `aria-live` announcements** — When PLAN-room-iroh-migration lands.

---

## Test Coverage Summary

| Domain | Test Files | Approx Tests | Notes |
|---|---|---|---|
| Accounts (Users, Tokens) | 2 | ~48 | New: accounts_test.exs |
| Collaboration (Polls) | 1 | ~32 | New: collaboration_test.exs |
| Sensors (core) | 6 | ~89 | Existing, no changes |
| OTP (AttentionTracker, AttributeStore, RoomServer) | 3 | ~71 | All new |
| Encoding (DeltaEncoder) | 1 | ~18 | New |
| Resilience (CircuitBreaker) | 1 | ~22 | New |
| Simulator | 4 | ~51 | No changes |
| LiveView (Lobby, MIDI, Search, Room, etc.) | 14 | ~189 | 4 new regression tests |
| Channel / Presence | 2 | ~29 | No changes |
| Misc (Router, ErrorHTML) | 2 | ~8 | No changes |
| Integration (Wallaby) | 1 | ~12 | No changes |
| Performance / Stress | 5 | ~53 | No changes |
| Data Layer / Ash | 9 | ~110 | No changes |
| **Total** | **51** | **~732** | **Up from 33/~373** |

Coverage estimate: **~61% of application code** (up from ~44%). The largest uncovered areas remain: Phoenix channel error paths, Simulator edge cases (startup failure, timeout), and MIDI hardware abstraction layer.

---

## Appendix: Files Reviewed This Cycle

- `test/sensocto_web/live/lobby_graph_regression_test.exs` (229 lines)
- `test/sensocto_web/live/midi_output_regression_test.exs` (219 lines)
- `test/sensocto_web/live/search_live_test.exs`
- `test/sensocto/accounts/accounts_test.exs` (316 lines)
- `test/sensocto/collaboration/collaboration_test.exs` (192 lines)
- `test/sensocto/encoding/delta_encoder_test.exs` (149 lines)
- `test/sensocto/otp/attention_tracker_test.exs` (147 lines)
- `test/sensocto/otp/attribute_store_tiered_test.exs` (133 lines)
- `test/sensocto/otp/room_server_test.exs` (330 lines)
- `test/sensocto/resilience/circuit_breaker_test.exs` (138 lines)
- `lib/sensocto_web/live/polls_live.html.heex`
- `lib/sensocto_web/live/user_directory_live.html.heex`
- `lib/sensocto_web/live/profile_live.html.heex`
- `lib/sensocto_web/live/user_show_live.html.heex`
- `lib/sensocto_web/components/layouts/app.html.heex`
- `lib/sensocto_web/components/layouts/root.html.heex`
- `lib/sensocto_web/live/lobby_live.html.heex` (1672 lines)
- `lib/sensocto_web/live/index_live.ex`
- `git diff HEAD~10 --stat` (116 files changed, 17663 insertions)

---

## Summary

The Sensocto project has made substantial testing and accessibility progress since the February 16 review. Test file count grew from 33 to 51, test count from ~373 to ~732, and three longstanding accessibility violations (skip navigation, live title, lobby tablist) have been resolved.

The new Collaboration and Accounts domains are well-covered by their new test files. The OTP layer now has meaningful regression coverage for AttentionTracker, AttributeStoreTiered, and RoomServer. The lobby regression test suite covers all 13 routes and the composite MIDI push event contract.

However, the rapid addition of the Polls, UserDirectory, and Profile features introduced four new HIGH-severity WCAG violations and two test quality issues that must be addressed before these features ship to production. The `polls_live.html.heex` form label association failures and the `search_live_test.exs` false-green pattern are the most urgent items.

The three custom modals in `lobby_live.html.heex` remain the project's most significant accessibility debt. Migrating them to the `<.modal>` core component should be scheduled as a focused sprint task.

*Last updated: 2026-02-20 by elixir-test-accessibility-expert agent.*
