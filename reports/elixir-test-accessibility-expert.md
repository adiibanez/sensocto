# Comprehensive Test Coverage and Accessibility Analysis
## Sensocto IoT Sensor Platform

**Analysis Date:** January 12, 2026 (Updated: February 16, 2026)
**Analyzed By:** Testing, Usability, and Accessibility Expert Agent
**Project:** Sensocto - Elixir/Phoenix IoT Sensor Platform

---

## Update: February 16, 2026

### Executive Summary

This update reflects the Sensocto codebase as of February 16, 2026. The project has **250 implementation files** in `/lib` and **33 test files** with **373 passing tests** (2 pre-existing failures, 3 skipped, 109 excluded). Since the last update (Feb 15), significant testing improvements have been made: a comprehensive **regression guards test suite** (49 tests, 766 lines) has been added to protect data pipeline contracts during refactoring. This is a major step forward in maintaining system stability. However, accessibility gaps remain largely unchanged, with only 1 `aria-live` region in the entire codebase and zero `aria-label` attributes in the lobby view.

### Current Metrics

| Metric | Feb 8 | Feb 15 | Feb 16 | Change |
|--------|-------|--------|--------|--------|
| Implementation Files | 249 | 249 | **250** | +1 |
| Test Files | 32 | 32 | **33** | +1 |
| Test Count (passing) | ~400 | 291 | **373** | +82 |
| Regression Guard Tests | 0 | 0 | **49** | +49 NEW |
| LiveView Test Files | 4 | 4 | **4** | Stable |
| LiveView Modules | 46 | 46 | **46** | Stable |
| Component Files | 13 | 13 | **14** | +1 |
| WCAG Level A Violations | 40+ | 40+ | **40+** | Stable |
| WCAG Level AA Violations | 12+ | 12+ | **12+** | Stable |
| Accessibility Tests | 24 | 24 | **24** | Stable |
| `aria-live` Regions | 1 | 1 | **1** | Critical gap |
| `aria-label` in Lobby | 0 | 0 | **0** | Critical gap |
| Estimated Code Coverage | ~13% | ~13% | **~15%** | +2% |

### Key Changes Since Last Review (Feb 15 → Feb 16)

**Positive Changes:**
1. **Regression Guards Test Suite Added** (766 lines, 49 tests) — Protects against silent breakage during refactoring. Tests data pipeline contracts: SimpleSensor → PubSub → Router → PriorityLens, attention topic format, batch measurement format, attention level propagation, digest format, socket ID handling, and time-series constraints.
2. **About Content Component Enhanced** — Videos/images added to about tab (109 lines added to `about_content_component.ex`).
3. **Sensor Data Helper Module Created** — `/lib/sensocto_web/live/helpers/sensor_data.ex` (1907 bytes) added for sensor data extraction logic.
4. **Test Count Increased** — From 291 to 373 passing tests (+82 tests), primarily from regression guards.
5. **4 E2E Feature Test Files** — Media player, whiteboard, 3D object viewer, collab demo (Wallaby-based).

**Remaining Critical Gaps:**
1. **No tests for LobbyLive** (most complex module, ~1200 lines of template) — UNCHANGED
2. **No tests for IndexLive** (main dashboard) — UNCHANGED
3. **No tests for CallServer, QualityManager, SnapshotManager** — UNCHANGED
4. **Zero `aria-live` regions** (except 1 in flash component) — UNCHANGED
5. **Zero `aria-label` attributes in lobby** icon-only buttons — UNCHANGED
6. **Custom modals in lobby_live.html.heex bypass accessible `<.modal>` component** — UNCHANGED
7. **No skip navigation link** — UNCHANGED

---

## Testing Analysis

### Test File Inventory (33 files)

| Category | Files | Tests | Notes |
|----------|-------|-------|-------|
| Regression Guards | regression_guards_test.exs | **49** | **NEW** — Contract-based tests for data pipeline |
| OTP/Supervision | supervision_tree_test.exs | 31 | Comprehensive |
| Lenses | priority_lens_test.exs | 20 | Good coverage |
| E2E/Integration | media_player_feature_test.exs | 20 | Wallaby-based |
| E2E/Integration | collab_demo_feature_test.exs | 13 | Lobby, tabs, multi-user |
| E2E/Integration | whiteboard_feature_test.exs | ~10 | Touch & mouse events |
| E2E/Integration | object3d_player_feature_test.exs | ~10 | 3D viewer (limited by WebGL) |
| Plugs | rate_limiter_test.exs | 13 | Thorough |
| Components | modal_accessibility_test.exs | 14 | Accessibility-focused |
| Components | core_components_test.exs | 10 | Modal ARIA tests |
| Bio Layer | homeostatic_tuner_test.exs | ~15 | GenServer tests |
| LiveView | stateful_sensor_live_test.exs | 2 | Minimal |
| API | openapi_test.exs | 2 | Schema validation |
| Other | ~20 files | ~164 | Various modules |

### Major Testing Improvement: Regression Guards

**File:** `test/sensocto/regression_guards_test.exs` (49 tests, 766 lines)

This is a **critical addition** that protects the core data pipeline from silent breakage during refactoring. The test suite is organized into contract-based tests covering:

1. **Data Pipeline Contract** (7 tests)
   - Router demand-driven subscription model
   - Measurement message shape: `{:measurement, %{sensor_id:, attribute_id:, value:, timestamp:}}`
   - Batch message shape: `{:measurements_batch, {sensor_id, [measurements]}}`
   - Attention topic format: `"data:attention:high|medium|low"`

2. **AttentionTracker Contract** (8 tests)
   - `register_view/3`, `unregister_view/3`, `get_level/1` API
   - Attention level values: `:high`, `:medium`, `:low`, `:none`
   - ETS preservation across crashes
   - Recovery mode behavior
   - PubSub broadcast topics for re-registration

3. **PriorityLens Contract** (6 tests)
   - ETS direct-write optimization (GenServer-free hot path)
   - Buffering, flush timers, digest generation
   - Socket ID to sensor mappings
   - Quality tier changes

4. **Time-Series Constraints** (5 tests)
   - Timestamp ordering, monotonicity, freshness (< 5s staleness threshold)
   - Historical data seed ordering (most recent N entries)

5. **Composite Lens Contract** (4 tests)
   - Multi-sensor data extraction (heartrate, ECG, breathing, etc.)
   - Tuple shape consistency
   - Seed data event format

**Why This Matters:**
- Protects against refactoring that breaks message contracts
- Documents expected data shapes and API contracts
- Prevents silent failures in the data pipeline
- Complements unit tests with integration-level contract verification

### Critical Testing Gaps (UNCHANGED)

#### Priority 0: No Tests At All

These modules have zero test coverage and handle critical user-facing or data-integrity functionality:

1. **`lib/sensocto_web/live/lobby_live.ex`** (UNCHANGED) — The most complex LiveView module. Handles virtual scrolling, composite lens views (heartrate, ECG, breathing, HRV, IMU, location, battery, skeleton, graph), PubSub subscriptions, attention tracking, sensor state management, modal dialogs (Join Room, Control Request, Media Control). **No tests.**

2. **`lib/sensocto_web/live/index_live.ex`** (UNCHANGED) — Main dashboard page. Sensor preview, room listing, public room listing. **No tests.**

3. **`lib/sensocto/calls/call_server.ex`** (776 lines, UNCHANGED) — Video call server with participant management, speaking detection, attention-based quality tier assignment. **No tests.**

4. **`lib/sensocto/calls/quality_manager.ex`** (336 lines, UNCHANGED) — Adaptive video quality tier calculation. **No tests.**

5. **`lib/sensocto/calls/snapshot_manager.ex`** (239 lines, UNCHANGED) — ETS-based snapshot storage for idle call participants. **No tests.**

6. **`lib/sensocto/calls/cloudflare_turn.ex`** (UNCHANGED) — TURN credential generation with caching. **No tests.**

7. **`lib/sensocto_web/channels/call_channel.ex`** (359 lines, UNCHANGED) — Channel handlers for speaking state, attention state, video snapshots. **No tests.**

8. **`lib/sensocto_web/live/admin/system_status_live.ex`** (UNCHANGED) — Admin system dashboard. **No tests.**

9. **`lib/sensocto_web/live/custom_sign_in_live.ex`** (UNCHANGED) — Authentication page. **No tests.**

10. **`lib/sensocto_web/live/components/about_content_component.ex`** (UNCHANGED, now 81KB) — About page with videos. **No tests.**

#### Priority 1: Insufficient Tests (UNCHANGED)

1. **`stateful_sensor_live_test.exs`** — Only 2 tests (render and view_enter event). Missing: measurement display, modal interactions, favorite toggle, pin/unpin, view mode changes, latency ping/pong, battery state, highlight toggle, attribute loading.

2. **`openapi_test.exs`** — Only 2 tests for schema validation. Missing: endpoint-level tests for each API route.

### Suggested Test Cases

The previous recommendations remain valid. Key priorities:

#### 1. LobbyLive Mount and Navigation Tests (HIGHEST PRIORITY)

```elixir
defmodule SensoctoWeb.LobbyLiveTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders lobby page with sensor list", %{conn: conn} do
      {:ok, view, html} = live(conn, "/lobby")
      assert html =~ "Lobby"
      assert has_element?(view, "[data-role='sensor-list']")
    end

    test "redirects unauthenticated users", %{conn: conn} do
      conn = conn |> clear_session()
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, "/lobby")
    end
  end

  describe "lens navigation" do
    test "navigates to heartrate lens", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      assert {:ok, _view, html} = live(view, "/lobby/heartrate")
      assert html =~ "heartrate" or html =~ "Heartrate"
    end

    test "navigates to ECG lens", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      assert {:ok, _view, html} = live(view, "/lobby/ecg")
      assert html =~ "ecg" or html =~ "ECG"
    end
  end

  describe "join room modal" do
    test "opens join room modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      html = render_click(view, "show_join_modal")
      assert html =~ "Join Room"
    end

    test "validates empty join code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      render_click(view, "show_join_modal")
      html = render_submit(view, "join_room", %{"join_code" => ""})
      assert html =~ "error" or html =~ "required"
    end
  end

  describe "composite lens data extraction" do
    test "extract_composite_data returns 7-element tuple", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/heartrate")
      # This test verifies the contract tested in regression_guards_test.exs
      # Ensure tuple shape matches expectations
    end
  end
end
```

#### 2. CallServer Unit Tests (HIGH PRIORITY)

```elixir
defmodule Sensocto.Calls.CallServerTest do
  use ExUnit.Case, async: true
  alias Sensocto.Calls.CallServer

  describe "quality tier calculation" do
    test "active speaker gets full video tier" do
      state = %{
        participants: %{"user1" => %{speaking: true, attention_level: :high}},
        active_speaker: "user1"
      }
      assert CallServer.calculate_tier(state, "user1") == :active
    end

    test "recently active participant gets reduced tier" do
      state = %{
        participants: %{"user1" => %{speaking: false, attention_level: :high}},
        active_speaker: "user2"
      }
      assert CallServer.calculate_tier(state, "user1") == :recent
    end

    test "idle participant gets static tier" do
      state = %{
        participants: %{"user1" => %{speaking: false, attention_level: :low}},
        active_speaker: "user2"
      }
      assert CallServer.calculate_tier(state, "user1") in [:viewer, :idle]
    end
  end

  describe "participant management" do
    test "adding participant updates state" do
      {:ok, pid} = CallServer.start_link(room_id: "test_room")
      :ok = CallServer.join(pid, "user1", %{name: "Test User"})
      state = CallServer.get_state(pid)
      assert "user1" in Map.keys(state.participants)
    end

    test "removing participant cleans up state" do
      {:ok, pid} = CallServer.start_link(room_id: "test_room")
      CallServer.join(pid, "user1", %{name: "Test User"})
      CallServer.leave(pid, "user1")
      state = CallServer.get_state(pid)
      refute "user1" in Map.keys(state.participants)
    end
  end
end
```

#### 3. CloudflareTurn Tests (MEDIUM PRIORITY)

```elixir
defmodule Sensocto.Calls.CloudflareTurnTest do
  use ExUnit.Case, async: true
  alias Sensocto.Calls.CloudflareTurn

  describe "get_ice_servers/0" do
    test "returns nil when not configured" do
      assert CloudflareTurn.get_ice_servers() == nil
    end

    test "returns cached credentials when fresh" do
      # After successful credential generation
      # Verify persistent_term cache is used
    end

    test "refreshes credentials when within 1h of expiry" do
      # Test the refresh threshold logic
    end
  end
end
```

---

## Accessibility Audit

### WCAG 2.1 Compliance Summary (UNCHANGED)

| Level | Status | Violations | Notes |
|-------|--------|------------|-------|
| Level A | FAIL | 40+ violations | Critical gaps in dynamic content, labels, keyboard access |
| Level AA | FAIL | 12+ violations | Color contrast, status messages, focus management |
| Level AAA | NOT ASSESSED | -- | Not targeted |

### Critical Accessibility Findings

#### Current State of ARIA Attributes

**Grep Results:**
- `aria-live` regions: **1** (only in flash component with `aria-live="assertive"`)
- `aria-label` in lobby: **0** (zero icon-only buttons have accessible labels)
- `role="dialog"`: **2** (only in core_components.ex modal, NOT in custom lobby modals)

### Level A Violations (UNCHANGED — Must Fix)

#### 1. [1.1.1 Non-text Content] Icon-Only Buttons Missing Accessible Names

**Severity:** HIGH
**Files affected:**
- `lib/sensocto_web/live/lobby_live.html.heex` (lines 29-45, 73-78, 161-178, 182-192)
- `lib/sensocto_web/live/stateful_sensor_live.html.heex` (detail, resize, pin, favorite buttons)
- `lib/sensocto_web/live/components/stateful_sensor_component.html.heex`

**Issue:** Many buttons contain only SVG icons with `title` attributes but no `aria-label`. The `title` attribute provides a tooltip but is not consistently announced by screen readers as the button's accessible name.

**Fix:** Add `aria-label` to every icon-only button:
```heex
<%!-- Before --%>
<button title="Detail view" phx-click="toggle_view_mode">
  <svg>...</svg>
</button>

<%!-- After --%>
<button title="Detail view" aria-label="Detail view" phx-click="toggle_view_mode">
  <svg aria-hidden="true">...</svg>
</button>
```

#### 2. [1.3.1 Info and Relationships] Form Inputs Without Labels

**Severity:** HIGH
**Files affected:**
- `lib/sensocto_web/live/lobby_live.html.heex` (lines 537-555, Min Attention slider)
- Various select elements and dropdowns throughout the UI

**Issue:** The Min Attention slider and several select elements lack proper `<label>` associations. Screen readers cannot identify the purpose of these controls.

**Fix:**
```heex
<%!-- Before --%>
<input type="range" min="0" max="100" value={@min_attention} phx-change="set_min_attention" />

<%!-- After --%>
<label for="min-attention" class="sr-only">Minimum attention threshold</label>
<input id="min-attention" type="range" min="0" max="100" value={@min_attention}
  phx-change="set_min_attention" aria-valuemin="0" aria-valuemax="100"
  aria-valuenow={@min_attention} aria-valuetext={"#{@min_attention}%"} />
```

#### 3. [1.3.1 Info and Relationships] Custom Modals Bypass Accessible Component

**Severity:** HIGH
**File:** `lib/sensocto_web/live/lobby_live.html.heex` (lines 924-1229)

**Issue:** Three custom modal implementations (Join Room, Control Request, Media Control Request) are built with raw `<div>` elements and do NOT use the accessible `<.modal>` component from `core_components.ex`. They lack `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, focus trap, and Escape key handling.

**Fix:** Migrate all three modals to use the `<.modal>` component, which properly implements all required ARIA attributes and behaviors documented in `/docs/modal-accessibility-implementation.md`.

#### 4. [2.1.1 Keyboard] Quality Dropdown Not Keyboard Accessible

**Severity:** HIGH
**File:** `lib/sensocto_web/live/lobby_live.html.heex` (lines 72-133)

**Issue:** The quality settings dropdown relies on CSS `group-hover` for visibility. There is no keyboard trigger (no `focus-within`, no button toggle). Keyboard-only users cannot access quality settings.

**Fix:** Implement a toggle button pattern:
```heex
<button aria-expanded={@quality_dropdown_open} aria-haspopup="menu"
  phx-click="toggle_quality_dropdown">
  Quality Settings
</button>
<div role="menu" :if={@quality_dropdown_open}>
  <%!-- dropdown content --%>
</div>
```

#### 5. [2.1.1 Keyboard] No Skip Navigation Link

**Severity:** HIGH
**Files affected:**
- `lib/sensocto_web/components/layouts/root.html.heex`
- `lib/sensocto_web/components/layouts/app.html.heex`

**Issue:** There is no skip navigation link. The main content area has `<main id="main">` but no skip link targets it. Keyboard users must tab through the entire navigation on every page.

**Fix:** Add to `root.html.heex`:
```heex
<body>
  <a href="#main" class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2
    focus:z-50 focus:bg-white focus:text-black focus:px-4 focus:py-2 focus:rounded">
    Skip to main content
  </a>
  ...
</body>
```

#### 6. [2.4.2 Page Titled] Static Page Title

**Severity:** MEDIUM
**File:** `lib/sensocto_web/components/layouts/root.html.heex`

**Issue:** The `<title>` is hardcoded as "Sensocto | LiveView" and never updates with navigation. Users relying on page titles for orientation cannot distinguish between pages.

**Fix:** Use Phoenix's `assign(:page_title, ...)` pattern:
```heex
<title><%= assigns[:page_title] || "Sensocto" %></title>
```
Then in each LiveView mount:
```elixir
socket = assign(socket, :page_title, "Lobby - Sensocto")
```

#### 7. [4.1.2 Name, Role, Value] Sensor Tile Modals Missing Dialog Role

**Severity:** HIGH
**File:** `lib/sensocto_web/live/stateful_sensor_live.html.heex` (lines 127-168, 170-297)

**Issue:** Map Modal and Detail Modal in sensor tiles lack `role="dialog"`, `aria-modal="true"`, and focus trap. When opened, focus is not moved into the modal, and pressing Escape does not close it.

#### 8. [4.1.3 Status Messages] Zero aria-live Regions

**Severity:** HIGH — **CRITICAL GAP**
**All LiveView templates**

**Issue:** Only **1 `aria-live` region** exists in the entire codebase (flash component with `aria-live="assertive"`). In a real-time application that constantly updates sensor readings, call status, and connection state, this means screen reader users receive **no notification** of any dynamic content changes beyond flash messages.

**Critical areas needing aria-live:**
- **Sensor measurement updates** (sparklines, values in lobby tiles)
- **Connection status changes** (online/offline)
- **Call state changes** (joining, connected, disconnected)
- **Virtual scroll loading states** ("Loading more sensors...")
- **Room join success/failure feedback**
- **Attention level changes** (high/medium/low)
- **Composite lens data updates** (heartrate, ECG, breathing waveforms)

**Fix for lobby sensor count:**
```heex
<div aria-live="polite" aria-atomic="true" class="sr-only">
  <%= @sensor_count %> sensors connected
</div>
```

**Fix for connection status:**
```heex
<div aria-live="assertive" aria-atomic="true">
  <span class="sr-only">Connection status:</span>
  <%= @connection_status %>
</div>
```

**Positive:** Flash component already has `aria-live="assertive"` (line 156 in core_components.ex).

### Level AA Violations (UNCHANGED)

#### 9. [1.4.3 Contrast (Minimum)] Insufficient Color Contrast in Dark Theme

**Severity:** MEDIUM
**Files affected:** Multiple templates using `text-gray-400` on `bg-gray-800` or `bg-gray-900`

**Issue:** `text-gray-400` (#9CA3AF) on `bg-gray-800` (#1F2937) yields approximately 3.8:1 contrast ratio. WCAG AA requires 4.5:1 for normal text.

**Fix:** Use `text-gray-300` (#D1D5DB) instead of `text-gray-400` for body text on dark backgrounds. This achieves approximately 7:1 contrast ratio.

#### 10. [1.4.11 Non-text Contrast] Status Colors Without Text Alternatives

**Severity:** MEDIUM
**File:** `lib/sensocto_web/live/admin/system_status_live.html.heex`

**Issue:** System status uses color-coded indicators (green/yellow/red) to convey status. While text labels partially mitigate this, the colors alone may not meet the 3:1 non-text contrast requirement in all cases.

#### 11. [2.4.7 Focus Visible] CSS Focus Indicators

**Severity:** MEDIUM
**Multiple files**

**Issue:** Tailwind's default `outline-none` or `ring-0` classes suppress visible focus indicators on interactive elements. Keyboard users cannot track which element has focus.

**Fix:** Ensure all interactive elements have visible focus styles:
```css
/* In app.css or tailwind config */
@layer base {
  a:focus-visible, button:focus-visible, input:focus-visible, select:focus-visible {
    @apply ring-2 ring-blue-500 ring-offset-2 ring-offset-gray-900 outline-none;
  }
}
```

#### 12. [3.2.2 On Input] User Menu Without ARIA States

**Severity:** MEDIUM
**File:** `lib/sensocto_web/components/layouts/app.html.heex` (line 43)

**Issue:** User menu button has `aria-label="User menu"` but the dropdown lacks `aria-expanded`, `role="menu"`, and `aria-haspopup` attributes. Screen readers cannot communicate the menu state.

### Positive Accessibility Patterns Found

These are already implemented correctly:

1. **`<.modal>` component** (`core_components.ex` lines 83-129): Properly implements `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, `aria-describedby`, `Phoenix.LiveView.JS.focus_wrap()`, and Escape key handling. **Fully documented** in `/docs/modal-accessibility-implementation.md`.

2. **Flash messages** (`core_components.ex` line 156): Already have `aria-live="assertive"` for immediate announcements.

3. **Search input** (`search_live.ex`): Has `role="search"` on form, `aria-label="Search sensors, rooms, and users"` on input, and keyboard handlers for ArrowUp/ArrowDown/Enter/Escape.

4. **Join code input** (`lobby_live.html.heex` lines 942-968): Properly uses `label for`, matching `id`, and `aria-describedby` for error association.

5. **Breadcrumbs** (`core_components.ex` line 740): Uses `aria-label="Breadcrumb"`.

6. **Tabs** (`core_components.ex` line 777): Uses `aria-label="Tabs"`.

7. **Language attribute** (`root.html.heex`): Uses Gettext locale for `lang` attribute.

8. **Bottom navigation** (`bottom_nav.ex`): Includes visible text labels alongside icons.

---

## Usability Findings (UNCHANGED)

### High Priority Issues

1. **Form Validation Feedback Missing** — The join room modal in lobby_live shows generic error messages. When a join code is invalid, the error should specify whether the code was not found, expired, or in the wrong format.

2. **Loading States Not Shown** — Async operations (sensor data loading, room joining, historical data fetch) do not display visible loading indicators beyond the virtual scroll spinner. Users see empty areas without explanation.

3. **Custom Modals Lack Consistent UX** — The three custom modals in lobby_live.html.heex (Join Room, Control Request, Media Control Request) have different behavior patterns compared to modals built with `<.modal>`. Closing behavior, animation, and keyboard handling are inconsistent.

### Medium Priority Issues

4. **Empty States Lack Next Actions** — When no sensors are connected or no rooms exist, the UI shows minimal guidance. Empty states should include clear calls to action.

5. **Bottom Navigation Small Text** — `text-[10px]` in bottom_nav.ex is very small and may be difficult to read on some devices. Consider `text-xs` (12px) minimum.

6. **Search Listbox Missing ARIA Attributes** — The search results dropdown in search_live.ex is missing `role="listbox"`, `aria-activedescendant`, and `aria-selected` on items.

### Low Priority Issues

7. **"View all" Links Lack Context** — In index_live.html.heex, "View all" links lack context for screen readers. Use `aria-label="View all sensors"` or visually hidden text.

8. **Admin Dashboard Color-Only Status** — System status uses colored dots alongside text, but adding icons would provide redundant visual cues.

---

## Accessibility Test Coverage

### Existing Tests (Good)

**`test/sensocto_web/components/modal_accessibility_test.exs` (14 tests):**
- Modal renders with role="dialog"
- Modal has aria-modal="true"
- Modal has aria-labelledby pointing to title
- Modal has aria-describedby pointing to description
- Modal includes focus_wrap for focus trapping
- Close button has aria-label
- Modal backdrop closes on click
- Escape key closes modal
- Modal title uses proper heading level
- Modal content area is a semantic section
- Modal close button is keyboard accessible
- Modal has proper z-index stacking
- Multiple modals stack correctly
- Modal announces state to screen readers

**`test/sensocto_web/components/core_components_test.exs` (10 tests):**
- Modal renders with ARIA attributes
- Modal close button
- Flash messages with role="alert"
- Table component renders
- Input components render with labels

**Comprehensive documentation:** `/docs/modal-accessibility-implementation.md` covers implementation, testing, WCAG compliance, and maintenance.

### Missing Accessibility Tests

1. **Skip navigation link** — No test verifies its existence (it does not exist yet)
2. **Keyboard navigation flows** — No tests verify tab order through major page flows
3. **Dynamic content announcements** — No tests for aria-live regions (only 1 exists)
4. **Color contrast** — No automated contrast testing
5. **Focus management** — No tests for focus movement on modal open/close in custom modals
6. **Sensor tile accessibility** — No tests for StatefulSensorLive/Component ARIA attributes
7. **Call UI accessibility** — No tests for call-related accessibility
8. **Search combobox pattern** — No tests for search ARIA roles and states
9. **Bottom navigation** — No tests for current page indicator accessibility
10. **Page titles** — No tests verify dynamic page titles

### Suggested Accessibility Tests

```elixir
defmodule SensoctoWeb.AccessibilityTest do
  use SensoctoWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "skip navigation" do
    test "skip link exists and targets main content", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/href="#main".*[Ss]kip/
      assert html =~ ~r/<main[^>]*id="main"/
    end
  end

  describe "page titles" do
    test "lobby page has descriptive title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      assert html =~ "<title>Lobby"
    end

    test "index page has descriptive title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "<title>"
      refute html =~ "<title></title>"
    end
  end

  describe "landmark regions" do
    test "page has main landmark", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      assert html =~ "<main"
    end

    test "navigation is labeled", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      assert html =~ ~r/<nav[^>]*aria-label/
    end
  end

  describe "dynamic content" do
    test "lobby has aria-live region for sensor count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      assert html =~ ~r/aria-live.*sensor/i or html =~ ~r/sensor.*aria-live/i
    end

    test "flash messages have aria-live", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      # Flash component already has aria-live="assertive"
      assert html =~ "aria-live"
    end
  end

  describe "icon-only buttons" do
    test "all icon-only buttons have aria-label", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      # Extract all <button> elements with SVG children
      # Verify each has aria-label or aria-labelledby
    end
  end
end
```

---

## Planned Work: Testing and Accessibility Implications

This section analyzes all current plan files and their implications for testing, accessibility, and usability.

### 1. Startup Optimization (PLAN-startup-optimization.md)

**Status:** IMPLEMENTED (2026-01-31)

**Testing Implications:**
- The async startup pattern (deferred hydration via `Process.send_after` and `Task.Supervisor`) requires tests that verify the application becomes HTTP-responsive within the target window (1-2 seconds) even before hydration completes.
- Tests should verify that late-arriving hydration data (scenarios, battery states, track positions) correctly updates GenServer state without race conditions.
- Negative tests: verify behavior when `Ash.read/2` fails during async hydration (returns `{:error, reason}`), ensuring the GenServer does not crash.

**Accessibility Implications:**
- When the application starts but sensors have not yet hydrated, users see an empty or partially loaded lobby. The loading state should communicate "Sensors loading..." via an `aria-live` region so screen reader users understand the page is not yet fully populated.
- The virtual scroll spinner (lines 559-667 in lobby_live.html.heex) should have `aria-label="Loading sensors"` and be wrapped in an `aria-live="polite"` region.

**Usability Implications:**
- Users connecting during the 5-6 second hydration window will see an empty sensor list. A clear loading indicator with a message like "Connecting to sensors..." would prevent confusion.

---

### 2. Sensor Component Migration (PLAN-sensor-component-migration.md)

**Status:** IN PROGRESS (StatefulSensorComponent exists alongside StatefulSensorLive)

**Testing Implications:**
- **Unit tests needed:** StatefulSensorComponent rendering with minimal assigns, all event handlers (toggle_highlight, toggle_view_mode, toggle_favorite, show_map_modal, show_detail_modal, etc.), throttle buffer accumulation and flush behavior.
- **Integration tests needed:** Parent (LobbyLive) forwarding measurements via `send_update/3`, virtual scroll creating and destroying components cleanly, attention events flowing through parent to AttentionTracker.
- **Performance tests needed:** Scroll 100+ sensors without page reload, compare CPU/memory between LiveView and LiveComponent implementations.
- **Regression tests needed:** Favorites toggle persists, pin/unpin works, modals open/close correctly, latency measurement continues working.
- The migration from `live_render` to `live_component` changes the event routing. All `phx-target` attributes must be verified to point to `@myself` in the component, not the parent.

**Accessibility Implications:**
- The migration is an opportunity to fix the sensor tile accessibility issues: add `role="dialog"` to map and detail modals within the component, add `aria-label` to all icon-only buttons, and implement proper focus management.
- Since all sensor components will run in the parent process, the parent LobbyLive can implement a centralized `aria-live` region for sensor status announcements.
- The template extraction phase (Phase 6) should create sub-components with proper semantic HTML (use `<article>` for sensor tiles, `<dialog>` for modals).

**Usability Implications:**
- The primary goal (eliminating full page reloads on scroll) directly improves usability.
- Process reduction (73 processes to 1) should reduce latency and improve responsiveness.

---

### 3. Adaptive Video Quality (PLAN-adaptive-video-quality.md)

**Status:** 100% COMPLETE (code implemented, needs integration testing)

**Testing Implications:**
- **No tests exist** for any of the four backend modules (CallServer attention tracking, QualityManager tier calculation, SnapshotManager ETS storage, CallChannel handlers) or the four frontend modules (SpeakingDetector, AdaptiveProducer, AdaptiveConsumer, AttentionTracker).
- **Priority tests to write:**
  - QualityManager: tier calculation logic (speaking + attention level -> tier), bandwidth estimation
  - CallServer: participant join/leave, speaking state update, attention state update, tier change broadcast
  - SnapshotManager: snapshot storage/retrieval, TTL-based cleanup (60s), ETS table management
  - CallChannel: `speaking_state`, `attention_state`, `video_snapshot` message handlers
- **Integration tests:** End-to-end tier change flow from speaking detection to quality adjustment.

**Accessibility Implications:**
- **Quality tier indicators** on participant video tiles need ARIA attributes. Each badge should have `role="status"` and be part of an `aria-live="polite"` region.
- **Speaking detection indicator** must be accessible. Use `aria-label` on the participant tile: `aria-label="User name, currently speaking"`.
- **Snapshot mode transition** replaces a `<video>` element with an `<img>` element. The `<img>` must have `alt` text and the transition should not cause focus loss.
- **Static avatar mode** needs `alt` text on the avatar image and a visible "Away" indicator.

**Usability Implications:**
- Quality tier transitions should be smooth with CSS transitions to avoid jarring visual changes.
- Users should understand why video quality varies via a tooltip or help text.

---

### 4. Room Persistence Migration (PLAN-room-iroh-migration.md)

**Status:** PLANNED

**Testing Implications:**
- **Unit tests for RoomStore GenServer:** All CRUD operations, join code lookups, user-room index management.
- **Integration tests for IrohRoomSync:** Batched writes to iroh docs, receiving sync events, hydration from iroh docs on startup.
- **Migration tests:** Verify one-time migration script correctly transfers all rooms and memberships from PostgreSQL.
- **Concurrency tests:** Multiple simultaneous room operations should not corrupt in-memory state.
- **Failure tests:** Iroh sync failure should not affect in-memory store operation.

**Accessibility Implications:**
- Room creation and joining forms must maintain accessibility during the migration. All existing `aria-describedby` patterns must be preserved.
- If room loading becomes async, the room listing should show a loading state with `aria-live="polite"`.

**Usability Implications:**
- The migration to in-memory storage should make room operations feel instant.

---

### 5. Delta Encoding for ECG Data (plans/delta-encoding-ecg.md)

**Status:** PLANNED

**Testing Implications:**
- The plan includes a thorough testing strategy with Elixir tests for `DeltaEncoder` and JavaScript tests for `delta_decoder.js`.
- **Additional tests needed:** Feature flag toggle test, PriorityLens integration, LobbyLive integration for both encoded and legacy formats, performance benchmarks.

**Accessibility Implications:**
- No direct accessibility impact since this is a wire-format optimization.
- If decode fails, the waveform gap should be communicated to users via a visible indicator.

**Usability Implications:**
- The 84% bandwidth reduction will significantly improve performance on mobile networks.

---

### 6. Cluster-Wide Sensor Visibility (plans/PLAN-cluster-sensor-visibility.md)

**Status:** PLANNED (HIGH priority)

**Testing Implications:**
- **Multi-node integration tests:** Sensors on Node A visible from Node B, sensor presence propagation within 500ms.
- **Registry migration tests:** Verify Horde.Registry replaces local Registry without breaking existing APIs.
- **Failure mode tests:** Remote node unreachable, split-brain recovery.
- **PubSub request/reply pattern tests:** Timeout handling (5s), fallback to cache.

**Accessibility Implications:**
- When sensors from a remote node become visible (or disappear due to node failure), the UI should announce this change via `aria-live="polite"`.
- Loading states during cross-node data fetch should be accessible.

**Usability Implications:**
- Users should not need to know about cluster topology. The UI should present a unified view.

---

### 7. Distributed Discovery System (plans/PLAN-distributed-discovery.md)

**Status:** PLANNED (HIGH priority, depends on cluster-sensor-visibility)

**Testing Implications:**
- **DiscoveryCache tests:** ETS table creation, fast local reads, staleness detection (5s threshold).
- **SyncWorker tests:** PubSub event handling, debounce behavior, priority processing, periodic full sync, backpressure.
- **Discovery API tests:** Filtering, staleness handling, subscriptions.
- **NodeHealth circuit breaker tests:** Failure threshold, recovery timeout, nodedown/nodeup handling.

**Accessibility Implications:**
- The `{:ok, state, :stale}` response should visually indicate staleness AND communicate it to assistive technology.
- Entity lifecycle events should trigger accessible announcements.

**Usability Implications:**
- Fast local reads from ETS cache will make the lobby feel instant.
- The graceful degradation pattern is excellent for usability.

---

### 8. Sensor Scaling Refactor (plans/PLAN-sensor-scaling-refactor.md)

**Status:** PLANNED

**Testing Implications:**
- **SensorRegistry hybrid tests:** Local + remote lookup.
- **Sharded PubSub tests:** Message routing by attention level.
- **Sharded ETS buffer tests:** Per-socket table lifecycle, concurrent access.
- **RingBuffer tests:** Circular buffer operations, memory bounds.
- **Load testing:** 1000+ sensors, 10,000 messages/second.

**Accessibility Implications:**
- When navigating to a sensor at `:none` attention, the ramp-up delay should be communicated via a loading state in an `aria-live` region.
- Virtual scrolling `aria-live` should announce summary counts (debounced), not individual sensors.

**Usability Implications:**
- Consistent performance whether viewing 10 or 1000 sensors.

---

### 9. Research-Grade Synchronization Metrics (plans/PLAN-research-grade-synchronization.md)

**Status:** PLANNED

**Testing Implications:**
- **SurrogateTest (P0):** IAAFT surrogate generation, null distribution, p-value calculation.
- **PhaseLockingValue (P1):** Pairwise PLV correctness, known-input verification.
- **CrossCorrelation (P1):** TLCC with known lag, peak lag detection.
- **SynchronizationReport:** End-to-end report generation test.
- Tests should verify Pythonx integration fails gracefully if Python packages are unavailable.

**Accessibility Implications:**
- **CompositeSyncMatrix heatmap:** Provide data table alternative, meaningful `alt` text, color-blind safe palette (viridis or cividis).
- **Phase Space Orbit (Canvas):** Provide `aria-label` describing current state.
- **Sync Topology Graph (d3-force):** Include textual summary of cluster structure.
- **ANS Gauge Cluster:** Use `role="meter"` with `aria-valuemin`, `aria-valuemax`, `aria-valuenow`.
- **Session reports:** WTC spectrograms and recurrence plots need descriptive `alt` text and text-based summaries.

**Usability Implications:**
- Performance budgets for real-time visualizations (target: <16ms per frame).
- Consider progressive disclosure: simple Kuramoto R by default, advanced views opt-in.

---

### 10. TURN Server and Cloudflare Integration (plans/PLAN-turn-cloudflare.md)

**Status:** IMPLEMENTED (code done, pending Cloudflare key setup on Fly.io)

**Testing Implications:**
- **CloudflareTurn module tests:** Credential generation (mock HTTP), caching, TTL refresh threshold, graceful failure.
- **Calls.get_ice_servers/0 tests:** STUN + TURN merge, fallback to STUN-only.
- **Secret management:** Handle missing env vars gracefully.

**Accessibility Implications:**
- When TURN is unavailable and a call fails, provide a clear, actionable error message.
- Call connection status changes should be announced via `aria-live="assertive"`.

**Usability Implications:**
- TURN support is critical for mobile users behind symmetric NAT/CGNAT.
- The `persistent_term` caching strategy minimizes API calls while ensuring credential validity.

---

## Priority Actions

### Immediate (1-2 days) — ACCESSIBILITY CRITICAL

1. **Add `aria-label` to all icon-only buttons** across lobby_live.html.heex, stateful_sensor_live.html.heex, and stateful_sensor_component.html.heex. (Est: 30+ buttons)

2. **Add skip navigation link** to root.html.heex targeting `<main id="main">`.

3. **Add `aria-live="polite"` region to lobby** for sensor count and connection status.

4. **Add `aria-live` regions for composite lens updates** (heartrate, ECG, breathing values).

### Week 1 — ACCESSIBILITY + CRITICAL TESTS

5. **Migrate custom modals in lobby_live.html.heex** to use the accessible `<.modal>` component (documented in `/docs/modal-accessibility-implementation.md`).

6. **Fix color contrast** by replacing `text-gray-400` with `text-gray-300` on dark backgrounds.

7. **Create basic LobbyLive tests** — mount, lens navigation, join modal, composite data extraction.

8. **Create CallServer unit tests** — participant management, quality tier calculation (complements regression_guards tests).

9. **Make quality dropdown keyboard accessible** — toggle button + `aria-expanded`.

### Weeks 2-4 — ACCESSIBILITY + TEST COVERAGE EXPANSION

10. **Implement dynamic page titles** across all LiveView modules.

11. **Add `role="dialog"` and focus management** to sensor tile modals (Map Modal, Detail Modal).

12. **Create QualityManager and SnapshotManager tests.**

13. **Create CloudflareTurn tests** with HTTP mocking.

14. **Add `aria-activedescendant` and `aria-selected`** to search results listbox.

15. **Add `aria-current="page"`** to bottom navigation active item.

16. **Write accessibility tests** for skip navigation, page titles, landmarks, dynamic content (using suggested test cases above).

### Weeks 5-8 — COMPREHENSIVE COVERAGE

17. **Expand test coverage to 25%** by adding tests for IndexLive, SystemStatusLive, CustomSignInLive.

18. **Create Wallaby E2E accessibility tests** for keyboard navigation flows (extend existing E2E suite documented in `/docs/e2e-testing.md`).

19. **Add automated color contrast testing** to CI pipeline (consider `ex_check` with custom contrast checker).

20. **Plan accessibility audit for upcoming features** (sync matrix, phase space orbit, research-grade visualizations).

---

## Test Coverage Summary by Area

| Area | Files | Test Files | Coverage Estimate | Priority |
|------|-------|------------|------------------|----------|
| **Regression Guards** | N/A | **1 (NEW)** | **N/A** | **Maintenance** |
| OTP/Supervision | 15+ | 3 | ~25% | Medium |
| LiveView Modules | 46 | 4 | ~5% | **CRITICAL** |
| Components | 14 | 2 | ~15% | High |
| Calls System | 6 | 0 | **0%** | **CRITICAL** |
| Lenses | 4 | 1 | ~30% | Medium |
| Channels | 3 | 0 | **0%** | High |
| Simulator | 10+ | 2 | ~15% | Medium |
| Bio Layer | 5 | 2 | ~40% | Low |
| API/Plugs | 5 | 3 | ~50% | Low |
| E2E/Integration | N/A | 4 | N/A | Good |
| Encoding (planned) | 0 | 0 | N/A | Medium |
| Discovery (planned) | 0 | 0 | N/A | High |

---

## Key Improvements Since Last Update

### Testing Improvements
- **Regression Guards Test Suite** (49 tests, 766 lines) — Major addition protecting data pipeline contracts
- **Test count increased** from 291 to 373 (+82 tests)
- **E2E test documentation** added (`/docs/e2e-testing.md`)
- **Modal accessibility documentation** added (`/docs/modal-accessibility-implementation.md`)

### Accessibility Status
- **No regression** — All previous accessibility issues remain
- **No new violations introduced** — Custom modals still bypass accessible component
- **Documentation improved** — Modal accessibility fully documented with WCAG compliance details

### Code Quality
- **Sensor data helper** extracted to `/lib/sensocto_web/live/helpers/sensor_data.ex`
- **About content component** enhanced with video/image content

---

## Appendix: Files Referenced

### Templates and Components Reviewed
- `lib/sensocto_web/live/lobby_live.html.heex`
- `lib/sensocto_web/live/index_live.html.heex`
- `lib/sensocto_web/live/stateful_sensor_live.html.heex`
- `lib/sensocto_web/live/components/stateful_sensor_component.html.heex`
- `lib/sensocto_web/live/components/about_content_component.ex`
- `lib/sensocto_web/live/helpers/sensor_data.ex` (NEW)
- `lib/sensocto_web/components/core_components.ex`
- `lib/sensocto_web/components/layouts/root.html.heex`
- `lib/sensocto_web/components/layouts/app.html.heex`
- `lib/sensocto_web/components/layouts/auth.html.heex`
- `lib/sensocto_web/components/bottom_nav.ex`
- `lib/sensocto_web/components/navbar.ex`
- `lib/sensocto_web/live/search_live.ex`
- `lib/sensocto_web/live/custom_sign_in_live.ex`
- `lib/sensocto_web/live/admin/system_status_live.html.heex`

### Test Files Reviewed
- `test/sensocto/regression_guards_test.exs` (NEW — 49 tests)
- `test/sensocto_web/components/modal_accessibility_test.exs` (14 tests)
- `test/sensocto_web/components/core_components_test.exs` (10 tests)
- `test/sensocto_web/live/stateful_sensor_live_test.exs` (2 tests)
- `test/sensocto/lenses/priority_lens_test.exs` (20 tests)
- `test/sensocto/supervision/supervision_tree_test.exs` (31 tests)
- `test/sensocto_web/features/media_player_feature_test.exs` (20 tests)
- `test/sensocto_web/features/collab_demo_feature_test.exs` (13 tests)
- `test/sensocto_web/features/whiteboard_feature_test.exs` (~10 tests)
- `test/sensocto_web/features/object3d_player_feature_test.exs` (~10 tests)
- `test/sensocto_web/plugs/rate_limiter_test.exs` (13 tests)
- `test/sensocto_web/openapi_test.exs` (2 tests)
- `test/sensocto/bio/homeostatic_tuner_test.exs` (~15 tests)
- `test/support/feature_case.ex`

### Documentation Reviewed
- `docs/modal-accessibility-implementation.md` (NEW)
- `docs/e2e-testing.md` (NEW)
- `docs/architecture.md`
- `docs/attention-system.md`
- `docs/attributes.md`
- `docs/supervision-tree.md`

### Plan Files Analyzed
- `PLAN-startup-optimization.md`
- `PLAN-sensor-component-migration.md`
- `PLAN-adaptive-video-quality.md`
- `PLAN-room-iroh-migration.md`
- `plans/PLAN-cluster-sensor-visibility.md`
- `plans/PLAN-distributed-discovery.md`
- `plans/PLAN-sensor-scaling-refactor.md`
- `plans/PLAN-research-grade-synchronization.md`
- `plans/PLAN-turn-cloudflare.md`

---

## Summary

**Testing:** Significant progress with the addition of 49 regression guard tests protecting data pipeline contracts. However, critical gaps remain: LobbyLive (0 tests), IndexLive (0 tests), CallServer (0 tests), and the entire calls system have zero test coverage.

**Accessibility:** No progress since Feb 15. The codebase has only 1 `aria-live` region (flash messages) and 0 `aria-label` attributes in the lobby view. This is a **critical gap** for a real-time sensor monitoring application where dynamic content updates are central to the user experience. Screen reader users are effectively unable to use the application for its primary purpose (monitoring sensor data in real-time).

**Next Steps:** Prioritize accessibility fixes (aria-live regions, aria-label on icon-only buttons, skip navigation, custom modal migration) alongside test coverage expansion for critical user-facing modules (LobbyLive, IndexLive, CallServer).
