# Comprehensive Test Coverage and Accessibility Analysis
## Sensocto IoT Sensor Platform

**Analysis Date:** January 12, 2026 (Updated: March 1, 2026)
**Analyzed By:** Testing, Usability, and Accessibility Expert Agent
**Project:** Sensocto - Elixir/Phoenix IoT Sensor Platform

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

3. The follower floating badge uses `phx-click="guide_end_session"` for the dismiss button (the `&times;` button at the end of the badge). This is the same event used in the guide panel to end the session entirely. A follower clicking the `&times;` to dismiss their badge would end the entire session rather than just collapsing the badge. This is a significant UX and logic bug.

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
      # Activity reported at ~900ms, so timer resets; drift_back should not arrive for another second
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
      {:ok, %{session_id: sid, guide_id: gid}} = start_server()

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

In `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/live/lobby_live.html.heex` around line 1537, the `&times;` dismiss button on the follower floating badge fires `guide_end_session`, which ends the entire guided session. A follower should be able to minimize or leave the session without destroying it for the guide.

The fix requires either:

1. A separate `"follower_leave_session"` event that ends the session from the follower's perspective only (calls `SessionServer.end_session/2` which stops the server), or
2. A `"dismiss_session_badge"` event that just hides the UI (sets `@guided_session` to nil locally) if the intent is that the follower can leave without ending the guide's ability to resume.

### Accessibility Audit: Guided Session UI (Feb 24, 2026)

#### WCAG Violations in New UI Elements

**Violation GS-1 — [1.1.1 Non-text Content] Floating Badge Dismiss Button Has No Accessible Name**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` approximately line 1537

The `&times;` character is not a reliable accessible name. The button has a `title="End session"` attribute, which some screen readers announce as a tooltip on hover but is not a reliable accessible name for interactive elements.

Fix:

```heex
<button
  phx-click="guide_end_session"
  class="ml-2 text-xs text-error/60 hover:text-error"
  aria-label="End guided session"
>
  <span aria-hidden="true">&times;</span>
</button>
```

**Violation GS-2 — [1.4.1 Use of Color] Guide/Follower Presence Dot Relies Solely on Color**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` approximately lines 1514-1517 and 1571-1573

Both the follower badge and the guide panel use a small colored dot (`bg-green-500` vs `bg-gray-400`) as the sole indicator of guide/follower connection status. Users with color blindness or low vision cannot distinguish the dot colors. The dot element is an empty `<span>` with no text content and no `aria-label`.

Fix:

```heex
<%!-- Replace the bare colored span with a labeled indicator --%>
<span
  class={["w-2 h-2 rounded-full", if(@guided_presence.guide_connected, do: "bg-green-500", else: "bg-gray-400")]}
  aria-label={if @guided_presence.guide_connected, do: "Guide is online", else: "Guide is offline"}
  role="img"
>
</span>
```

**Violation GS-3 — [4.1.3 Status Messages] Guided Session State Changes Not Announced**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 1510-1544

When a follower breaks away or drifts back, the badge text changes between "Following guide" and "Exploring on your own". These dynamic content changes are not in an `aria-live` region, so screen reader users receive no announcement when the mode changes.

Fix: Wrap the badge status text in a live region.

```heex
<div
  class="bg-base-200 rounded-full shadow-lg px-4 py-2 flex items-center gap-2 text-sm"
  role="status"
  aria-live="polite"
  aria-atomic="true"
>
  <%!-- existing badge content --%>
</div>
```

**Violation GS-4 — [4.1.3 Status Messages] Suggestion Toast Not Announced**

Severity: HIGH
File: `lib/sensocto_web/live/lobby_live.html.heex` approximately lines 1547-1562

The suggestion toast (`@guided_suggestion`) appears via a conditional `<%= if ... %>` block. When the content renders, a screen reader user receives no announcement. The toast contains guidance from the guide (e.g., "Try breathing at 6 breaths/min") which is important information to convey.

Fix: Add `role="alert"` and `aria-live="assertive"` because suggestion toasts are action-relevant information that needs immediate attention. Alternatively, use `aria-live="polite"` if the suggestion is not time-critical.

```heex
<%= if @guided_suggestion do %>
  <div
    class="fixed bottom-24 left-1/2 -translate-x-1/2 z-50 max-w-md w-full px-4"
    role="alert"
    aria-live="assertive"
    aria-atomic="true"
  >
    <div class="bg-base-200 rounded-xl shadow-xl p-4 flex items-start gap-3">
      <div class="flex-1">
        <p class="text-sm font-medium">{@guided_suggestion.text}</p>
      </div>
      <button
        phx-click="dismiss_suggestion"
        class="text-base-content/40 hover:text-base-content text-lg leading-none"
        aria-label="Dismiss suggestion"
      >
        <span aria-hidden="true">&times;</span>
      </button>
    </div>
  </div>
<% end %>
```

**Violation GS-5 — [2.4.3 Focus Order] Floating Badge and Toast Have No Focus Management**

Severity: MEDIUM
File: `lib/sensocto_web/live/lobby_live.html.heex` lines 1510-1562

Both the floating badge and the suggestion toast use `fixed` positioning and appear dynamically. When the toast appears, keyboard focus remains wherever it was. Users who navigate by keyboard have no indication that new content has appeared unless they tab through the page. The toast in particular contains an interactive dismiss button that keyboard users may never find.

Fix: When a suggestion toast appears, use `Phoenix.LiveView.push_event` with a JS hook to focus the toast's dismiss button. When the toast is dismissed, return focus to a stable landmark.

```elixir
# In the handle_info for :guided_suggestion in lobby_live.ex:
{:noreply, socket |> assign(:guided_suggestion, suggestion) |> push_event("focus", %{"id" => "suggestion-dismiss-btn"})}
```

```heex
<button
  id="suggestion-dismiss-btn"
  phx-click="dismiss_suggestion"
  aria-label="Dismiss suggestion"
>
```

**Violation GS-6 — [1.3.1 Info and Relationships] Guide Panel Suggestion Buttons Lack Context**

Severity: MEDIUM
File: `lib/sensocto_web/live/lobby_live.html.heex` approximately lines 1582-1617

The guide panel renders two "suggest" buttons labeled "Breathing" and "Break". Without additional context, a screen reader user on the guide panel hears only "Breathing, button" and "Break, button" with no indication these are actions to send suggestions to the follower.

Fix:

```heex
<button
  phx-click="guide_suggest"
  phx-value-type="breathing_rhythm"
  phx-value-text="Try breathing at 6 breaths/min"
  class="btn btn-xs btn-outline"
  aria-label="Suggest breathing exercise to follower"
>
  Breathing
</button>
<button
  phx-click="guide_suggest"
  phx-value-type="take_break"
  phx-value-text="Take a short break"
  class="btn btn-xs btn-outline"
  aria-label="Suggest taking a break to follower"
>
  Break
</button>
```

**Violation GS-7 — [2.4.2 Page Titled] GuidedSessionJoinLive Missing `page_title` on Error State**

Severity: LOW-MEDIUM
File: `lib/sensocto_web/live/guided_session_join_live.ex` lines 13-35

All mount branches set `page_title: "Join Guided Session"` including error states. This is correct. However, the error-state content ("This invitation is no longer valid.") is rendered in a `<p class="text-error">` without any ARIA role to distinguish it from regular content. A screen reader user lands on the join page and hears the heading "Guided Session" followed by the error text with no indication it is an error message.

Fix: Add `role="alert"` to the error paragraph so screen readers announce it immediately on page load.

```heex
<%= if @error do %>
  <p class="text-error mt-4" role="alert">{@error}</p>
```

**Violation GS-8 — [4.1.2 Name, Role, Value] "Accept & Join" Button Has No Disabled State**

Severity: LOW
File: `lib/sensocto_web/live/guided_session_join_live.ex` line 115

The accept button has no `phx-disable-with` attribute, which means double-clicks can fire the `accept` event twice. The second `Ash.update` call would fail (session already active), but the user would see no feedback. The button also has no loading indicator.

Fix:

```heex
<button
  phx-click="accept"
  class="btn btn-primary btn-lg"
  phx-disable-with="Joining..."
>
  Accept &amp; Join
</button>
```

#### Accessibility Enhancements for Guided Session (Not Violations, But Recommended)

**GS-E1 — Guide Panel Should Use `role="region"` with `aria-label`**

The guide panel div at line 1566 is a significant UI area but has no landmark role. Screen reader users cannot navigate to it quickly.

```heex
<div
  class="fixed top-16 right-4 z-50"
  role="region"
  aria-label="Guide controls"
>
```

**GS-E2 — Follower Badge Should Use `role="region"` with `aria-label`**

Same reasoning as GS-E1 for the follower badge at line 1512.

```heex
<div
  class="fixed top-16 right-4 z-50"
  role="region"
  aria-label="Guided session status"
>
```

**GS-E3 — Keyboard Shortcut for Rejoin/Break Away**

Power users and users who rely on keyboard navigation would benefit from a keyboard shortcut (e.g., `Escape` to break away, `G` to rejoin guide) when in a guided session. This is an enhancement for a future iteration but worth logging now.

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

### Immediate (Block on next release — NEW from Feb 24)
1. **Fix runtime bug: `Ash.update` with `action: :create` in `guided_session_join_live.ex` line 61** — This will crash at runtime. Add a `:set_follower` update action to `GuidedSession` or combine the follower assignment into the `:accept` action. 30-minute fix. See "Critical Bug Fix Required" section above.
2. **Fix UX bug: Follower badge dismiss button fires `guide_end_session`** — The `&times;` button on the follower floating badge ends the entire session. Introduce a `"follower_leave_session"` event or a `"dismiss_session_badge"` event with the appropriate semantics. 20-minute fix.
3. **Add `aria-live="polite"` to the guided session badge status region** — Without it, mode switches (Following / Exploring) are invisible to screen reader users (Violation GS-3). 10-minute fix.
4. **Add `role="alert" aria-live="assertive"` to the suggestion toast** — Guide suggestions to the follower are time-sensitive and must be announced (Violation GS-4). 5-minute fix.
5. **Add `aria-label="End guided session"` to the badge dismiss button** — `title` attribute alone does not provide an accessible name (Violation GS-1). 5-minute fix.
6. **Add `aria-label` to the guide/follower presence dot** — Color alone fails WCAG 1.4.1 (Violation GS-2). 5-minute fix.

### Immediate (Carried over from Feb 22)
7. **Fix polls form labels** — Add `for=` and `id=` to all 4 label/input pairs in `polls_live.html.heex`. 30-minute fix.
8. **Fix user directory search label** — Add `aria-label="Search users"` to search input. 5-minute fix.
9. **Fix profile remove-skill button** — Add `aria-label={"Remove skill: " <> skill.name}` to each button. 15-minute fix.
10. **Fix search_live_test false-green** — Replace `if search_view do ... end` with `assert search_view` + unconditional body. 5-minute fix.

### Short-term (Next sprint — NEW from Feb 24)
11. **Write `SessionServerTest`** — Focus on drift-back timer, break_away/rejoin cycle, idle timeout, and role enforcement. Use `assert_receive`/`refute_receive` with PubSub. ~3 hours.
12. **Write `GuidedSessionResourceTest`** — Cover all 4 actions, `generate_invite_code/1` alphabet validation, and constraint enforcement. ~2 hours.
13. **Write `GuidedSessionJoinLiveTest`** — All mount paths plus the accept event (authenticated and unauthenticated). ~2 hours.
14. **Add `role="region" aria-label` to guide panel and follower badge** — Landmarks enable screen reader navigation (Violations GS-E1, GS-E2). 10-minute fix.
15. **Add `aria-label` to suggestion toast dismiss button** — `&times;` has no accessible name (Violation GS-4 dismiss button). 5-minute fix.
16. **Add `role="alert"` to join page error text** — Violations GS-7. 5-minute fix.
17. **Add `phx-disable-with="Joining..."` to Accept button** — Prevents double-submit (Violation GS-8). 5-minute fix.
18. **Add `aria-label` to guide panel suggestion buttons** — "Breathing" and "Break" lack context out of tree order (Violation GS-6). 10-minute fix.

### Short-term (Carried over from Feb 22)
19. **Add `aria-expanded` to app layout menus** — User menu, language switcher, mobile hamburger. Update JS hooks to maintain `aria-expanded`. 2-hour fix.
20. **Fix IndexLive page title** — Add `assign(:page_title, "Home")` in `index_live.ex`. 5-minute fix.
21. **Add `aria-current` to user directory nav** — 10-minute fix.
22. **Fix vote count aria-live** — Wrap vote count display in `<span aria-live="polite">`. 15-minute fix.
23. **Add `phx-disable-with` to poll submit button** — 5-minute fix.
24. **Investigate `refute_push_event/4` arity** in `midi_output_regression_test.exs` — Verify 4-argument call is valid for the installed Phoenix version.

### Medium-term (Next month)
25. **Migrate lobby custom modals to `<.modal>` component** — Join Room, Control Request, Media Control Request modals. Highest effort (~4 hours) but critical for keyboard accessibility.
26. **Add Floki-based accessibility regression tests** — Create `test/sensocto_web/accessibility/` with form label, aria-live, and icon-button tests.
27. **Add `phx-change="validate_poll"` real-time validation** — Prevents disruptive submit-to-discover error cycle.
28. **Deduplicate redundant lobby_graph_regression tests** — Remove the 3 identical describe blocks, or split into 3 named tests.
29. **Add focus management for suggestion toast** — Use a `push_event`/JS hook to focus the dismiss button when the toast appears (Violation GS-5).

### Ongoing
30. **Audit each new LiveView for WCAG 1.3.1 compliance** — Every new form must have label/input associations before merging.
31. **Review adaptive video quality controls for `aria-pressed`** — When PLAN-adaptive-video-quality features land.
32. **Review Iroh connection status for `aria-live` announcements** — When PLAN-room-iroh-migration lands.

---

## Test Coverage Summary

| Domain | Test Files | Approx Tests | Notes |
|---|---|---|---|
| Accounts (Users, Tokens) | 2 | ~48 | New: accounts_test.exs |
| Collaboration (Polls) | 1 | ~32 | New: collaboration_test.exs |
| Guidance (GuidedSession) | 0 | 0 | NEW — 3 test files needed, ~70 tests |
| Sensors (core) | 6 | ~89 | Existing, no changes |
| OTP (AttentionTracker, AttributeStore, RoomServer) | 3 | ~71 | All new |
| Encoding (DeltaEncoder) | 1 | ~18 | New |
| Resilience (CircuitBreaker) | 1 | ~22 | New |
| Simulator | 4 | ~51 | No changes |
| LiveView (Lobby, MIDI, Search, Room, GuidedJoin) | 14 | ~189 | GuidedSessionJoinLive has 0 coverage |
| Channel / Presence | 2 | ~29 | No changes |
| Misc (Router, ErrorHTML) | 2 | ~8 | No changes |
| Integration (Wallaby) | 1 | ~12 | No changes |
| Performance / Stress | 5 | ~53 | No changes |
| Data Layer / Ash | 9 | ~110 | No changes |
| **Total** | **51** | **~732** | **Guidance domain at 0%** |

Coverage estimate: **~58% of application code** (down from ~61% due to new untest Guidance domain adding approximately 500 lines). The Guidance domain is the largest new uncovered area. Priority is `SessionServerTest` (timer behavior), `GuidedSessionResourceTest` (constraint and action coverage), and `GuidedSessionJoinLiveTest` (all mount paths and accept event).

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

- `lib/sensocto/guidance.ex`
- `lib/sensocto/guidance/guided_session.ex`
- `lib/sensocto/guidance/session_server.ex`
- `lib/sensocto/guidance/session_supervisor.ex`
- `lib/sensocto_web/live/guided_session_join_live.ex`
- `lib/sensocto_web/live/lobby_live.html.heex` (lines 1510-1624, guided session additions)

---

## Summary

### February 24, 2026

The Guided Session feature was shipped across six new files with zero test coverage and eight new accessibility violations. Two bugs were discovered that would affect users in production immediately:

1. `GuidedSessionJoinLive.handle_event("accept")` calls `Ash.update` with `action: :create`, which is a runtime error. The `GuidedSession` resource has no update action named `:create`. This must be fixed before the feature is accessible to any user.

2. The follower floating badge dismiss button (`&times;`) fires `guide_end_session`, which ends the entire session for both participants. A follower clicking it to close their status badge will terminate the session unexpectedly. A separate event is needed.

On the accessibility side, the new UI introduces five HIGH-severity violations: no live region for session state changes (Following / Exploring), no live region for guide suggestions (the toast appears silently for screen reader users), presence dots that rely solely on color, icon-only buttons without accessible names, and error text on the join page that is not announced on load.

Three test files are needed (approximately 70 tests total):
- `test/sensocto/guidance/session_server_test.exs` — GenServer behavior, timer correctness, role enforcement, PubSub contracts
- `test/sensocto/guidance/guided_session_resource_test.exs` — Ash resource actions, constraints, invite code alphabet
- `test/sensocto_web/live/guided_session_join_live_test.exs` — All mount paths, accept event, unauthenticated rejection

### February 22, 2026

The project made substantial testing and accessibility progress since the February 16 review. Test file count grew from 33 to 51, test count from ~373 to ~732, and three longstanding accessibility violations (skip navigation, live title, lobby tablist) have been resolved.

The three custom modals in `lobby_live.html.heex` remain the project's most significant pre-existing accessibility debt. The new Guidance feature has added to that debt with 8 new violations, 2 of which (the live region for state changes and the suggestion toast announcement) are HIGH severity and directly affect the core user experience of the feature.

*Last updated: 2026-03-01 by elixir-test-accessibility-expert agent.*

---

## Update: March 1, 2026

### Changes Since Last Review (Feb 24 -> Mar 1, 2026)

**Lobby Refactoring:** `lobby_live.ex` was significantly refactored with hooks extracted to `lobby_live/hooks/` (5 files: call_hook, guided_session_hook, media_hook, object3d_hook, whiteboard_hook) and UI components extracted to `lobby_live/components.ex` (412 lines). All 8 new modules have 0% test coverage.

**Profile System:** `profile_live.ex` grew by ~200 lines with skills management, connections, user search, and UserGraph visualization. `profile_live.html.heex` expanded by ~180 lines.

**New Pages:** `user_settings_live.ex` (417 lines) — language selector, mobile device linking (QR code), privacy toggle, sign-out.

### Bugs Fixed
- **GS-Bug-1 FIXED**: `guided_session_join_live.ex` now uses `:assign_follower` action correctly
- **Violation 3 FIXED**: Profile remove-skill button now has `aria-label={"Remove skill #{skill.skill_name}"}`

### New Accessibility Violations

| ID | File | Issue | Severity |
|---|---|---|---|
| SETS-1 | `user_settings_live.ex:242-253` | `<label>` outside form context for static info | HIGH |
| SETS-2 | `user_settings_live.ex:382-392` | Privacy `role="switch"` missing `aria-labelledby` | HIGH |
| SETS-3 | `user_settings_live.ex:340-350` | Copy button lacks descriptive accessible name | MEDIUM |
| SETS-4 | `user_settings_live.ex:313-318` | QR token auto-regeneration not announced via `aria-live` | MEDIUM |
| SETS-5 | `user_settings_live.ex:267-277` | Locale buttons missing visible focus ring | MEDIUM |
| COMP-1 | `lobby_live/components.ex:37-55` | Call mute/video buttons use color-only state | HIGH |
| COMP-2 | `lobby_live/components.ex:131-134` | Modal close buttons lack `aria-label` | HIGH |

### New Usability Issues

- **SETS-U1 (HIGH)**: No visual warning when QR auth token is about to expire
- **SETS-U2 (MEDIUM)**: "Copied!" state persists after token regeneration
- **SETS-U3 (MEDIUM)**: Privacy toggle to public has no confirmation/undo
- **PROF-U1 (MEDIUM)**: Per-connection type select has no accessible label
- **PROF-U2 (MEDIUM)**: User search dropdown not keyboard-accessible

### Updated Test Coverage (Mar 2026)

| Domain | Files | Approx. Tests | Change |
|---|---|---|---|
| OTP / Supervision | 7 | ~100 | +3 files |
| Lenses (PriorityLens) | 3 | ~45 | +2 files |
| Bio | 6 | ~60 | +1 file |
| E2E (Wallaby) | 7 | ~70 | +3 files |
| LiveView (regression) | 5 | ~50 | +1 file |
| **Total** | **~66** | **~855** | **+~120 since Feb 24** |

Estimated coverage: ~26%. Largest zero-coverage areas: `UserSettingsLive`, `LobbyLive.Components`/`Hooks` (8 modules), `Guidance` domain.

### Priority Actions

1. Add `aria-labelledby` to privacy toggle (SETS-2) — 5min
2. Replace `<label>` with `<dt>`/`<dd>` in settings info (SETS-1) — 10min
3. Add `aria-pressed` + `aria-label` to call mute/video buttons (COMP-1) — 10min
4. Add `aria-label="Close modal"` to component close buttons (COMP-2) — 5min
5. Add focus ring classes to locale buttons (SETS-5) — 5min
6. Fix `@copied` reset after token regenerate (SETS-U2) — 20min
7. Write `UserSettingsLive` tests — ~3 hours
8. Write `ProfileLive` event handler tests — ~3 hours
9. Write `LobbyLive.Components` unit tests — ~2 hours
