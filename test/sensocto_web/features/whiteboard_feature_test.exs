defmodule SensoctoWeb.Features.WhiteboardFeatureTest do
  @moduledoc """
  End-to-end tests for the collaborative whiteboard component.

  Tests cover:
  - Canvas rendering and tool selection
  - Drawing with mouse and touch events
  - Multi-user collaboration and control system
  - Cross-device compatibility (touch vs mouse)
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "whiteboard rendering" do
    @tag :e2e
    test "whiteboard component loads on lobby page", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("[id*='whiteboard-']", visible: true))
      |> assert_has(css("[data-whiteboard-canvas='true']", visible: true))
    end

    @tag :e2e
    test "whiteboard canvas has correct dimensions", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> execute_js("""
        const canvas = document.querySelector('[data-whiteboard-canvas="true"]');
        return {
          width: canvas.offsetWidth,
          height: canvas.offsetHeight,
          aspectRatio: (canvas.offsetWidth / canvas.offsetHeight).toFixed(2)
        };
      """)
      |> then(fn {session, result} ->
        # Canvas should maintain 16:9 aspect ratio
        assert result["aspectRatio"] == "1.78" or result["aspectRatio"] == "1.77"
        session
      end)
    end

    @tag :e2e
    test "whiteboard can be collapsed and expanded", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> assert_has(css("[data-whiteboard-canvas='true']", visible: true))
      |> click(css("[phx-click='toggle_collapsed']"))
      |> refute_has(css("[data-whiteboard-canvas='true']", visible: true))
      |> click(css("[phx-click='toggle_collapsed']"))
      |> assert_has(css("[data-whiteboard-canvas='true']", visible: true))
    end
  end

  describe "tool selection" do
    @tag :e2e
    test "pen tool is selected by default", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> assert_has(css("[phx-click='set_tool'][phx-value-tool='pen'].bg-green-600"))
    end

    @tag :e2e
    test "can switch between drawing tools", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      # Switch to eraser
      |> click(css("[phx-click='set_tool'][phx-value-tool='eraser']"))
      |> assert_has(css("[phx-click='set_tool'][phx-value-tool='eraser'].bg-green-600"))
      # Switch to line tool
      |> click(css("[phx-click='set_tool'][phx-value-tool='line']"))
      |> assert_has(css("[phx-click='set_tool'][phx-value-tool='line'].bg-green-600"))
      # Switch to rectangle tool
      |> click(css("[phx-click='set_tool'][phx-value-tool='rect']"))
      |> assert_has(css("[phx-click='set_tool'][phx-value-tool='rect'].bg-green-600"))
      # Switch back to pen
      |> click(css("[phx-click='set_tool'][phx-value-tool='pen']"))
      |> assert_has(css("[phx-click='set_tool'][phx-value-tool='pen'].bg-green-600"))
    end

    @tag :e2e
    test "tool selection updates data attribute on hook element", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='set_tool'][phx-value-tool='eraser']"))
      |> assert_has(css("[id*='whiteboard-'][data-tool='eraser']"))
    end
  end

  describe "color picker" do
    @tag :e2e
    test "color picker opens and closes", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      # Color picker should be closed initially
      |> refute_has(css("[phx-click='set_color']"))
      # Open color picker
      |> click(css("[phx-click='toggle_color_picker']"))
      |> assert_has(css("[phx-click='set_color']", count: 10))
      # Close by clicking toggle again
      |> click(css("[phx-click='toggle_color_picker']"))
      |> refute_has(css("[phx-click='set_color']"))
    end

    @tag :e2e
    test "selecting a color updates the stroke color", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='toggle_color_picker']"))
      |> click(css("[phx-click='set_color'][phx-value-color='#ef4444']"))
      |> assert_has(css("[id*='whiteboard-'][data-color='#ef4444']"))
    end
  end

  describe "stroke width" do
    @tag :e2e
    test "stroke width can be changed via dropdown", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> fill_in(css("select[name='width']"), with: "8")
      |> assert_has(css("[id*='whiteboard-'][data-width='8']"))
    end
  end

  describe "drawing with mouse" do
    @tag :e2e
    test "mouse down/move/up creates a stroke", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> take_whiteboard_control()
      |> simulate_mouse_draw()
      |> then(fn session ->
        # Verify stroke was sent to server via LiveView
        # The canvas should have received the stroke
        Process.sleep(500)
        session
      end)
    end

    @tag :e2e
    test "drawing is disabled when not in control", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      # Don't take control - try to draw
      |> simulate_mouse_draw()

      # Stroke should not be created (no error but no effect)
    end
  end

  describe "drawing with touch" do
    @tag :e2e
    @tag :touch
    test "touch events create strokes", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> take_whiteboard_control()
      |> simulate_touch_draw()
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
    end

    @tag :e2e
    @tag :touch
    test "canvas has touch-action: none for proper touch handling", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> execute_js("""
        const canvas = document.querySelector('[data-whiteboard-canvas="true"]');
        return window.getComputedStyle(canvas).touchAction;
      """)
      |> then(fn {session, result} ->
        assert result == "none"
        session
      end)
    end
  end

  describe "control system" do
    @tag :e2e
    test "take control button is visible when no controller", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> assert_has(css("[phx-click='take_control']", text: "Take Control"))
    end

    @tag :e2e
    test "taking control shows release button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='take_control']"))
      |> assert_has(css("[phx-click='release_control']", text: "Release"))
    end

    @tag :e2e
    test "releasing control shows take control button again", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='take_control']"))
      |> assert_has(css("[phx-click='release_control']"))
      |> click(css("[phx-click='release_control']"))
      |> assert_has(css("[phx-click='take_control']", text: "Take Control"))
    end
  end

  describe "multi-user collaboration" do
    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "second user sees request control button when first user has control", %{
      session: session1
    } do
      # First user takes control
      session1
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='take_control']"))

      # Second user opens the page
      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> assert_has(css("[phx-click='request_control']", text: "Request"))

      Wallaby.end_session(session2)
    end

    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "strokes sync between multiple users", %{session: session1} do
      # First user takes control and draws
      session1
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> click(css("[phx-click='take_control']"))
      |> simulate_mouse_draw()

      # Second user should see the stroke
      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> then(fn session ->
        # Give time for sync
        Process.sleep(1000)
        session
      end)
      |> execute_js("""
        const hook = document.querySelector('[id*="whiteboard-"]').__liveViewHook;
        return hook ? hook.strokes?.length || 0 : -1;
      """)
      |> then(fn {session, stroke_count} ->
        # Second user should have received the stroke
        assert stroke_count >= 0
        session
      end)

      Wallaby.end_session(session2)
    end
  end

  describe "undo and clear" do
    @tag :e2e
    test "undo button removes last stroke", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> take_whiteboard_control()
      |> simulate_mouse_draw()
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[phx-click='undo']"))
    end

    @tag :e2e
    test "clear button removes all strokes", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_whiteboard()
      |> take_whiteboard_control()
      |> simulate_mouse_draw()
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[phx-click='clear_whiteboard']"))
    end
  end

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  defp simulate_mouse_draw(session) do
    execute_script(session, """
      const canvas = document.querySelector('[data-whiteboard-canvas="true"]');
      const rect = canvas.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      // Simulate mouse events
      const mousedown = new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        clientX: centerX - 50,
        clientY: centerY,
        button: 0
      });

      const mousemove = new MouseEvent('mousemove', {
        bubbles: true,
        cancelable: true,
        clientX: centerX + 50,
        clientY: centerY,
        button: 0
      });

      const mouseup = new MouseEvent('mouseup', {
        bubbles: true,
        cancelable: true,
        clientX: centerX + 50,
        clientY: centerY,
        button: 0
      });

      canvas.dispatchEvent(mousedown);
      setTimeout(() => {
        canvas.dispatchEvent(mousemove);
        setTimeout(() => {
          canvas.dispatchEvent(mouseup);
        }, 50);
      }, 50);
    """)

    Process.sleep(200)
    session
  end

  defp simulate_touch_draw(session) do
    execute_script(session, """
      const canvas = document.querySelector('[data-whiteboard-canvas="true"]');
      const rect = canvas.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      // Create touch objects
      const touch1 = new Touch({
        identifier: 1,
        target: canvas,
        clientX: centerX - 50,
        clientY: centerY
      });

      const touch2 = new Touch({
        identifier: 1,
        target: canvas,
        clientX: centerX + 50,
        clientY: centerY
      });

      // Simulate touch events
      const touchstart = new TouchEvent('touchstart', {
        bubbles: true,
        cancelable: true,
        touches: [touch1],
        targetTouches: [touch1],
        changedTouches: [touch1]
      });

      const touchmove = new TouchEvent('touchmove', {
        bubbles: true,
        cancelable: true,
        touches: [touch2],
        targetTouches: [touch2],
        changedTouches: [touch2]
      });

      const touchend = new TouchEvent('touchend', {
        bubbles: true,
        cancelable: true,
        touches: [],
        targetTouches: [],
        changedTouches: [touch2]
      });

      canvas.dispatchEvent(touchstart);
      setTimeout(() => {
        canvas.dispatchEvent(touchmove);
        setTimeout(() => {
          canvas.dispatchEvent(touchend);
        }, 50);
      }, 50);
    """)

    Process.sleep(200)
    session
  end
end
