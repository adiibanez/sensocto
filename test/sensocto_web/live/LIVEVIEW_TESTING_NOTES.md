# LiveView Testing Notes

## SearchLive Component ID Issue

### Problem Description

The `SensoctoWeb.SearchLive` component causes LiveView tests to fail with duplicate component ID errors when testing LiveViews that use the standard `app` layout.

### Root Cause

1. `SearchLive` is rendered in `lib/sensocto_web/components/layouts/app.html.heex` with:
   ```heex
   {live_render(@socket, SensoctoWeb.SearchLive, id: "global-search")}
   ```

2. The component itself also has `id="global-search"` in its template:
   ```heex
   <div id="global-search" phx-hook="GlobalSearch">
   ```

3. When testing LiveViews with `Phoenix.LiveViewTest.live/2`, the layout is rendered along with the main LiveView, causing the "global-search" ID to appear twice.

### Affected Tests

- `test/sensocto_web/live/stateful_sensor_live_test.exs` - Currently SKIPPED

### Workarounds

#### Option 1: Use `live_isolated/3` with `layout: false`
```elixir
{:ok, view, html} = live_isolated(conn, MyLive, session: %{...})
```
This bypasses the layout entirely but loses layout functionality.

#### Option 2: Create Test-Specific Layouts
Create a `test_app.html.heex` layout that excludes SearchLive for testing purposes.

#### Option 3: Make SearchLive ID Unique Per Instance (RECOMMENDED)
Modify the `live_render` call to use a unique ID:
```heex
{live_render(@socket, SensoctoWeb.SearchLive, id: "global-search-#{@socket.id}")}
```
And update the SearchLive template accordingly.

#### Option 4: Conditional Rendering
Add a socket assign to control SearchLive rendering:
```heex
<%= if @render_search != false do %>
  {live_render(@socket, SensoctoWeb.SearchLive, id: "global-search")}
<% end %>
```

### Recommended Fix

The cleanest solution is **Option 3** - making the SearchLive ID dynamically generated based on the parent socket. This ensures uniqueness across all contexts while maintaining functionality.

Steps to implement:
1. In `app.html.heex`, change the `live_render` call to use a unique ID generator
2. Update `SearchLive` to accept an ID as a session parameter
3. Use that ID consistently throughout the component

### Impact Assessment

Until fixed, the following test patterns are blocked:
- Integration tests using `live/2` with authenticated routes
- Tests verifying layout + LiveView interactions
- Full-page rendering tests

Tests using `live_isolated/3` will continue to work but cannot test layout interactions.

---

*Last Updated: 2026-01-17*
*Author: livebook-tester agent*
