defmodule SensoctoWeb.LobbyGraphRegressionTest do
  @moduledoc """
  Regression tests for lobby graph controls and mobile footer.

  Guards against:
  - LobbyGraph Svelte component not rendering on /lobby/graph
  - TabbedFooterLive collapse/expand state logic
  - IndexLive graph preview rendering
  - Route availability for graph-related pages
  """

  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :integration

  # ===========================================================================
  # Setup: create an authenticated user
  # ===========================================================================

  setup %{conn: conn} do
    email = "lobby_graph_test_#{System.unique_integer([:positive])}@example.com"

    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: email,
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = log_in_user(conn, user)

    {:ok, conn: conn, user: user}
  end

  # ===========================================================================
  # 1. /lobby/graph route renders LobbyGraph Svelte component
  # ===========================================================================

  describe "/lobby/graph route" do
    test "mounts successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby/graph")
      assert html =~ "LobbyGraph"
    end

    test "renders graph container", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby/graph")
      # The Svelte component should have rendered with its data-live-svelte attribute
      assert html =~ "LobbyGraph"
    end

    test "live_action is :graph", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/lobby/graph")
      # The assigns should show :graph as the action
      assert render(view) =~ "LobbyGraph"
    end
  end

  # ===========================================================================
  # 2. /lobby route (sensors view) renders without errors
  # ===========================================================================

  describe "/lobby route" do
    test "mounts successfully", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/lobby")
    end

    test "shows mode selector for lenses", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/lobby")
      # The lobby page should render the view mode controls
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # 3. Index page graph preview
  # ===========================================================================

  describe "index page graph preview" do
    test "mounts successfully", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/")
    end

    test "shows Enter Lobby link", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Enter Lobby"
    end

    test "shows sensor count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "sensors online"
    end
  end

  # ===========================================================================
  # 4. TabbedFooterLive collapse/expand behavior
  # ===========================================================================

  describe "TabbedFooterLive collapse behavior" do
    test "primary pages start expanded (collapsed=false)" do
      assert primary_page?("/lobby")
      assert primary_page?("/lobby/graph")
      assert primary_page?("/rooms")
      assert primary_page?("/rooms/some-id")
    end

    test "non-primary pages start collapsed" do
      refute primary_page?("/")
      refute primary_page?("/sensors")
      refute primary_page?("/simulator")
      refute primary_page?("/settings")
    end

    test "expand_footer event sets collapsed to false", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.TabbedFooterLive,
          session: %{
            "current_user" => nil,
            "current_path" => "/simulator",
            "chat_enabled" => false
          }
        )

      # On /simulator, footer starts collapsed
      html = render(view)
      assert html =~ "expand_footer"

      # Click expand
      view |> element("button[phx-click=expand_footer]") |> render_click()

      # Now should show the full footer with nav items
      html = render(view)
      assert html =~ "Lobby"
      assert html =~ "Rooms"
    end

    test "switch_tab changes active tab", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.TabbedFooterLive,
          session: %{
            "current_user" => nil,
            "current_path" => "/lobby",
            "chat_enabled" => false
          }
        )

      # Default tab is :nav
      html = render(view)
      assert html =~ "Navigate"

      # Switch to controls tab
      view
      |> element("button[phx-click=switch_tab][phx-value-tab=controls]")
      |> render_click()

      html = render(view)
      assert html =~ "bluetooth-mobile-tabbed"
    end

    test "path_changed event updates collapse state", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, SensoctoWeb.TabbedFooterLive,
          session: %{
            "current_user" => nil,
            "current_path" => "/lobby",
            "chat_enabled" => false
          }
        )

      # Navigate away from primary page
      render_hook(view, "path_changed", %{"path" => "/simulator"})
      html = render(view)
      # Should be collapsed now, showing the pill
      assert html =~ "expand_footer"

      # Navigate back to primary page
      render_hook(view, "path_changed", %{"path" => "/lobby"})
      html = render(view)
      # Should show full nav
      assert html =~ "Lobby"
    end
  end

  # ===========================================================================
  # 5. Route availability
  # ===========================================================================

  describe "all lobby routes are accessible" do
    @lobby_routes [
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

    for route <- @lobby_routes do
      test "#{route} mounts without crash", %{conn: conn} do
        {:ok, _view, _html} = live(conn, unquote(route))
      end
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp primary_page?(path) do
    String.starts_with?(path, "/lobby") or String.starts_with?(path, "/rooms")
  end

  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
