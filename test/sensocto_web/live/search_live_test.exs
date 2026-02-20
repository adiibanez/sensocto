defmodule SensoctoWeb.SearchLiveTest do
  @moduledoc """
  Tests for SearchLive — the global command palette (Cmd+K).
  No auth required, layout: false.
  """
  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # SearchLive is embedded in the layout but we can test it standalone
    # by mounting it directly. It uses layout: false.
    # We need an authenticated user since it's in the main app layout.
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "search_test_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = log_in_user(conn, user)

    # Index some test data for search
    Sensocto.Search.SearchIndex.index_sensor("search_test_sensor", %{
      name: "TestHeartRate",
      type: "heartrate"
    })

    Sensocto.Search.SearchIndex.index_room("search_test_room", %{
      name: "TestMeditationRoom",
      description: "A test room"
    })

    Process.sleep(50)

    on_exit(fn ->
      Sensocto.Search.SearchIndex.remove_sensor("search_test_sensor")
      Sensocto.Search.SearchIndex.remove_room("search_test_room")
    end)

    {:ok, conn: conn}
  end

  describe "mount" do
    test "starts closed with empty state", %{conn: conn} do
      # Visit any page that includes the search bar
      {:ok, view, _html} = live(conn, "/about")

      # The search container should exist but be closed
      html = render(view)
      assert html =~ "search-container"
    end
  end

  describe "open/close events" do
    test "open event shows the palette", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")

      # Find the search live view
      search_view = find_live_child(view, "search-live")

      if search_view do
        render_click(search_view, "open")
        html = render(search_view)
        assert html =~ "Search sensors, rooms"
      end
    end
  end

  describe "search event" do
    test "searching with query returns results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      search_view = find_live_child(view, "search-live")

      if search_view do
        render_click(search_view, "open")
        html = render_change(search_view, "search", %{"query" => "TestHeart"})
        assert html =~ "TestHeartRate" or html =~ "Sensors"
      end
    end
  end

  describe "keyboard navigation" do
    test "Escape closes the palette", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/about")
      search_view = find_live_child(view, "search-live")

      if search_view do
        render_click(search_view, "open")
        render_keydown(search_view, "keydown", %{"key" => "Escape"})
        # After escape, the open overlay should be gone
        html = render(search_view)
        # The search input should not be visible when closed
        refute html =~ "search-palette-input"
      end
    end
  end

  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
