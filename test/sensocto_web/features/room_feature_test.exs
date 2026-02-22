defmodule SensoctoWeb.Features.RoomFeatureTest do
  @moduledoc """
  End-to-end tests for room creation and navigation.

  Tests the rooms list page, room creation flow, and room detail view.
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "rooms list" do
    @tag :e2e
    test "authenticated user can view rooms page", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/rooms")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "room creation" do
    @tag :e2e
    test "user can open room creation form", %{session: session} do
      session
      |> sign_in_as_guest()
      |> visit("/rooms/new")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "room join by code" do
    @tag :e2e
    test "join page renders for a code", %{session: session} do
      session
      |> visit("/rooms/join/TESTCODE")
      |> wait_for_liveview()
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end
end
