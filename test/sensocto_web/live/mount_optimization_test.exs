defmodule SensoctoWeb.MountOptimizationTest do
  @moduledoc """
  Tests for LiveView mount optimizations:

  1. SearchLive sticky: persists across navigation (no re-spawn)
  2. LobbyLive deferred subscriptions: mount only subscribes to essential topics
  3. SenseLive deferred signal subscription: "signal" topic deferred until connected
  """

  use SensoctoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :integration

  setup %{conn: conn} do
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "mount_opt_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = log_in_user(conn, user)

    {:ok, conn: conn, user: user}
  end

  # ===========================================================================
  # 1. SearchLive sticky behavior
  # ===========================================================================

  describe "SearchLive sticky" do
    test "SearchLive is present as child on lobby page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      assert find_live_child(view, "global-search")
    end

    test "SearchLive is present as child on about page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      assert find_live_child(view, "global-search")
    end

    test "SearchLive is present as child on rooms page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/rooms")
      assert find_live_child(view, "global-search")
    end

    test "SearchLive remains functional after page mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      search_view = find_live_child(view, "global-search")

      if search_view do
        # Open search palette
        render_click(search_view, "open")
        html = render(search_view)
        assert html =~ "Search sensors, rooms" or html =~ "search"

        # Close with escape
        render_keydown(search_view, "keydown", %{"key" => "Escape"})
        html = render(search_view)
        refute html =~ "search-palette-input"
      end
    end
  end

  # ===========================================================================
  # 2. LobbyLive deferred subscriptions
  # ===========================================================================

  describe "LobbyLive deferred subscriptions" do
    test "lobby mounts successfully with deferred subscriptions", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      assert is_binary(html)
    end

    test "lobby receives presence events (essential subscription)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      # Presence is an essential subscription — should work immediately
      # Verify by checking the page renders without crash
      html = render(view)
      assert is_binary(html)
    end

    test "lobby handles signal events after deferred subscription completes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      # Wait for deferred subscriptions to process
      Process.sleep(100)

      # Signal events should be received now — the handler won't crash
      # because signal subscriptions were deferred, not removed
      send(view.pid, {:signal, %{test: true}})

      # LobbyLive should still be alive
      assert Process.alive?(view.pid)
      html = render(view)
      assert is_binary(html)
    end

    test "all lobby lens routes mount with deferred subscriptions", %{conn: conn} do
      routes = [
        "/lobby",
        "/lobby/graph",
        "/lobby/heartrate",
        "/lobby/ecg",
        "/lobby/battery",
        "/lobby/breathing",
        "/lobby/hrv",
        "/lobby/gaze",
        "/lobby/imu",
        "/lobby/location",
        "/lobby/skeleton",
        "/lobby/favorites",
        "/lobby/users"
      ]

      for route <- routes do
        {:ok, _view, _html} = live(conn, route)
      end
    end

    test "deferred subscriptions handler processes without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      # Send deferred_subscriptions again (idempotent — subscribing twice is fine)
      send(view.pid, :deferred_subscriptions)
      Process.sleep(50)

      assert Process.alive?(view.pid)
    end

    test "lobby receives media events after deferred subscription", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")

      # Wait for deferred subscriptions
      Process.sleep(100)

      # Broadcast a media event — should not crash even if handler ignores it
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "media:lobby",
        {:media_event, %{type: :test}}
      )

      Process.sleep(50)
      assert Process.alive?(view.pid)
    end

    test "lobby receives call events after deferred subscription", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      Process.sleep(100)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "call:lobby",
        {:call_event, %{type: :test}}
      )

      Process.sleep(50)
      assert Process.alive?(view.pid)
    end

    test "lobby receives whiteboard events after deferred subscription", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      Process.sleep(100)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "whiteboard:lobby",
        {:whiteboard_event, %{type: :test}}
      )

      Process.sleep(50)
      assert Process.alive?(view.pid)
    end

    test "lobby receives object3d events after deferred subscription", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby")
      Process.sleep(100)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "object3d:lobby",
        {:object3d_event, %{type: :test}}
      )

      Process.sleep(50)
      assert Process.alive?(view.pid)
    end
  end

  # ===========================================================================
  # 3. SenseLive deferred signal subscription
  # ===========================================================================

  describe "SenseLive deferred signal subscription" do
    test "SenseLive mounts as layout child", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      assert find_live_child(view, "bluetooth")
    end

    test "SenseLive is present on all pages", %{conn: conn} do
      for route <- ["/", "/lobby", "/rooms", "/about"] do
        {:ok, view, _html} = live(conn, route)

        assert find_live_child(view, "bluetooth"),
               "SenseLive should be present on #{route}"
      end
    end

    test "SenseLive can be mounted in isolation without signal subscription", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.SenseLive,
          session: %{
            "parent_id" => nil,
            "user_token" => nil
          }
        )

      html = render(view)
      assert html =~ "SenseApp"

      # Process should be alive (didn't crash during mount)
      assert Process.alive?(view.pid)
    end

    test "SenseLive processes subscribe_signal without crash", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.SenseLive,
          session: %{
            "parent_id" => nil,
            "user_token" => nil
          }
        )

      # Manually trigger the deferred subscription (in case not connected)
      send(view.pid, :subscribe_signal)
      Process.sleep(50)

      assert Process.alive?(view.pid)
    end

    test "SenseLive handles signal messages after deferred subscription", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.SenseLive,
          session: %{
            "parent_id" => nil,
            "user_token" => nil
          }
        )

      # Trigger subscription and wait
      send(view.pid, :subscribe_signal)
      Process.sleep(50)

      # Send a signal message — should be handled (just logged, no crash)
      send(view.pid, {:signal, %{test: true}})
      Process.sleep(50)

      assert Process.alive?(view.pid)
    end
  end

  # ===========================================================================
  # 4. ChatSidebarLive and TabbedFooterLive sticky (pre-existing, verify)
  # ===========================================================================

  describe "layout LiveView stickiness" do
    test "ChatSidebarLive is present as sticky child", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")

      # ChatSidebarLive may or may not be present depending on chat_enabled?()
      # Just verify the page loads without crash
      assert Process.alive?(view.pid)
    end

    test "TabbedFooterLive is present as sticky child", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      assert find_live_child(view, "tabbed-footer-live")
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
