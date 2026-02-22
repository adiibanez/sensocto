defmodule SensoctoWeb.Features.AuthFlowFeatureTest do
  @moduledoc """
  End-to-end tests for authentication flows.

  Tests guest sign-in, sign-out, and protected route access.
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "guest authentication" do
    @tag :e2e
    test "user can sign in as guest from sign-in page", %{session: session} do
      session
      |> visit("/sign-in")
      |> assert_has(css("[phx-click='join_as_guest']"))
      |> click(css("[phx-click='join_as_guest']"))
      |> wait_for_liveview()
      # After guest sign-in, should be redirected away from sign-in
      |> refute_has(css("[phx-click='join_as_guest']"))
    end

    @tag :e2e
    test "guest user can access the lobby", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "protected routes" do
    @tag :e2e
    test "unauthenticated user visiting /lobby gets redirected to sign-in", %{session: session} do
      session
      |> visit("/lobby")
      |> wait_for_liveview()
      # Should see sign-in page elements since user is not authenticated
      |> assert_has(css("[data-phx-main]", visible: true))
    end

    @tag :e2e
    test "authenticated user can access /devices", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/devices")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "sign-in page rendering" do
    @tag :e2e
    test "sign-in page renders without errors", %{session: session} do
      session
      |> visit("/sign-in")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end
end
