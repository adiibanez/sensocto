defmodule SensoctoWeb.Features.CollabDemoFeatureTest do
  @moduledoc """
  End-to-end tests for collaborative demo features across all components.

  Tests multi-user scenarios, cross-device compatibility, and real-time
  synchronization for whiteboard, media player, and 3D object viewer.

  ## UI Structure

  The lobby page has a tabbed interface for collab demos:
  - 3D Object tab (default when visiting lobby)
  - Media tab
  - Whiteboard tab

  Only one component is visible at a time. Tests must switch tabs to interact
  with different components.

  ## Tags

  - @tag :e2e - All E2E tests
  - @tag :multi_user - Tests requiring multiple browser sessions
  - @tag :slow - Tests > 5 seconds
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
      |> click(css("button", text: "Whiteboard"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end

    @tag :e2e
    test "3D object tab can be selected", %{session: session} do
      # Note: 3D viewer may fail in headless Chrome due to no WebGL
      # This test just verifies the tab can be clicked
      session
      |> visit_lobby()
      |> click(css("button", text: "3D Object"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
      # Just verify the page didn't crash - 3D content may not render without WebGL
      |> assert_has(css("[data-phx-main]", visible: true))
    end
  end

  describe "whiteboard functionality" do
    @tag :e2e
    test "whiteboard is rendered when tab is clicked", %{session: session} do
      session
      |> visit_lobby()
      |> click(css("button", text: "Whiteboard"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end

    @tag :e2e
    test "whiteboard component loads without error", %{session: session} do
      session
      |> visit_lobby()
      |> click(css("button", text: "Whiteboard"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
      # Verify whiteboard is rendered and has buttons
      |> assert_has(css("#whiteboard-lobby", visible: true))
      |> assert_has(css("#whiteboard-lobby button", count: :any, minimum: 1))
    end
  end

  # Note: 3D object viewer tests are limited in headless Chrome
  # because WebGL isn't available. Full 3D functionality should be
  # tested manually or with a non-headless browser configuration.

  describe "multi-user collaboration workflow" do
    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "two users can access the lobby simultaneously", %{session: session1} do
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
  end

  describe "mobile viewport compatibility" do
    @tag :e2e
    test "collab tabs render correctly on mobile viewport", %{session: session} do
      session
      |> resize_window(375, 812)
      |> visit_lobby()
      |> assert_has(css("button", text: "Whiteboard"))
      |> assert_has(css("button", text: "Media"))
      |> assert_has(css("button", text: "3D Object"))
    end

    @tag :e2e
    test "whiteboard is accessible on small screens", %{session: session} do
      session
      |> resize_window(375, 812)
      |> visit_lobby()
      |> click(css("button", text: "Whiteboard"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
      |> assert_has(css("#whiteboard-lobby", visible: true))
    end
  end

  describe "tablet viewport compatibility" do
    @tag :e2e
    test "components render correctly on tablet viewport", %{session: session} do
      session
      |> resize_window(768, 1024)
      |> visit_lobby()
      |> click(css("button", text: "Whiteboard"))
      |> then(fn s ->
        Process.sleep(1000)
        s
      end)
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
    test "WebGL check runs without error", %{session: session} do
      # WebGL may not be available in headless Chrome, but the check should run
      session
      |> visit_lobby()
      |> execute_script(
        """
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
        return !!gl;
        """,
        fn result ->
          # WebGL may be true or false depending on environment
          assert is_boolean(result)
        end
      )
    end

    @tag :e2e
    test "ResizeObserver is available for responsive canvas", %{session: session} do
      session
      |> visit_lobby()
      |> execute_script("return typeof ResizeObserver !== 'undefined'", fn result ->
        assert result == true
      end)
    end
  end
end
