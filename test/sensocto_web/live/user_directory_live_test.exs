defmodule SensoctoWeb.UserDirectoryLiveTest do
  @moduledoc """
  Tests for the UserDirectoryLive (list and graph views).
  """
  use SensoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    # Create an authenticated user
    user =
      Ash.Seed.seed!(Sensocto.Accounts.User, %{
        email: "directory_test_#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.utc_now(),
        is_public: true,
        display_name: "Directory Tester",
        bio: "Testing the directory"
      })

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(user, %{purpose: :user}, token_lifetime: {1, :hours})

    user = Map.put(user, :__metadata__, %{token: token})
    conn = log_in_user(conn, user)

    {:ok, conn: conn, user: user}
  end

  describe "/users (list view)" do
    test "mounts successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")
      assert html =~ "Users"
      assert html =~ "Public user directory"
    end

    test "shows the List/Graph tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")
      assert html =~ "List"
      assert html =~ "Graph"
    end

    test "displays the search input", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")
      assert html =~ "Search users"
    end

    test "shows users in the list", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, "/users")
      assert html =~ user.display_name
    end

    test "search filters users", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/users")

      # Search for the test user's name
      html = view |> element("form") |> render_change(%{"search" => "Directory Tester"})
      assert html =~ user.display_name

      # Search for something that doesn't match
      html = view |> element("form") |> render_change(%{"search" => "zzz_nonexistent_zzz"})
      assert html =~ "No users found"
    end
  end

  describe "/users/graph (graph view)" do
    test "mounts successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users/graph")
      assert html =~ "Users"
      assert html =~ "UserGraph"
    end

    test "shows graph container with Svelte component", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users/graph")
      assert html =~ "UserGraph"
    end
  end

  describe "navigation between views" do
    test "navigating from list to graph", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")
      # List view has search, no UserGraph
      assert html =~ "Search users"
      refute html =~ "UserGraph"

      # Navigate to graph
      {:ok, _view, html} = live(conn, "/users/graph")
      assert html =~ "UserGraph"
    end
  end

  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
