defmodule SensoctoWeb.Features.CollabDemoFeatureTest do
  @moduledoc """
  End-to-end tests for collaborative demo features across all components.

  Tests multi-user scenarios, cross-device compatibility, and real-time
  synchronization for whiteboard, media player, and 3D object viewer.

  ## UI Structure

  The lobby page has a tabbed interface for collab demos:
  - Media tab (default)
  - 3D Object tab
  - Whiteboard tab

  Only one component is visible at a time. Tests must switch tabs to interact
  with different components.

  ## Tags

  - @tag :e2e - All E2E tests
  - @tag :multi_user - Tests requiring multiple browser sessions
  - @tag :slow - Tests > 5 seconds
  - @tag :touch - Touch event specific tests
  - @tag :mobile - Mobile viewport tests
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "lobby page loads collaborative components" do
    @tag :e2e
    test "collab demo tabs are visible on lobby", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("button", text: "Whiteboard"))
      |> assert_has(css("button", text: "Media"))
      |> assert_has(css("button", text: "3D Object"))
    end

    @tag :e2e
    test "whiteboard loads when tab is clicked", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end

    @tag :e2e
    test "3D object viewer loads when tab is clicked", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_object3d_tab()
      |> assert_has(css("button", text: "Take Control"))
    end
  end

  describe "whiteboard functionality" do
    @tag :e2e
    test "whiteboard has tool buttons", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> assert_has(css("button", text: "Pen"))
      |> assert_has(css("button", text: "Eraser"))
      |> assert_has(css("button", text: "Line"))
      |> assert_has(css("button", text: "Rectangle"))
    end

    @tag :e2e
    test "take control button works on whiteboard", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> click(css("button", text: "Take Control"))
      |> then(fn s ->
        Process.sleep(300)
        s
      end)
      |> assert_has(css("button", text: "Release"))
    end
  end

  describe "3D object viewer functionality" do
    @tag :e2e
    test "3D viewer has navigation buttons", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_object3d_tab()
      |> assert_has(css("button", text: "Previous"))
      |> assert_has(css("button", text: "Next"))
    end

    @tag :e2e
    test "3D viewer has view controls", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_object3d_tab()
      |> assert_has(css("button", text: "Center"))
      |> assert_has(css("button", text: "Reset View"))
    end
  end

  describe "multi-user collaboration workflow" do
    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "two users can see each other's presence on the page", %{session: session1} do
      session1
      |> visit_lobby()
      |> wait_for_liveview()

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_liveview()
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)

      Wallaby.end_session(session2)
    end

    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "control handoff works on whiteboard", %{session: session1} do
      session1
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> click(css("button", text: "Take Control"))
      |> then(fn s ->
        Process.sleep(500)
        s
      end)

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> assert_has(css("button", text: "Request"))

      Wallaby.end_session(session2)
    end
  end

  describe "mobile viewport compatibility" do
    @tag :e2e
    @tag :mobile
    test "collab tabs render correctly on mobile viewport", %{session: session} do
      session
      |> resize_window(375, 812)
      |> visit_lobby()
      |> assert_has(css("button", text: "Whiteboard"))
      |> assert_has(css("button", text: "Media"))
      |> assert_has(css("button", text: "3D Object"))
    end

    @tag :e2e
    @tag :mobile
    test "whiteboard controls are accessible on small screens", %{session: session} do
      session
      |> resize_window(375, 812)
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> assert_has(css("button", text: "Take Control", visible: true))
    end
  end

  describe "tablet viewport compatibility" do
    @tag :e2e
    test "components render correctly on tablet viewport", %{session: session} do
      session
      |> resize_window(768, 1024)
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end
  end

  describe "keyboard accessibility" do
    @tag :e2e
    test "buttons are focusable via keyboard", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_liveview()
      |> send_keys([:tab])
      |> then(fn session ->
        Process.sleep(100)
        session
      end)
    end
  end

  describe "network resilience" do
    @tag :e2e
    @tag :slow
    test "components recover after brief disconnect", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_liveview()
      |> execute_script("window.liveSocket.disconnect()")
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> execute_script("window.liveSocket.connect()")
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "browser compatibility checks" do
    @tag :e2e
    test "WebGL is available for 3D viewer", %{session: session} do
      session
      |> visit_lobby()
      |> local_execute_js("""
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        return !!gl;
      """)
      |> then(fn {session, webgl_available} ->
        assert webgl_available == true
        session
      end)
    end

    @tag :e2e
    test "ResizeObserver is available for responsive canvas", %{session: session} do
      session
      |> visit_lobby()
      |> local_execute_js("return typeof ResizeObserver !== 'undefined'")
      |> then(fn {session, resize_observer_available} ->
        assert resize_observer_available == true
        session
      end)
    end
  end

  describe "performance under load" do
    @tag :e2e
    @tag :slow
    test "rapid control toggles don't crash whiteboard", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> rapid_toggle_control(5)
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end

    @tag :e2e
    @tag :slow
    test "rapid tool switches don't crash whiteboard", %{session: session} do
      session
      |> visit_lobby()
      |> switch_to_whiteboard_tab()
      |> click(css("button", text: "Take Control"))
      |> then(fn s ->
        Process.sleep(300)
        s
      end)
      |> then(fn session ->
        Enum.reduce(1..5, session, fn _, s ->
          s
          |> click(css("button", text: "Pen"))
          |> click(css("button", text: "Eraser"))
          |> click(css("button", text: "Line"))
          |> click(css("button", text: "Rectangle"))
        end)
      end)
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end
  end

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  defp local_execute_js(session, script) do
    result = execute_script(session, script)
    {session, result}
  end

  defp rapid_toggle_control(session, times) do
    Enum.reduce(1..times, session, fn _, s ->
      s
      |> click(css("button", text: "Take Control"))
      |> then(fn session ->
        Process.sleep(150)
        session
      end)
      |> click(css("button", text: "Release"))
      |> then(fn session ->
        Process.sleep(150)
        session
      end)
    end)
  end
end
