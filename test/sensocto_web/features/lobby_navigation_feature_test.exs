defmodule SensoctoWeb.Features.LobbyNavigationFeatureTest do
  @moduledoc """
  End-to-end tests for lobby navigation and lens switching.

  Tests tab navigation between sensor lenses, hierarchy view,
  and responsive layout on different viewports.
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "lobby lens navigation" do
    @tag :e2e
    test "lobby loads with default sensors view", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("[data-phx-main]", visible: true))
    end

    @tag :e2e
    test "user can navigate to heart rate lens", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/lobby/heartrate")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end

    @tag :e2e
    test "user can navigate to ECG lens", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/lobby/ecg")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end

    @tag :e2e
    test "user can navigate to hierarchy view", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/lobby/hierarchy")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "lobby responsive layout" do
    @tag :e2e
    test "lobby renders correctly on mobile viewport", %{session: session} do
      session
      |> resize_window(375, 812)
      |> visit_lobby()
      |> assert_has(css("[data-phx-main]", visible: true))
    end

    @tag :e2e
    test "lobby renders correctly on tablet viewport", %{session: session} do
      session
      |> resize_window(768, 1024)
      |> visit_lobby()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "lobby graph view" do
    @tag :e2e
    test "user can navigate to graph view", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/lobby/graph")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end
end
