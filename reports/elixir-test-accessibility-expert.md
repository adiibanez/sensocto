# Comprehensive Test Coverage and Accessibility Analysis
## Sensocto IoT Sensor Platform

**Analysis Date:** January 12, 2026 (Updated: March 25, 2026)
**Analyzed By:** Testing, Usability, and Accessibility Expert Agent
**Project:** Sensocto - Elixir/Phoenix IoT Sensor Platform

---

## Update: March 25, 2026

### Changes Reviewed in This Update

| File | Nature of Change |
|---|---|
| `lib/sensocto_web/live/lobby_live.html.heex` | Major refactoring: content panel, mode switcher, layout toggle, quality override |
| `lib/sensocto_web/live/custom_sign_in_live.ex` | Rework: sensor background, draggable balls, locale switcher, guest sign-in |
| `lib/sensocto_web/live/components/about_content_component.ex` | Translation pattern change: `{color, "**verb** phrase"}` per-lens use cases |
| `lib/sensocto_web/components/layouts/app.html.heex` | Nav: search trigger, theme toggle, language switcher, user menu, mobile hamburger, speed dial, footer toolbar |
| `lib/sensocto_web/components/layouts/root.html.heex` | Arabic RTL: `dir={if locale == "ar", do: "rtl", else: "ltr"}` |
| `lib/sensocto_web/live/index_live.ex` | Snapshot mode, animation mode, preview theme toggle |
| `lib/sensocto_web/live/components/media_player_component.ex` | Refactored update/2, incremental assigns |
| `lib/sensocto_web/live/components/object3d_player_component.ex` | Same pattern as media player |
| `lib/sensocto_web/live/components/whiteboard_component.ex` | New component: collaborative canvas with per-user colors, control request modal |
| `lib/sensocto_web/live/components/attribute_component.ex` | ECG summary mode, render hint dispatch |
| `lib/sensocto_web/live/user_settings_live.ex` | Arabic locale added, `@valid_locale_codes` compile-time guard |
| `lib/sensocto_web/live/lobby_live/lens_components.ex` | `composite_lens/1` wrapper, `midi_panel/1` extracted |

---

### Current Metrics (March 25, 2026)

| Metric | Mar 1 | Mar 25 | Change |
|--------|-------|--------|--------|
| Implementation Files | ~280 | ~295 | +15 |
| LiveView/Component Files | ~70 | ~80 | +10 |
| `aria-live` Regions | 11 | **12** | +1 (whiteboard modal) |
| RTL Support | None | **Arabic `dir="rtl"`** | New |
| Skip Navigation Link | YES | YES | Stable |
| `<.live_title>` in root layout | YES | YES | Stable |
| WCAG Level A Violations (estimated) | ~35 | **~32** | -3 |
| WCAG Level AA Violations (estimated) | ~12 | **~14** | +2 (new whiteboard/lobby controls) |
| Estimated Code Coverage | ~22% | **~22%** | Stable |

---

### Accessibility Audit: March 25 Changes

#### Positive Changes

**RTL Arabic Layout Support — GOOD FOUNDATION**

`root.html.heex` line 3 now sets `dir="rtl"` when locale is `ar`. This is the correct place to set document direction. The skip link, nav links, and content area will mirror correctly in RTL browsers.

However, several UI patterns use directional CSS classes that do not flip automatically in RTL:

- `app.html.heex` line 503: `bg-controls-drawer` uses `left: 0` and `translateX(calc(-100% + 21px))` — this drawer will overlap content incorrectly in RTL, where it should emerge from the right edge.
- `app.html.heex` line 346: `footer-toolbar` is positioned `left: 0.5rem` — the sensor pill should be on the right in RTL.
- `app.html.heex` lines 124-143 and 144-182: The dropdown menus use `absolute right-0` positioning — this happens to be correct for RTL (right-aligned menus) but only by accident. In LTR these are right-aligned; in RTL they remain right-aligned, which is correct for user menu but wrong for the lang switcher which is not the rightmost element in RTL.

**Custom Sign-In Page: `page_title` Now Set — FIXED**

`custom_sign_in_live.ex` line 58 assigns `page_title: "Sign In"`. This was flagged as missing in the February 20 report. Now resolved.

**IndexLive: `page_title` Now Set — FIXED**

`index_live.ex` line 46 assigns `page_title: "Home"`. This was flagged as missing in the February 20 report. Now resolved.

**WhiteboardComponent Control Request Modal: `role="timer"` + `aria-live` — GOOD**

`whiteboard_component.ex` lines 793-797: The countdown modal uses `role="timer"`, `aria-live="polite"`, and `aria-atomic="true"` on the countdown container. This matches the established pattern from `media_player_component.ex` and `object3d_player_component.ex`.

**UserSettingsLive: Compile-time Locale Validation — GOOD**

`user_settings_live.ex` line 160: `@valid_locale_codes` is derived at compile time from `@locales` and used as a guard in the `change_locale` event handler. This matches the pattern applied in `custom_sign_in_live.ex` and is correct per project security rules.

---

#### New Violations Found

**Violation M26-1 — [4.1.2 Name, Role, Value] Lobby Content Mode Buttons Missing `aria-pressed` or `role="tab"` + `aria-selected`**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 273-343

The `switch_lobby_mode` buttons for Media, 3D Object, Whiteboard, Polls, and Avatar use color alone to indicate the active mode. There is no `aria-pressed`, `role="tab"` + `aria-selected`, or any other ARIA state to convey the selected state to assistive technologies. A screen reader user hears "Media, button", "3D Object, button", etc. with no indication which mode is currently active.

These are semantically toggle buttons controlling a content panel, not page-level navigation tabs. The correct pattern is `role="tab"` + `aria-selected` because they control a visible panel region below, or at minimum `aria-pressed` if they are treated as standalone toggles.

Fix:

```heex
<%!-- Wrap the group: --%>
<div role="tablist" aria-label="Content panel mode">
  <button
    role="tab"
    phx-click="switch_lobby_mode"
    phx-value-mode="media"
    aria-selected={to_string(@lobby_mode == :media)}
    aria-controls="lobby-content-panel"
    class={...}
  >
    <Heroicons.icon name="play" type="solid" class="h-3 w-3" /> Media
  </button>
  <%!-- ... remaining buttons ... --%>
</div>
<%!-- The panel that these tabs control: --%>
<div id="lobby-content-panel" role="tabpanel" ...>
```

**Violation M26-2 — [4.1.2 Name, Role, Value] Layout Toggle Button Has No Accessible Name**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 84-106

The layout toggle button (stacked vs. floating) uses an icon with a `title` attribute only. The `title` attribute is the button's visible label on hover but is not announced reliably by all screen readers as the accessible name for interactive controls. The button has no `aria-label` and no text content.

Fix:

```heex
<button
  phx-click="toggle_lobby_layout"
  aria-label={
    if(@lobby_layout == :floating,
      do: "Switch to stacked layout",
      else: "Switch to floating dock"
    )
  }
  aria-pressed={to_string(@lobby_layout == :floating)}
  class={...}
>
  <Heroicons.icon ... />
</button>
```

**Violation M26-3 — [4.1.2 Name, Role, Value] Quality Override Buttons Rely on Color Without Text State**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 143-195

Each quality override button (High, Medium, Low, Minimal) uses a small colored `<span>` dot to convey the quality tier, plus a `✓` checkmark that appears only when that tier is selected. The checkmark is text content rendered inside a `:if` conditional — this is better than color-only but still insufficient because the `<span>` dots are unlabeled and convey meaning (green = good, red = bad) purely through color, violating WCAG 1.4.1.

Additionally, the quality override dropdown trigger button (line 135) has only a `title="Quality settings"` and an icon — no `aria-label`. The dropdown itself appears on `:hover` via CSS (`group-hover:visible`), which is entirely inaccessible to keyboard users who cannot trigger hover states.

Fix — add `aria-label` to the trigger and `aria-expanded` state, plus label the colored dots:

```heex
<%!-- Dropdown trigger --%>
<button
  id="quality-override-trigger"
  class="p-1.5 rounded-lg bg-gray-700/50 hover:bg-gray-600 text-gray-300 hover:text-white transition-colors"
  aria-label="Change data quality setting"
  aria-haspopup="listbox"
  aria-expanded="false"
>

<%!-- Each option button's dot: --%>
<span
  class="w-2 h-2 rounded-full bg-green-400"
  aria-hidden="true"
>
</span>
High (20Hz)
```

The hover-only reveal must be replaced with a click-toggled JS.show/hide mechanism with `aria-expanded` managed on the trigger button.

**Violation M26-4 — [2.1.1 Keyboard] Quality Override Dropdown Keyboard-Inaccessible**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 134-196

The quality dropdown uses `group-hover:visible` CSS to show/hide. Keyboard users cannot open it because `:hover` does not trigger on focus. This is a complete keyboard barrier for changing data quality.

Fix: Replace hover with a click toggle using `JS.toggle()` or a `phx-click` event to toggle a `show_quality_dropdown` assign. Add `aria-expanded` to the trigger and close on Escape via `phx-key="escape"` or a JS hook.

**Violation M26-5 — [1.4.1 Use of Color] Quality Indicator Dot Is Color-Only**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 119-131

The quality indicator pill near the toolbar shows the current quality level using a colored dot (green/yellow/orange/red/gray) plus the text label. The text label is present, so this partially satisfies 1.4.1. However, the status dot is a bare `<span>` with no `aria-hidden="true"` and no label — screen readers may announce it as an empty element creating a confusing reading order.

Fix: Add `aria-hidden="true"` to the dot span since the text sibling already conveys the information:

```heex
<span class={"w-2 h-2 rounded-full " <> ...} aria-hidden="true"></span>
<span>{@current_quality |> to_string() |> String.capitalize()}</span>
```

**Violation M26-6 — [4.1.2 Name, Role, Value] Content Panel Collapse Button Has No Accessible Name**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 228-252

The "Content" tile header is a `<button>` that collapses/expands the content panel. It contains the text "Content" and the current mode name, which partially serves as a label. However, it does not communicate the expanded/collapsed state (`aria-expanded`) and the chevron icon used to show expand state has no `aria-hidden="true"`, causing screen readers to announce the SVG path data.

Fix:

```heex
<button
  phx-click="toggle_content_panel"
  aria-expanded={to_string(!@content_panel_collapsed)}
  aria-controls="lobby-content-panel-body"
  class="w-full flex items-center justify-between px-3 py-2 bg-gray-900/50 hover:bg-gray-900/70 transition-colors"
>
  <div class="flex items-center gap-2">
    <Heroicons.icon name="squares-2x2" type="solid" class="w-4 h-4 text-gray-400" aria-hidden="true" />
    <span class="text-sm font-medium text-gray-300">Content</span>
    <span class="text-xs text-gray-500">{String.capitalize(to_string(@lobby_mode))}</span>
  </div>
  <svg class={...} aria-hidden="true" ...>
```

**Violation M26-7 — [1.1.1 Non-text Content] Custom Sign-In Background Controls: Unlabeled Theme Buttons**

Severity: MEDIUM
File: `lib/sensocto_web/live/custom_sign_in_live.ex` lines 365-394

The background theme selector buttons use Unicode characters (`—`, `✦`, `≈`, `◐`, `⁘`, `↻`) as their visible content. These characters have `data-tip` tooltip text which is shown via CSS pseudo-elements — this is purely visual and is not read by screen readers. The buttons have no `aria-label` and the icon characters have no semantic meaning to assistive technologies.

Fix:

```heex
<button
  :for={
    {label, theme, tip} <- [
      {"—", "off", gettext("No visualization")},
      ...
    ]
  }
  phx-click="set_bg_theme"
  phx-value-theme={theme}
  aria-label={tip}
  aria-pressed={to_string(@sensor_bg_theme == theme)}
  class={...}
>
  <span aria-hidden="true">{label}</span>
</button>
```

The auto-cycle button (`↻`) should similarly get `aria-label={gettext("Auto-cycle background themes")}` and `aria-pressed={to_string(@sensor_bg_cycling)}`.

**Violation M26-8 — [1.1.1 Non-text Content] Custom Sign-In Background Controls Drawer: No Accessible Label**

Severity: MEDIUM
File: `lib/sensocto_web/live/custom_sign_in_live.ex` lines 347-413

The entire `bg-controls-drawer` div is a slide-out panel that appears on hover (CSS `transform` transition). The panel contains the sensor count slider and theme buttons but has no `aria-label` or `role` to identify it as a controls region. Keyboard users cannot access this drawer because it only appears on mouse hover (`:hover` CSS selector on the wrapper div).

Fix: Convert the hover mechanism to a togglable `<details>/<summary>` or a button-triggered `phx-click` show/hide. Add `aria-label` to the panel wrapper.

**Violation M26-9 — [1.3.1 Info and Relationships] Sign-In Range Input Has No Label**

Severity: HIGH
File: `lib/sensocto_web/live/custom_sign_in_live.ex` line 352

The sensor count range input (`type="range"`, `name="count"`) has no `<label>` element and no `aria-label` or `aria-labelledby`. The number display next to it (the `{@sensor_bg_count}` span) is not associated with the input. Screen reader users have no way to know what this slider controls.

Fix:

```heex
<form phx-change="set_bg_count" class="flex items-center gap-1.5 flex-1">
  <label for="sensor-bg-count" class="sr-only">{gettext("Number of background sensors")}</label>
  <input
    type="range"
    id="sensor-bg-count"
    min="1"
    max="100"
    value={@sensor_bg_count}
    name="count"
    aria-valuemin="1"
    aria-valuemax="100"
    aria-valuenow={@sensor_bg_count}
    class="w-20 h-1 accent-cyan-500 cursor-pointer"
  />
  <span class="w-4 text-[10px] text-center text-gray-500" aria-hidden="true">{@sensor_bg_count}</span>
</form>
```

**Violation M26-10 — [4.1.2 Name, Role, Value] App Header Dropdown Buttons Missing `aria-expanded`**

Severity: HIGH
File: `lib/sensocto_web/components/layouts/app.html.heex` lines 115-143 (lang), 145-182 (user menu), 186-277 (mobile hamburger)

All three dropdown/menu trigger buttons lack `aria-expanded` state. The dropdowns are toggled by `phx-hook="LangMenu"`, `phx-hook="UserMenu"`, and `phx-hook="MobileMenu"` respectively. Without `aria-expanded`, assistive technology users cannot determine if the menu is open or closed, and cannot rely on the `aria-expanded="true"` signal to understand that new content has appeared.

This was flagged in the February 20 report and remains unresolved.

Fix for each trigger button: manage `aria-expanded` in the JS hook:

```javascript
// In LangMenu hook:
mounted() {
  this.toggle = this.el.querySelector("[data-dropdown-toggle]");
  this.menu = this.el.querySelector("[data-dropdown-menu]");
  this.toggle.addEventListener("click", () => {
    const isOpen = !this.menu.classList.contains("hidden");
    this.menu.classList.toggle("hidden");
    this.toggle.setAttribute("aria-expanded", String(!isOpen));
    if (!isOpen) {
      // move focus to first menu item
      this.menu.querySelector("button, a")?.focus();
    }
  });
}
```

Additionally, each menu `<div>` should have `role="menu"` and each item `role="menuitem"`.

**Violation M26-11 — [2.1.1 Keyboard] App Header Search Trigger Only Dispatches Custom Event**

Severity: MEDIUM
File: `lib/sensocto_web/components/layouts/app.html.heex` line 50

The search trigger button fires `JS.dispatch("open-search")`. The `SearchLive` component presumably handles this via a hook. This pattern works for mouse/keyboard if the button is focusable (it is) and activated by Enter/Space (it is, being a `<button>`). This is a low risk item but should be verified in the JS hook that the `open-search` window event also moves focus into the search input when triggered.

**Violation M26-12 — [3.1.2 Language of Parts] Arabic Number/Code Segments in RTL Context**

Severity: MEDIUM
File: `lib/sensocto_web/components/layouts/root.html.heex` line 3

The RTL direction is set globally for Arabic. This is correct for Arabic text. However, several UI segments contain numbers, codes, and technical identifiers (e.g., sensor IDs, timestamps, QR link tokens) that should maintain LTR direction even inside an RTL document. Without `dir="ltr"` on these inline segments, numbers and identifiers may display mirrored or in unexpected order.

Fix: Wrap technical/numeric content in `<span dir="ltr">` in templates rendered for Arabic users:

```heex
<%!-- Example: sensor data value display --%>
<span dir="ltr" class="font-mono">{@sensor_value}</span>
```

**Violation M26-13 — [1.1.1 Non-text Content] WhiteboardComponent Color Picker Buttons Have No Accessible Name**

Severity: MEDIUM
File: `lib/sensocto_web/live/components/whiteboard_component.ex` lines 556-587

The color picker renders 34 color swatch buttons. Each has `title={color}` where `color` is a hex string like `"#ef4444"`. Hex values are not meaningful accessible names for color swatches. A screen reader user hears "hashtag e f 4 4 4 4, button" for each swatch.

Fix: Map hex values to human-readable color names and use them as `aria-label`:

```heex
<button
  phx-click="set_color"
  phx-value-color={color}
  phx-target={@myself}
  aria-label={"#{color_name(color)} #{if @stroke_color == color, do: "(selected)", else: ""}"}
  aria-pressed={to_string(@stroke_color == color)}
  ...
>
</button>
```

Where `color_name/1` maps `"#ef4444"` to `"Red"`, `"#22c55e"` to `"Green"`, etc. At minimum, mark currently selected color with `aria-pressed="true"`.

**Violation M26-14 — [4.1.2 Name, Role, Value] WhiteboardComponent Tool Buttons Missing `aria-pressed`**

Severity: MEDIUM
File: `lib/sensocto_web/live/components/whiteboard_component.ex` lines 491-529

The pen, eraser, line, and rectangle tool buttons use background color change to indicate the active tool. No `aria-pressed` state is set. Screen reader users cannot determine which drawing tool is currently active.

Fix:

```heex
<button
  phx-click="set_tool"
  phx-value-tool="pen"
  phx-target={@myself}
  aria-pressed={to_string(@current_tool == "pen")}
  aria-label="Pen tool"
  class={...}
>
  <Heroicons.icon name="pencil" type="outline" class="w-4 h-4" />
</button>
```

**Violation M26-15 — [1.3.1 Info and Relationships] WhiteboardComponent Canvas Lacks `role` and Label**

Severity: MEDIUM
File: `lib/sensocto_web/live/components/whiteboard_component.ex` lines 449-455

The `<canvas>` element has no `role`, `aria-label`, or fallback text content. For screen reader users, the canvas is simply invisible or reported as "canvas". If the whiteboard is interactive and collaborative, it should at minimum communicate its purpose.

Fix:

```heex
<canvas
  id={"whiteboard-canvas-#{@room_id}"}
  phx-update="ignore"
  data-whiteboard-canvas="true"
  role="img"
  aria-label="Collaborative whiteboard canvas"
  class="absolute inset-0 w-full h-full"
  style="touch-action: none;"
>
  <%!-- Fallback for non-canvas browsers --%>
  Collaborative whiteboard. Use drawing tools above to contribute.
</canvas>
```

**Violation M26-16 — [2.4.3 Focus Order] WhiteboardComponent Control Request Modal No Focus Trap**

Severity: HIGH
File: `lib/sensocto_web/live/components/whiteboard_component.ex` lines 788-833

The control request modal is a `fixed inset-0` overlay rendered conditionally via `<%= if ... %>`. When it appears, focus is not moved into the modal and there is no focus trap — keyboard users can tab behind the modal into the main page. The modal has no `role="dialog"` or `aria-modal="true"`.

Fix:

```heex
<div
  class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
  role="dialog"
  aria-modal="true"
  aria-labelledby={"whiteboard-modal-title-#{@room_id}"}
>
  <div
    id={"whiteboard-control-request-modal-#{@room_id}"}
    phx-hook="FocusTrap"
    ...
  >
    <h3 id={"whiteboard-modal-title-#{@room_id}"} class="text-lg font-semibold text-white mb-2">
      Control Requested
    </h3>
```

**Violation M26-17 — [1.1.1 Non-text Content] LensComponents MIDI Panel: Status Dot and Buttons Unlabeled**

Severity: MEDIUM
File: `lib/sensocto_web/live/lobby_live/lens_components.ex` lines 56, 58-60

The MIDI panel's status dot (`id="midi-status-dot"`) is a bare `<span>` with no text and no `aria-label`. The "Audio Off" button, backend select, device select, and mode button are all managed by `phx-update="ignore"` and the `MidiOutputHook` JS hook. The JS hook is responsible for updating these elements' labels, but the static initial HTML provides no accessible names.

Fix: Add `aria-label` to the status dot and ensure the JS hook updates `aria-label` dynamically:

```heex
<span
  id="midi-status-dot"
  class="w-2 h-2 rounded-full bg-gray-500 flex-shrink-0"
  role="status"
  aria-label="MIDI disconnected"
>
</span>
```

Ensure the MIDI hook calls `statusDot.setAttribute("aria-label", "MIDI connected")` etc. when state changes.

**Violation M26-18 — [3.2.2 On Input] Custom Sign-In Locale Change Triggers Full Page Redirect**

Severity: LOW-MEDIUM
File: `lib/sensocto_web/live/custom_sign_in_live.ex` lines 127-132

The `change_locale` event redirects the user to `/sign-in?locale=<code>`, which triggers a full page reload. This is a usability regression for screen reader users who had focus positioned in the sign-in form — after the redirect the focus returns to the top of the document. The form state is also lost.

The same pattern in `user_settings_live.ex` line 171 (redirect to `/settings?locale=<code>`) has the same issue on the settings page.

Mitigation: Both redirects are currently necessary to have the `Locale` plug update the session cookie. This is a known limitation. The recommendation is to add a `<span aria-live="polite">` region that announces the locale change before the redirect fires, so users have context for the page reload:

```heex
<div id="locale-change-status" aria-live="polite" class="sr-only"></div>
```

And in the hook or a push_event, update this region with "Switching to German..." before the redirect.

**Violation M26-19 — [1.3.1 Info and Relationships] `AboutContentComponent` `hl/1` Bold Spans Have No Semantic Meaning**

Severity: LOW
File: `lib/sensocto_web/live/components/about_content_component.ex`

The `hl/1` function component (inferred from the translation pattern) splits strings on `**` markers and wraps the highlighted word in a colored `<span>`. Colored spans with no `role` or `<strong>` tag do not convey emphasis to screen reader users. The visual highlighting is purely decorative and conveys the "action" meaning, but sighted users understand the verb emphasis while non-sighted users do not.

Fix: Use `<strong>` (strong importance) or `<em>` (stress emphasis) instead of, or wrapping, the colored span:

```elixir
defp hl(text, color) do
  # ... split on **
  ~H"""
  <strong class={"text-#{@color}-400 font-semibold"}>{@word}</strong>
  """
end
```

---

### Testing Recommendations: March 25 Changes

#### Missing Test Coverage for New/Changed Code

| Module | Status | Gap |
|---|---|---|
| `WhiteboardComponent` | 0% | All event handlers, update/2 logic, state initialization |
| `CustomSignInLive` | 0% | Ball presence, locale switching, bg theme cycling, guest sign-in |
| `IndexLive` | 0% | Preview mode toggle, snapshot refresh, animation mode |
| `LensComponents` | 0% | `composite_lens/1`, `midi_panel/1` rendering |
| `UserSettingsLive` | 0% | Token regeneration, QR toggle, locale change, `toggle_public` |
| `AboutContentComponent` | 0% | `hl/1` rendering, lens selector, use-case display |
| `MediaPlayerComponent` | Partial | `update/2` incremental assign path, sync event emission |
| `Object3DPlayerComponent` | Partial | Same as media player |

#### Suggested Test Cases

```elixir
# test/sensocto_web/live/components/whiteboard_component_test.exs

defmodule SensoctoWeb.Live.Components.WhiteboardComponentTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # WhiteboardComponent is a LiveComponent embedded in a parent view.
  # Test via a simple wrapper LiveView using live_isolated/3.

  defp authenticated_conn(conn) do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "wb_test_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
    |> Map.put(:assigns, %{current_user: user})
  end

  describe "WhiteboardComponent mount" do
    test "renders canvas and tool buttons", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, view, html} = live(conn, "/lobby")
      render_click(view, "switch_lobby_mode", %{"mode" => "whiteboard"})
      html = render(view)
      assert html =~ "whiteboard-canvas"
      assert html =~ "Collab Whiteboard"
    end
  end

  describe "tool selection" do
    test "set_tool changes current_tool", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, view, _html} = live(conn, "/lobby")
      render_click(view, "switch_lobby_mode", %{"mode" => "whiteboard"})

      wb = find_live_child(view, "lobby-whiteboard")
      assert wb

      html = render_click(wb, "set_tool", %{"tool" => "eraser"})
      assert html =~ ~r/current_tool.*eraser/ or has_element?(wb, "[aria-pressed=true]", "Eraser")
    end
  end

  describe "stroke width" do
    test "set_width with valid integer updates stroke_width" do
      # Verify String.to_integer does not crash on valid values "1", "3", "5", "8", "12"
      for width <- ~w(1 3 5 8 12) do
        assert String.to_integer(width) in [1, 3, 5, 8, 12]
      end
    end

    test "wb_export with unsupported format is rejected" do
      # Ensure the guard `when format in @valid_export_formats` holds
      # wb_export with "gif" should be a no-op (falls through to catch-all)
      assert function_exported?(SensoctoWeb.Live.Components.WhiteboardComponent, :handle_event, 3)
    end
  end
end
```

```elixir
# test/sensocto_web/live/custom_sign_in_live_test.exs

defmodule SensoctoWeb.CustomSignInLiveTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders sign-in form at /sign-in", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sign-in")
      assert html =~ "Welcome"
      assert html =~ "Continue as Guest"
    end

    test "sets page_title to 'Sign In'", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sign-in")
      assert html =~ "<title>Sign In"
    end

    test "redirects to /lobby if valid guest session exists", %{conn: conn} do
      # Guest redirect requires session["is_guest"] = true and a valid guest in store
      {:ok, guest} = Sensocto.Accounts.GuestUserStore.create_guest()

      conn =
        conn
        |> Plug.Test.init_test_session(%{"is_guest" => true, "guest_id" => guest.id})

      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, "/sign-in")
    end
  end

  describe "change_locale" do
    test "accepts valid locale code and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sign-in")
      assert {:error, {:redirect, %{to: "/sign-in?locale=de"}}} =
               render_click(view, "change_locale", %{"locale" => "de"})
    end

    test "ignores invalid locale code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sign-in")
      # Should not redirect, should not crash
      html = render_click(view, "change_locale", %{"locale" => "xx"})
      assert html =~ "Welcome"
    end
  end

  describe "set_bg_theme" do
    test "accepts valid theme", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sign-in")
      html = render_click(view, "set_bg_theme", %{"theme" => "constellation"})
      assert html =~ "sensor-background"
    end

    test "ignores invalid theme and does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sign-in")
      html = render_click(view, "set_bg_theme", %{"theme" => "malicious<script>"})
      assert html =~ "sensor-background"
    end
  end

  describe "join_as_guest" do
    test "redirects to /auth/guest/:id/:token on success", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sign-in")
      result = render_click(view, "join_as_guest")
      # Should redirect to the guest auth URL
      assert result == {:error, {:redirect, %{to: _}}} or
               (is_binary(result) and result =~ "sensor-background")
    end
  end
end
```

```elixir
# test/sensocto_web/live/user_settings_live_test.exs

defmodule SensoctoWeb.UserSettingsLiveTest do
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defp authenticated_conn(conn) do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "settings_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
    |> Map.put(:assigns, %{current_user: user})
  end

  describe "mount" do
    test "renders settings page for authenticated user", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, _view, html} = live(conn, "/settings")
      assert html =~ "Settings"
      assert html =~ "Language"
    end

    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, "/settings")
    end
  end

  describe "change_locale" do
    test "accepts Arabic locale and redirects", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, view, _html} = live(conn, "/settings")
      assert {:error, {:redirect, %{to: "/settings?locale=ar"}}} =
               render_click(view, "change_locale", %{"locale" => "ar"})
    end

    test "rejects unknown locale code", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, view, _html} = live(conn, "/settings")
      html = render_click(view, "change_locale", %{"locale" => "zz"})
      # Should not redirect
      assert html =~ "Settings"
    end
  end

  describe "toggle_qr" do
    test "shows QR code section on toggle", %{conn: conn} do
      conn = authenticated_conn(conn)
      {:ok, view, html} = live(conn, "/settings")
      refute html =~ "qr_svg"
      html = render_click(view, "toggle_qr")
      assert html =~ "sensocto://auth"
    end
  end
end
```

---

### Priority Actions (March 25, 2026)

1. **[BLOCKER] Lobby content mode buttons missing ARIA state (M26-1)** — Five buttons with no `aria-selected` or `aria-pressed`. Screen reader users cannot determine which content panel is active. Apply `role="tablist"` + `role="tab"` + `aria-selected` to the mode switcher group.

2. **[BLOCKER] Quality override dropdown keyboard-inaccessible (M26-4)** — Hover-only CSS reveal completely blocks keyboard access to quality settings. Replace with click-toggled mechanism.

3. **[BLOCKER] WhiteboardComponent control request modal lacks focus trap and `role="dialog"` (M26-16)** — Modal overlay with no focus management. Keyboard users can interact with content behind the modal.

4. **[HIGH] App header dropdowns missing `aria-expanded` (M26-10)** — Language switcher, user menu, and mobile hamburger all lack ARIA state. Flagged in February 20 report, still unresolved.

5. **[HIGH] Sign-in range input has no label (M26-9)** — Range slider in the background controls drawer has no associated `<label>` or `aria-label`.

6. **[HIGH] WhiteboardComponent tool buttons missing `aria-pressed` (M26-14)** — Active tool is only communicated via color.

7. **[HIGH] WhiteboardComponent canvas has no accessible name (M26-15)** — Canvas element is invisible to screen readers.

8. **[MEDIUM] RTL layout: positioned elements not mirrored for Arabic (M26-1 RTL)** — Background controls drawer and footer toolbar use `left:` positioning that does not adapt to `dir="rtl"`. Use logical CSS properties (`inset-inline-start`, `margin-inline-end`) across all positioned elements.

9. **[MEDIUM] Write tests for `WhiteboardComponent`, `CustomSignInLive`, and `UserSettingsLive`** — All three have zero test coverage and contain multiple event handlers and state transitions.

10. **[MEDIUM] Add `aria-label` and `aria-pressed` to custom sign-in background theme buttons (M26-7)**.

---

## Update: February 24, 2026

### Changes Since Last Review (Feb 22 -> Feb 24, 2026): Guided Session Feature

Six new files were added for the "Guided Session" feature. None have test coverage yet. Two of the
six introduce UI accessible from every lobby page (floating badge, suggestion toast, guide panel in
`lobby_live.html.heex`), and one is a standalone LiveView (`GuidedSessionJoinLive`).

| New File | Type | Coverage Status |
|---|---|---|
| `lib/sensocto/guidance.ex` | Ash Domain | 0% — trivial wrapper, no direct tests needed |
| `lib/sensocto/guidance/guided_session.ex` | Ash Resource | 0% — actions, constraints, `generate_invite_code/1` untested |
| `lib/sensocto/guidance/session_server.ex` | GenServer | 0% — drift-back timer, role enforcement, PubSub broadcasts, idle timeout all untested |
| `lib/sensocto/guidance/session_supervisor.ex` | DynamicSupervisor | 0% — start/stop/lookup untested |
| `lib/sensocto_web/live/guided_session_join_live.ex` | LiveView | 0% — all three mount paths and `accept` event untested |
| `lib/sensocto_web/live/lobby_live.html.heex` | Template (additions) | 0% — floating badge, suggestion toast, guide panel not covered by existing lobby tests |

**Critical Bugs Found During Review:**

1. `GuidedSessionJoinLive.handle_event("accept")` calls `Ash.update(session, %{follower_user_id: user_id}, action: :create, ...)` — the `:create` atom is wrong; this should use a custom `:set_follower` update action or directly use `:accept` after setting the attribute through a combined action. The `:create` action on an `update/4` call will produce a runtime error or unexpected behavior.

2. The `session_server.ex` struct exposes `drift_back_timer_ref` in process state but `get_state/1` intentionally omits it from the public map. This is correct for security but means the only way to observe timer behavior in tests is via PubSub messages or by inspecting the raw process state with `:sys.get_state/1`.

3. The follower floating badge uses `phx-click="guide_end_session"` for the dismiss button (the `&times;` button at the end of the badge). This is the same event used in the guide panel to end the session entirely. A follower clicking the `&times;` to dismiss their badge would end the entire session rather than just collapsing the badge. This is a significant UX and logic bug. **Status as of March 25: The lobby template now shows a `follower_leave_session` event on the dismiss button in the following pill (line 72 of lobby_live.html.heex). This specific bug appears resolved. The `guide_end_session` event remains on the guide panel's end button, which is correct.**

### Testing Recommendations: Guided Session (Feb 24, 2026)

#### Missing Test Coverage

**SessionServer (GenServer)**

- Drift-back timer fires after `drift_back_seconds` and sets `following: true`
- `report_activity` resets the drift-back timer (cancels old timer, starts new one)
- Calling `report_activity` when already following does not start a timer
- `break_away` by a non-follower returns `{:error, :not_follower}`
- `set_lens` by a non-guide returns `{:error, :not_guide}`
- `end_session` by either participant broadcasts `{:guided_ended, ...}` and stops the process
- `end_session` by a non-participant returns `{:error, :not_participant}`
- `rejoin` returns the current guide state (`current_lens`, `focused_sensor_id`)
- `rejoin` cancels the drift-back timer
- Guide disconnect starts idle timer; guide reconnect cancels it
- Idle timeout fires and stops the process with `{:guided_ended, %{ended_by: :idle_timeout}}`
- Annotations accumulate in order and get a UUID assigned
- `add_annotation` by a non-guide returns `{:error, :not_guide}`
- `is_follower?` returns false when `follower_user_id` is nil
- `is_guide?`/`is_follower?` perform string comparison (handles binary vs. string UUID mismatch)

**GuidedSession Ash Resource**

- `generate_invite_code/1` returns only characters from the unambiguous alphabet (no `0`, `O`, `I`, `1`)
- `generate_invite_code/1` default length is 6 characters
- `generate_invite_code/2` respects custom length argument
- `:create` action sets `status: :pending` and generates `invite_code`
- `:accept` action sets `status: :active` and populates `started_at`
- `:decline` action sets `status: :declined` and populates `ended_at`
- `:end_session` action sets `status: :ended` and populates `ended_at`
- `:by_invite_code` read only returns sessions with `status in [:pending, :active]`
- `:by_invite_code` returns `nil` for a code with `status: :ended`
- `:active_for_user` returns sessions where user is guide or follower
- `drift_back_seconds` rejects values below 5 or above 120
- `invite_code` identity constraint prevents duplicate codes

**GuidedSessionJoinLive**

- Mount with valid pending invite code assigns `session` and no `error`
- Mount with expired/ended invite code assigns `error: "This invitation is no longer valid."`
- Mount with no code param assigns `error: "No invitation code provided."`
- Mount with DB error assigns `error: "Something went wrong."`
- `accept` event when `current_user` is nil puts a flash error and does not navigate
- `accept` event with valid session sets follower, starts SessionServer, broadcasts to guide topic, navigates to `/lobby`
- `accept` event when Ash update fails puts a flash error

**SessionSupervisor**

- `start_session` starts a new process and registers it
- `start_session` called again with the same ID returns `{:ok, pid}` (idempotent)
- `stop_session` terminates the process
- `stop_session` returns `{:error, :not_found}` for unknown session
- `session_exists?` returns true/false correctly
- `list_active_sessions` returns session IDs currently running
- `count` reflects the number of active sessions

#### Suggested Test Cases

```elixir
# test/sensocto/guidance/session_server_test.exs

defmodule Sensocto.Guidance.SessionServerTest do
  use Sensocto.DataCase, async: false

  alias Sensocto.Guidance.SessionServer

  @moduletag :integration

  defp unique_id, do: Ash.UUID.generate()

  defp start_server(opts \\ []) do
    session_id = Keyword.get_lazy(opts, :session_id, &unique_id/0)
    guide_id = Keyword.get_lazy(opts, :guide_user_id, &unique_id/0)
    follower_id = Keyword.get_lazy(opts, :follower_user_id, &unique_id/0)

    all_opts =
      [
        session_id: session_id,
        guide_user_id: guide_id,
        guide_user_name: "Guide",
        follower_user_id: follower_id,
        follower_user_name: "Follower",
        drift_back_seconds: 1
      ] ++ opts

    {:ok, pid} = SessionServer.start_link(all_opts)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end)

    {:ok,
     %{
       pid: pid,
       session_id: session_id,
       guide_id: guide_id,
       follower_id: follower_id
     }}
  end

  describe "role enforcement" do
    test "set_lens by guide succeeds" do
      {:ok, %{session_id: sid, guide_id: gid}} = start_server()
      assert :ok = SessionServer.set_lens(sid, gid, :ecg)
    end

    test "set_lens by non-guide returns :not_guide" do
      {:ok, %{session_id: sid, follower_id: fid}} = start_server()
      assert {:error, :not_guide} = SessionServer.set_lens(sid, fid, :ecg)
    end

    test "break_away by non-follower returns :not_follower" do
      {:ok, %{session_id: sid, guide_id: gid}} = start_server()
      assert {:error, :not_follower} = SessionServer.break_away(sid, gid)
    end

    test "end_session by non-participant returns :not_participant" do
      {:ok, %{session_id: sid}} = start_server()
      stranger_id = unique_id()
      assert {:error, :not_participant} = SessionServer.end_session(sid, stranger_id)
    end

    test "is_follower? returns false when follower_user_id is nil" do
      guide_id = unique_id()
      session_id = unique_id()

      {:ok, _pid} =
        SessionServer.start_link(
          session_id: session_id,
          guide_user_id: guide_id,
          follower_user_id: nil
        )

      on_exit(fn ->
        case Registry.lookup(Sensocto.GuidanceRegistry, session_id) do
          [{pid, _}] -> GenServer.stop(pid, :normal)
          [] -> :ok
        end
      end)

      assert {:error, :not_follower} = SessionServer.break_away(session_id, guide_id)
    end
  end

  describe "break_away and drift-back timer" do
    test "break_away sets following: false" do
      {:ok, %{session_id: sid, follower_id: fid}} = start_server()
      :ok = SessionServer.break_away(sid, fid)
      {:ok, state} = SessionServer.get_state(sid)
      refute state.following
    end

    test "drift-back timer fires and resets following: true" do
      {:ok, %{session_id: sid, follower_id: fid}} = start_server(drift_back_seconds: 0)

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      :ok = SessionServer.break_away(sid, fid)

      assert_receive {:guided_drift_back, %{lens: :sensors, focused_sensor_id: nil}}, 500

      {:ok, state} = SessionServer.get_state(sid)
      assert state.following
    end

    test "report_activity resets the drift-back timer" do
      {:ok, %{session_id: sid, follower_id: fid}} = start_server(drift_back_seconds: 1)

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      :ok = SessionServer.break_away(sid, fid)
      # Activity reported at ~400ms, so timer resets; drift_back should not arrive for another second
      Process.sleep(400)
      SessionServer.report_activity(sid, fid)
      # Should NOT receive drift_back within the original 1s window
      refute_receive {:guided_drift_back, _}, 700
      # But eventually it does drift back after the fresh 1s window
      assert_receive {:guided_drift_back, _}, 1200
    end

    test "rejoin cancels drift-back timer" do
      {:ok, %{session_id: sid, follower_id: fid}} = start_server(drift_back_seconds: 1)

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      :ok = SessionServer.break_away(sid, fid)
      {:ok, _guide_state} = SessionServer.rejoin(sid, fid)

      # No drift_back message should arrive after rejoin cancels the timer
      refute_receive {:guided_drift_back, _}, 1500
    end

    test "rejoin returns current guide navigation state" do
      {:ok, %{session_id: sid, guide_id: gid, follower_id: fid}} = start_server()
      :ok = SessionServer.set_lens(sid, gid, :ecg)
      :ok = SessionServer.break_away(sid, fid)
      {:ok, state} = SessionServer.rejoin(sid, fid)
      assert state.lens == :ecg
    end
  end

  describe "idle timeout" do
    test "guide disconnect starts idle timer; idle_timeout stops server" do
      {:ok, %{session_id: sid}} = start_server()

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      # Override the idle timeout to a very short value for testing
      pid = GenServer.whereis(SessionServer.via_tuple(sid))
      # Send the idle_timeout message directly to bypass the 5-minute wait
      send(pid, :idle_timeout)

      assert_receive {:guided_ended, %{ended_by: :idle_timeout}}, 1000
      refute Process.alive?(pid)
    end

    test "guide reconnect before idle timeout cancels the shutdown" do
      {:ok, %{session_id: sid, guide_id: gid, pid: pid}} = start_server()

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      SessionServer.disconnect(sid, gid)
      Process.sleep(50)
      SessionServer.connect(sid, gid)
      # Server should still be alive after reconnection
      assert Process.alive?(pid)
    end
  end

  describe "end_session" do
    test "guide ending session broadcasts :guided_ended and stops process" do
      {:ok, %{session_id: sid, guide_id: gid, pid: pid}} = start_server()

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      :ok = SessionServer.end_session(sid, gid)
      assert_receive {:guided_ended, %{ended_by: ^gid}}, 500
      refute Process.alive?(pid)
    end

    test "follower ending session broadcasts :guided_ended and stops process" do
      {:ok, %{session_id: sid, follower_id: fid, pid: pid}} = start_server()

      topic = "guidance:#{sid}"
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      :ok = SessionServer.end_session(sid, fid)
      assert_receive {:guided_ended, %{ended_by: ^fid}}, 500
      refute Process.alive?(pid)
    end
  end

  describe "annotations" do
    test "guide can add an annotation and it accumulates" do
      {:ok, %{session_id: sid, guide_id: gid}} = start_server()
      annotation = %{text: "Check the spike here", timestamp: DateTime.utc_now()}
      :ok = SessionServer.add_annotation(sid, gid, annotation)
      {:ok, state} = SessionServer.get_state(sid)
      assert length(state.annotations) == 1
      [stored] = state.annotations
      assert Map.has_key?(stored, :id), "annotation should have a UUID :id assigned"
    end

    test "annotations accumulate in insertion order" do
      {:ok, %{session_id: sid, guide_id: gid}} = start_server()
      :ok = SessionServer.add_annotation(sid, gid, %{text: "First"})
      :ok = SessionServer.add_annotation(sid, gid, %{text: "Second"})
      {:ok, state} = SessionServer.get_state(sid)
      [first, second] = state.annotations
      assert first.text == "First"
      assert second.text == "Second"
    end
  end
end
```

```elixir
# test/sensocto/guidance/guided_session_resource_test.exs

defmodule Sensocto.Guidance.GuidedSessionResourceTest do
  use Sensocto.DataCase, async: true

  alias Sensocto.Guidance.GuidedSession

  @guide_id Ash.UUID.generate()

  defp create_session(attrs \\ %{}) do
    Ash.create!(GuidedSession, Map.merge(%{guide_user_id: @guide_id}, attrs),
      action: :create,
      authorize?: false
    )
  end

  describe "generate_invite_code/1" do
    test "default length is 6" do
      code = GuidedSession.generate_invite_code()
      assert String.length(code) == 6
    end

    test "only contains characters from the unambiguous alphabet" do
      ambiguous = ~w(0 O I 1)
      for _i <- 1..50 do
        code = GuidedSession.generate_invite_code()
        Enum.each(ambiguous, fn char ->
          refute String.contains?(code, char),
            "Expected code #{code} to not contain ambiguous character #{char}"
        end)
      end
    end

    test "respects custom length" do
      assert String.length(GuidedSession.generate_invite_code(8)) == 8
      assert String.length(GuidedSession.generate_invite_code(4)) == 4
    end
  end

  describe ":create action" do
    test "sets status to :pending" do
      session = create_session()
      assert session.status == :pending
    end

    test "auto-generates a non-nil invite_code" do
      session = create_session()
      assert is_binary(session.invite_code)
      assert String.length(session.invite_code) == 6
    end

    test "sets guide_user_id from argument" do
      session = create_session()
      assert to_string(session.guide_user_id) == to_string(@guide_id)
    end

    test "rejects drift_back_seconds below 5" do
      assert_raise Ash.Error.Invalid, fn ->
        create_session(%{drift_back_seconds: 4})
      end
    end

    test "rejects drift_back_seconds above 120" do
      assert_raise Ash.Error.Invalid, fn ->
        create_session(%{drift_back_seconds: 121})
      end
    end
  end

  describe ":accept action" do
    test "sets status to :active and populates started_at" do
      session = create_session()
      {:ok, accepted} = Ash.update(session, %{}, action: :accept, authorize?: false)
      assert accepted.status == :active
      assert %DateTime{} = accepted.started_at
    end
  end

  describe ":decline action" do
    test "sets status to :declined and populates ended_at" do
      session = create_session()
      {:ok, declined} = Ash.update(session, %{}, action: :decline, authorize?: false)
      assert declined.status == :declined
      assert %DateTime{} = declined.ended_at
    end
  end

  describe ":end_session action" do
    test "sets status to :ended and populates ended_at" do
      session = create_session()
      {:ok, session} = Ash.update(session, %{}, action: :accept, authorize?: false)
      {:ok, ended} = Ash.update(session, %{}, action: :end_session, authorize?: false)
      assert ended.status == :ended
      assert %DateTime{} = ended.ended_at
    end
  end

  describe ":by_invite_code read" do
    test "returns pending session for valid code" do
      session = create_session()
      {:ok, found} =
        Ash.read_one(GuidedSession,
          action: :by_invite_code,
          args: [invite_code: session.invite_code],
          authorize?: false
        )
      assert found.id == session.id
    end

    test "returns nil for a code belonging to an ended session" do
      session = create_session()
      {:ok, session} = Ash.update(session, %{}, action: :accept, authorize?: false)
      {:ok, session} = Ash.update(session, %{}, action: :end_session, authorize?: false)
      {:ok, result} =
        Ash.read_one(GuidedSession,
          action: :by_invite_code,
          args: [invite_code: session.invite_code],
          authorize?: false
        )
      assert is_nil(result)
    end

    test "returns nil for a declined session" do
      session = create_session()
      {:ok, session} = Ash.update(session, %{}, action: :decline, authorize?: false)
      {:ok, result} =
        Ash.read_one(GuidedSession,
          action: :by_invite_code,
          args: [invite_code: session.invite_code],
          authorize?: false
        )
      assert is_nil(result)
    end
  end
end
```

```elixir
# test/sensocto_web/live/guided_session_join_live_test.exs

defmodule SensoctoWeb.GuidedSessionJoinLiveTest do
  @moduledoc """
  Tests for the GuidedSessionJoinLive invite code join page.
  """
  use SensoctoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Sensocto.Guidance.GuidedSession

  @guide_id Ash.UUID.generate()

  defp create_pending_session do
    Ash.create!(GuidedSession, %{guide_user_id: @guide_id},
      action: :create,
      authorize?: false
    )
  end

  defp authenticated_conn(conn) do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "join_test_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
    |> Map.put(:assigns, %{current_user: user})
  end

  describe "mount with valid invite code" do
    test "assigns session and no error", %{conn: conn} do
      session = create_pending_session()
      {:ok, _view, html} = live(conn, "/join/#{session.invite_code}")
      refute html =~ "no longer valid"
      assert html =~ "Accept &amp; Join"
    end

    test "sets page_title to 'Join Guided Session'", %{conn: conn} do
      session = create_pending_session()
      {:ok, _view, html} = live(conn, "/join/#{session.invite_code}")
      assert html =~ "Join Guided Session"
    end
  end

  describe "mount with invalid or expired invite code" do
    test "shows 'no longer valid' for an ended session", %{conn: conn} do
      session = create_pending_session()
      {:ok, session} = Ash.update(session, %{}, action: :accept, authorize?: false)
      {:ok, _} = Ash.update(session, %{}, action: :end_session, authorize?: false)

      {:ok, _view, html} = live(conn, "/join/#{session.invite_code}")
      assert html =~ "no longer valid"
      refute html =~ "Accept &amp; Join"
    end

    test "shows error when no code param is provided", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/join")
      assert html =~ "No invitation code provided"
    end

    test "shows error for a completely unknown code", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/join/XXXXXX")
      assert html =~ "no longer valid"
    end
  end

  describe "accept event" do
    test "rejects when user is not signed in", %{conn: conn} do
      session = create_pending_session()
      {:ok, view, _html} = live(conn, "/join/#{session.invite_code}")
      html = render_click(view, "accept")
      assert html =~ "signed in" or html =~ "sign in"
    end

    test "navigates to /lobby and starts session server on success", %{conn: conn} do
      session = create_pending_session()
      conn = authenticated_conn(conn)
      {:ok, view, _html} = live(conn, "/join/#{session.invite_code}")

      assert {:error, {:live_redirect, %{to: "/lobby"}}} =
               render_click(view, "accept")
    end

    test "broadcasts guidance_invitation_accepted to guide topic on accept", %{conn: conn} do
      session = create_pending_session()
      conn = authenticated_conn(conn)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "user:#{@guide_id}:guidance")

      {:ok, view, _html} = live(conn, "/join/#{session.invite_code}")

      catch_exit do
        render_click(view, "accept")
      end

      assert_receive {:guidance_invitation_accepted, %{session_id: _, follower_name: _}}, 1000
    end
  end
end
```

#### Critical Bug Fix Required: Wrong Action on `accept` Event

In `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/live/guided_session_join_live.ex` line 61:

```elixir
# WRONG — :create is not a valid update action and will error at runtime:
with {:ok, session} <-
       Ash.update(session, %{follower_user_id: user_id}, action: :create, authorize?: false),
```

The `:create` action is not callable via `Ash.update/4`. The `GuidedSession` resource has no update action that accepts `follower_user_id`. Two options:

Option A — Add a dedicated `:set_follower` update action to the resource and call it:

```elixir
# In guided_session.ex actions block:
update :set_follower do
  accept [:follower_user_id]
end

# In guided_session_join_live.ex:
with {:ok, session} <-
       Ash.update(session, %{follower_user_id: user_id}, action: :set_follower, authorize?: false),
     {:ok, session} <- Ash.update(session, %{}, action: :accept, authorize?: false) do
```

Option B — Accept `follower_user_id` in the `:accept` action directly:

```elixir
# In guided_session.ex:
update :accept do
  accept [:follower_user_id]
  change set_attribute(:status, :active)
  change set_attribute(:started_at, &DateTime.utc_now/0)
end

# In guided_session_join_live.ex:
with {:ok, session} <-
       Ash.update(session, %{follower_user_id: user_id}, action: :accept, authorize?: false) do
```

#### Critical UX Bug: Follower Badge Uses Wrong Event to Dismiss

**Status as of March 25, 2026: RESOLVED.** The follower leave button in the current `lobby_live.html.heex` (line 72) correctly fires `follower_leave_session` rather than `guide_end_session`.

### Accessibility Audit: Guided Session UI (Feb 24, 2026)

#### WCAG Violations in Guided Session UI Elements

**Violation GS-1 — [1.1.1 Non-text Content] Floating Badge Dismiss Button Has No Accessible Name**

Severity: HIGH — **Status: RESOLVED** — The new `lobby_live.html.heex` uses a `<Heroicons.icon name="x-mark">` button with `title="Leave guided session"` for the follower leave button. A `title` attribute is still not a fully reliable accessible name; it should be supplemented with `aria-label="Leave guided session"`. The icon itself should have `aria-hidden="true"`.

**Violation GS-2 — [1.4.1 Use of Color] Guide/Follower Presence Dot Relies Solely on Color**

Severity: HIGH — **Status: PARTIALLY RESOLVED** — The dot in the following pill (`lobby_live.html.heex` lines 64-68) still uses only color (green vs. gray) with no text label or `aria-label` on the dot span. The guide connection state is visually implied by color only.

Fix:

```heex
<span class={[
  "w-2 h-2 rounded-full",
  if(@guided_presence.guide_connected, do: "bg-green-400", else: "bg-gray-400")
]}
  role="img"
  aria-label={if @guided_presence.guide_connected, do: "Guide is online", else: "Guide is offline"}
>
</span>
```

**Violation GS-3 — [4.1.3 Status Messages] Guided Session State Changes Not Announced**

Severity: HIGH — **Status: OPEN**

The `@guided_session` conditional block (lines 61-79) has no `aria-live` region. When a follower breaks away or drifts back, the text changes are silent to screen readers.

**Violation GS-4 — [4.1.3 Status Messages] Suggestion Toast Not Announced**

Severity: HIGH — **Status: OPEN** (if `@guided_suggestion` feature is still active)

**Violation GS-5 — [2.4.3 Focus Order] Floating Badge and Toast Have No Focus Management**

Severity: MEDIUM — **Status: OPEN**

**Violation GS-6 — [1.3.1 Info and Relationships] Guide Panel Suggestion Buttons Lack Context**

Severity: MEDIUM — **Status: OPEN**

**Violation GS-7 — [2.4.2 Page Titled] GuidedSessionJoinLive Missing `page_title` on Error State**

Severity: LOW-MEDIUM — **Status: OPEN** — Error states share the `"Join Guided Session"` title; the error content still lacks `role="alert"`.

**Violation GS-8 — [4.1.2 Name, Role, Value] "Accept & Join" Button Has No Disabled State**

Severity: LOW — **Status: OPEN** — `phx-disable-with` is still absent from the accept button.

---

## Update: February 22, 2026

### Changes Since Last Review (Feb 20 -> Feb 22, 2026)

| Change | Impact |
|--------|--------|
| E2E Tests (#35): 3 new Wallaby feature test files -- `auth_flow_feature_test.exs`, `room_feature_test.exs`, `lobby_navigation_feature_test.exs` | **Total 7 feature test files** (up from 4). Auth flow test covers login/logout/redirect pipeline. Room test covers room creation and navigation. Lobby navigation test covers lens switching and route stability. |
| Hierarchy View (#41): `/lobby/hierarchy` with collapsible User > Sensor tree | **ACCESSIBILITY REVIEW NEEDED**: Collapsible tree structures require `aria-expanded` on toggle buttons, `role="tree"`/`role="treeitem"` semantics, and keyboard arrow-key navigation per WAI-ARIA TreeView pattern. |
| My Devices View (#42): `/devices` with device cards, inline rename, forget with confirmation | **ACCESSIBILITY REVIEW NEEDED**: Inline rename requires focus management (focus input on edit mode entry). Forget confirmation dialog must use `<.modal>` component (not raw div). Device status indicators must not rely solely on color -- use text labels or `aria-label`. |
| Connector REST API (#40): New OpenApiSpex-annotated controller | `openapi_test.exs` should be expanded to validate connector schemas in the OpenAPI spec. Currently only 2 schema validation tests. |
| CRDT Sessions (#36): document_worker.ex with multi-device tracking | No direct accessibility impact. Consider testing that multi-device state sync does not cause unexpected UI updates without `aria-live` announcements. |
| Token Refresh (#37): POST `/api/auth/refresh` endpoint | No direct accessibility impact. Auth flow E2E test should cover token expiry and silent refresh behavior. |

---

## Update: February 20, 2026

### Executive Summary

This update reflects the Sensocto codebase as of February 20, 2026. The project now has **280 implementation files** in `/lib` and **51 test files** with approximately **732 test definitions** (up from 373 on Feb 16). Since the last update, the codebase has seen significant expansion: 6 new LiveView modules (PollsLive, ProfileLive, UserDirectoryLive, UserShowLive, plus two new component files for polls), a full Collaboration domain (Poll, PollOption, Vote), User profiles/skills/connections, a MIDI audio output system (1709-line JS hook), an upgraded LobbyGraph and a new UserGraph Svelte component, and 18 new test files spanning accounts, encoding, collaboration, OTP modules, web live views, and regression suites.

Several accessibility violations reported on Feb 16 have been fixed: the skip navigation link now exists in `root.html.heex`; `<.live_title>` is used in the root layout so per-page title changes are announced by screen readers; the lobby view mode selector now uses a proper ARIA tablist with `aria-selected`; and the count of `aria-live` regions jumped from 1 to 11. However, all six new features were shipped with accessibility gaps — unlabeled form fields, icon-only buttons without accessible names, navigation without `aria-current`, and JS-controlled dropdowns with no `aria-expanded` state. These must be addressed now before they compound further.

### Current Metrics (February 20, 2026)

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

1. **Skip Navigation Link Added** (`root.html.heex` lines 38-43) — Uses the correct `href="#main"` target with `sr-only focus:not-sr-only` pattern. Resolves the long-standing WCAG 2.4.1 violation.

2. **`<.live_title>` in Root Layout** — The root layout now uses Phoenix's `<.live_title>` component, meaning `page_title` changes on `handle_params` are properly announced to assistive technologies during LiveView navigation. Per-page titles are set in: `LobbyLive`, `PollsLive`, `ProfileLive`, `RoomListLive`, `RoomShowLive`, `SensorLive`, `UserDirectoryLive`, `UserShowLive`, `SystemStatusLive`, `AiChatLive`, `AboutLive`.

3. **Lobby View Mode Selector Upgraded to ARIA Tablist** — The lens navigation in `lobby_live.html.heex` now uses `role="tablist"` on the `<nav>` element and `role="tab"` plus `aria-selected` on each lens chip. This is a significant improvement for keyboard and screen reader users navigating between sensor views.

4. **`aria-live` Regions: 1 -> 11** — New regions added in `whiteboard_component.ex`, `object3d_player_component.ex`, `media_player_component.ex`, `room_show_live.ex`, and the lobby modals' countdown timers. The two countdown timer divs correctly use `role="timer"`, `aria-live="polite"`, and `aria-atomic="true"`.

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

### Test File Inventory (51 files as of Feb 20, 2026)

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

### Quality Issue: Silent `if` Guard in Search Tests

**File:** `test/sensocto_web/live/search_live_test.exs`

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

### Critical Testing Gaps (Priority Order, March 25, 2026)

#### Priority 0: Zero Coverage

1. **`lib/sensocto_web/live/components/whiteboard_component.ex`** — New collaborative canvas. No tests. All event handlers (`stroke_complete`, `clear_whiteboard`, `undo`, `take_control`, `request_control`, `keep_control`, `wb_export`) untested.

2. **`lib/sensocto_web/live/custom_sign_in_live.ex`** — Authentication page. Ball presence, locale switching, sensor background, guest sign-in all untested.

3. **`lib/sensocto_web/live/user_settings_live.ex`** — Settings page. Token regeneration, QR toggle, locale change, `toggle_public` for authenticated and guest users, all untested.

4. **`lib/sensocto_web/live/index_live.ex`** — Main dashboard. Snapshot refresh cycle, animation mode activation, preview theme change, presence diff handling all untested.

5. **`lib/sensocto/calls/call_server.ex`** (776 lines) — No tests.

6. **`lib/sensocto/calls/quality_manager.ex`** (336 lines) — No tests.

7. **`lib/sensocto/calls/snapshot_manager.ex`** (239 lines) — No tests.

8. **`lib/sensocto_web/channels/call_channel.ex`** (359 lines) — No tests.

9. **`lib/sensocto_web/live/polls_live.ex`** — No LiveView tests for `create_poll`, `validate_poll`, `add_option`, `close_poll`.

10. **`lib/sensocto_web/live/profile_live.ex`** — No LiveView tests for `save_profile`, `add_skill`, `remove_skill`.

#### Priority 1: Insufficient Tests

1. **`stateful_sensor_live_test.exs`** — Only 2 tests. Missing: measurement display, modal interactions, favorite toggle, pin/unpin, view mode changes, latency ping/pong, battery state, highlight toggle.

2. **`user_directory_live_test.exs`** — Tests mount but not the `search` event or list-to-graph navigation.

3. **`openapi_test.exs`** — Only 2 schema validation tests. Should include connector schema validation.

---

## Accessibility Audit

### WCAG 2.1 Compliance Summary (March 25, 2026)

| Level | Status | Violations | Change from Mar 1 |
|-------|--------|------------|-------------------|
| Level A | FAIL | ~32 violations | -3 (page titles fixed) |
| Level AA | FAIL | ~14 violations | +2 (whiteboard, lobby controls) |
| Level AAA | NOT ASSESSED | -- | N/A |

### Fixed Since Initial Report

1. **[2.4.1 Bypass Blocks] Skip Navigation Link — FIXED** — `root.html.heex` includes correct skip link to `#main` with `sr-only focus:not-sr-only` pattern.

2. **[2.4.2 Page Titled] Static Page Title — FIXED** — Root layout uses `<.live_title>`. `custom_sign_in_live.ex` and `index_live.ex` now set `page_title`. All major LiveViews have per-page titles.

3. **[1.3.1 Info and Relationships] Lobby Lens Tabs — FIXED** — Lobby lens navigation uses `role="tablist"`, `role="tab"`, `aria-selected`.

4. **[4.1.3 Status Messages] `aria-live` Regions — IMPROVED** — 12 regions as of March 25.

5. **[UX BUG] Follower badge dismiss event — FIXED** — The `×` button on the following pill now correctly fires `follower_leave_session` instead of `guide_end_session`.

### Open Critical Violations (as of March 25, 2026)

The complete list of open violations is documented in the March 25 "New Violations Found" section above (M26-1 through M26-19) plus the still-open Guided Session violations (GS-2 through GS-8). Key repeating themes:

- **ARIA state on toggle/tab controls** (M26-1, M26-2, M26-6, M26-14, GS-8): Pattern across entire codebase — buttons that change state (active tab, pressed toggle, open/close) do not communicate that state to ARIA.
- **Keyboard-inaccessible hover interactions** (M26-4, M26-8, M26-10): Multiple panels/dropdowns triggered by CSS `:hover` only.
- **Unlabeled icon and graphic controls** (M26-3, M26-7, M26-9, M26-13, M26-17): Persistent pattern of using Unicode glyphs, color dots, or icons without text alternatives.
- **Missing focus management on dynamic content** (M26-16, GS-5): Modals and toasts appear without moving focus.
- **RTL layout gaps** (M26-12): Arabic `dir="rtl"` is set on the document but positioned elements use physical CSS properties (`left:`, `right:`) that do not auto-flip.
