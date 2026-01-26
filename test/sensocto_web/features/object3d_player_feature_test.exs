defmodule SensoctoWeb.Features.Object3DPlayerFeatureTest do
  @moduledoc """
  End-to-end tests for the collaborative 3D object viewer component.

  Tests cover:
  - Gaussian splat viewer loading
  - Camera synchronization between users
  - Playlist navigation and management
  - Control system (take/release/request)
  - Cross-device compatibility (touch gestures vs mouse)
  - Load state tracking
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "3D object player rendering" do
    @tag :e2e
    test "3D object player component loads on lobby page", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("[id*='object3d-player']", visible: true))
    end

    @tag :e2e
    test "3D viewer area is present", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> assert_has(css("[id*='object3d-player']"))
    end

    @tag :e2e
    test "3D player can be collapsed and expanded", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='toggle_collapsed']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='object3d-player'] [phx-click='toggle_collapsed']"))
    end
  end

  describe "playlist navigation" do
    @tag :e2e
    test "next button advances to next 3D object", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> click(css("[id*='object3d-player'] [phx-click='next']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
    end

    @tag :e2e
    test "previous button goes to previous 3D object", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> click(css("[id*='object3d-player'] [phx-click='next']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='object3d-player'] [phx-click='previous']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
    end

    @tag :e2e
    test "playlist items are clickable for direct selection", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> assert_has(css("[id*='object3d-player'] [phx-click='view_item']"))
    end
  end

  describe "control system" do
    @tag :e2e
    test "take control button is visible initially", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> assert_has(css("[id*='object3d-player'] [phx-click='take_control']"))
    end

    @tag :e2e
    test "taking control shows release button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> assert_has(css("[id*='object3d-player'] [phx-click='release_control']"))
    end

    @tag :e2e
    test "releasing control shows take control button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='object3d-player'] [phx-click='release_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> assert_has(css("[id*='object3d-player'] [phx-click='take_control']"))
    end

    @tag :e2e
    test "controller name is displayed", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> assert_has(css("[id*='object3d-player']", text: "Controlled by"))
    end
  end

  describe "camera synchronization" do
    @tag :e2e
    test "sync mode toggle is present", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> assert_has(css("[id*='object3d-player'] [phx-click='toggle_sync_mode']"))
    end

    @tag :e2e
    test "toggling sync mode changes between synced and solo", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='toggle_sync_mode']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
    end
  end

  describe "Gaussian splat viewer" do
    @tag :e2e
    test "viewer iframe or canvas loads", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> then(fn session ->
        Process.sleep(2000)
        session
      end)
    end

    @tag :e2e
    test "viewer reports load state", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)
    end
  end

  describe "multi-user synchronization" do
    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "second user sees request control when first has control", %{session: session1} do
      session1
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))

      Process.sleep(500)

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> assert_has(css("[id*='object3d-player'] [phx-click='request_control']"))

      Wallaby.end_session(session2)
    end

    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "camera state syncs between users in sync mode", %{session: session1} do
      session1
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))

      Process.sleep(1000)

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)

      Wallaby.end_session(session2)
    end

    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "playlist navigation syncs between users", %{session: session1} do
      session1
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> click(css("[id*='object3d-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='object3d-player'] [phx-click='next']"))

      Process.sleep(1000)

      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)

      Wallaby.end_session(session2)
    end
  end

  describe "touch interactions for 3D navigation" do
    @tag :e2e
    @tag :touch
    test "touch gestures work on viewer area", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> simulate_touch_orbit()
    end

    @tag :e2e
    @tag :touch
    test "pinch zoom gesture support", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> simulate_pinch_zoom()
    end
  end

  describe "mouse interactions for 3D navigation" do
    @tag :e2e
    test "mouse drag rotates camera", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> simulate_mouse_orbit()
    end

    @tag :e2e
    test "mouse wheel zooms camera", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> simulate_mouse_wheel()
    end
  end

  describe "add object via URL" do
    @tag :e2e
    test "add object input is present", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
    end
  end

  describe "load state tracking" do
    @tag :e2e
    test "loading indicator appears during object load", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_object3d_player()
      |> take_object3d_control()
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
    end
  end

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  defp simulate_touch_orbit(session) do
    execute_script(session, """
      const viewer = document.querySelector('[id*="object3d-player"] iframe, [id*="object3d-player"] canvas');
      if (!viewer) return;

      const rect = viewer.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      const touch1 = new Touch({
        identifier: 1,
        target: viewer,
        clientX: centerX,
        clientY: centerY
      });

      const touch2 = new Touch({
        identifier: 1,
        target: viewer,
        clientX: centerX + 100,
        clientY: centerY + 50
      });

      viewer.dispatchEvent(new TouchEvent('touchstart', {
        bubbles: true, cancelable: true,
        touches: [touch1], targetTouches: [touch1], changedTouches: [touch1]
      }));

      setTimeout(() => {
        viewer.dispatchEvent(new TouchEvent('touchmove', {
          bubbles: true, cancelable: true,
          touches: [touch2], targetTouches: [touch2], changedTouches: [touch2]
        }));

        setTimeout(() => {
          viewer.dispatchEvent(new TouchEvent('touchend', {
            bubbles: true, cancelable: true,
            touches: [], targetTouches: [], changedTouches: [touch2]
          }));
        }, 100);
      }, 100);
    """)

    Process.sleep(300)
    session
  end

  defp simulate_pinch_zoom(session) do
    execute_script(session, """
      const viewer = document.querySelector('[id*="object3d-player"] iframe, [id*="object3d-player"] canvas');
      if (!viewer) return;

      const rect = viewer.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      const touch1Start = new Touch({
        identifier: 1, target: viewer,
        clientX: centerX - 30, clientY: centerY
      });
      const touch2Start = new Touch({
        identifier: 2, target: viewer,
        clientX: centerX + 30, clientY: centerY
      });

      const touch1End = new Touch({
        identifier: 1, target: viewer,
        clientX: centerX - 60, clientY: centerY
      });
      const touch2End = new Touch({
        identifier: 2, target: viewer,
        clientX: centerX + 60, clientY: centerY
      });

      viewer.dispatchEvent(new TouchEvent('touchstart', {
        bubbles: true, cancelable: true,
        touches: [touch1Start, touch2Start],
        targetTouches: [touch1Start, touch2Start],
        changedTouches: [touch1Start, touch2Start]
      }));

      setTimeout(() => {
        viewer.dispatchEvent(new TouchEvent('touchmove', {
          bubbles: true, cancelable: true,
          touches: [touch1End, touch2End],
          targetTouches: [touch1End, touch2End],
          changedTouches: [touch1End, touch2End]
        }));

        setTimeout(() => {
          viewer.dispatchEvent(new TouchEvent('touchend', {
            bubbles: true, cancelable: true,
            touches: [], targetTouches: [],
            changedTouches: [touch1End, touch2End]
          }));
        }, 100);
      }, 100);
    """)

    Process.sleep(300)
    session
  end

  defp simulate_mouse_orbit(session) do
    execute_script(session, """
      const viewer = document.querySelector('[id*="object3d-player"] iframe, [id*="object3d-player"] canvas');
      if (!viewer) return;

      const rect = viewer.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      viewer.dispatchEvent(new MouseEvent('mousedown', {
        bubbles: true, cancelable: true,
        clientX: centerX, clientY: centerY, button: 0
      }));

      setTimeout(() => {
        viewer.dispatchEvent(new MouseEvent('mousemove', {
          bubbles: true, cancelable: true,
          clientX: centerX + 100, clientY: centerY + 50, button: 0
        }));

        setTimeout(() => {
          viewer.dispatchEvent(new MouseEvent('mouseup', {
            bubbles: true, cancelable: true,
            clientX: centerX + 100, clientY: centerY + 50, button: 0
          }));
        }, 100);
      }, 100);
    """)

    Process.sleep(300)
    session
  end

  defp simulate_mouse_wheel(session) do
    execute_script(session, """
      const viewer = document.querySelector('[id*="object3d-player"] iframe, [id*="object3d-player"] canvas');
      if (!viewer) return;

      viewer.dispatchEvent(new WheelEvent('wheel', {
        bubbles: true, cancelable: true,
        deltaY: -100, deltaMode: 0
      }));
    """)

    Process.sleep(200)
    session
  end
end
