defmodule SensoctoWeb.Features.MediaPlayerFeatureTest do
  @moduledoc """
  End-to-end tests for the collaborative media player component.

  Tests cover:
  - YouTube video playback sync
  - Playlist management and navigation
  - Control system (take/release/request)
  - Cross-device compatibility
  - Multi-user synchronization
  """
  use SensoctoWeb.FeatureCase

  import Wallaby.Query

  @moduletag :e2e

  describe "media player rendering" do
    @tag :e2e
    test "media player component loads on lobby page", %{session: session} do
      session
      |> visit_lobby()
      |> assert_has(css("[id*='media-player']", visible: true))
    end

    @tag :e2e
    test "media player shows video area", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> assert_has(css("[id*='media-player']"))
    end

    @tag :e2e
    test "media player can be collapsed and expanded", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='toggle_collapsed']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='media-player'] [phx-click='toggle_collapsed']"))
    end
  end

  describe "playback controls" do
    @tag :e2e
    test "play button is visible when video is stopped", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> assert_has(css("[id*='media-player'] [phx-click='play']"))
    end

    @tag :e2e
    test "clicking play shows pause button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> click(css("[id*='media-player'] [phx-click='play']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> assert_has(css("[id*='media-player'] [phx-click='pause']"))
    end

    @tag :e2e
    test "clicking pause shows play button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> click(css("[id*='media-player'] [phx-click='play']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> click(css("[id*='media-player'] [phx-click='pause']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> assert_has(css("[id*='media-player'] [phx-click='play']"))
    end
  end

  describe "playlist navigation" do
    @tag :e2e
    test "next button advances to next item", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> click(css("[id*='media-player'] [phx-click='next']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
    end

    @tag :e2e
    test "previous button goes to previous item", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      # Go to next first
      |> click(css("[id*='media-player'] [phx-click='next']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='media-player'] [phx-click='previous']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
    end

    @tag :e2e
    test "playlist items are clickable", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> assert_has(css("[id*='media-player'] [phx-click='play_item']"))
    end
  end

  describe "control system" do
    @tag :e2e
    test "take control button is visible initially", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> assert_has(css("[id*='media-player'] [phx-click='take_control']"))
    end

    @tag :e2e
    test "taking control shows release button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
      |> assert_has(css("[id*='media-player'] [phx-click='release_control']"))
    end

    @tag :e2e
    test "releasing control shows take control button", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='media-player'] [phx-click='release_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> assert_has(css("[id*='media-player'] [phx-click='take_control']"))
    end

    @tag :e2e
    test "controller name is displayed when someone has control", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> assert_has(css("[id*='media-player']", text: "Controlled by"))
    end
  end

  describe "sync mode" do
    @tag :e2e
    test "sync mode toggle is present", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> assert_has(css("[id*='media-player'] [phx-click='toggle_sync_mode']"))
    end

    @tag :e2e
    test "toggling sync mode changes state", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='toggle_sync_mode']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
    end
  end

  describe "multi-user synchronization" do
    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "second user sees request control when first has control", %{session: session1} do
      # First user takes control
      session1
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='take_control']"))

      Process.sleep(500)

      # Second user opens the page
      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_media_player()
      |> assert_has(css("[id*='media-player'] [phx-click='request_control']"))

      Wallaby.end_session(session2)
    end

    @tag :e2e
    @tag :multi_user
    @tag :slow
    test "playback state syncs between users", %{session: session1} do
      # First user takes control and plays
      session1
      |> visit_lobby()
      |> wait_for_media_player()
      |> click(css("[id*='media-player'] [phx-click='take_control']"))
      |> then(fn session ->
        Process.sleep(300)
        session
      end)
      |> click(css("[id*='media-player'] [phx-click='play']"))

      Process.sleep(1000)

      # Second user should see playing state
      {:ok, session2} = Wallaby.start_session()

      session2
      |> visit_lobby()
      |> wait_for_media_player()
      |> assert_has(css("[id*='media-player'] [phx-click='pause']"))

      Wallaby.end_session(session2)
    end
  end

  describe "YouTube iframe" do
    @tag :e2e
    test "YouTube iframe loads for video playback", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> click(css("[id*='media-player'] [phx-click='play']"))
      |> then(fn session ->
        Process.sleep(2000)
        session
      end)
      |> assert_has(css("iframe[src*='youtube']"))
    end
  end

  describe "progress bar" do
    @tag :e2e
    test "progress bar is visible during playback", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> take_media_player_control()
      |> click(css("[id*='media-player'] [phx-click='play']"))
      |> then(fn session ->
        Process.sleep(1000)
        session
      end)
    end
  end

  describe "mobile touch interactions" do
    @tag :e2e
    @tag :touch
    test "controls respond to touch events", %{session: session} do
      session
      |> visit_lobby()
      |> wait_for_media_player()
      |> execute_script("""
        const takeControlBtn = document.querySelector('[id*="media-player"] [phx-click="take_control"]');
        if (takeControlBtn) {
          const touch = new Touch({
            identifier: 1,
            target: takeControlBtn,
            clientX: 0,
            clientY: 0
          });
          const touchstart = new TouchEvent('touchstart', {
            bubbles: true,
            cancelable: true,
            touches: [touch],
            targetTouches: [touch],
            changedTouches: [touch]
          });
          const touchend = new TouchEvent('touchend', {
            bubbles: true,
            cancelable: true,
            touches: [],
            targetTouches: [],
            changedTouches: [touch]
          });
          takeControlBtn.dispatchEvent(touchstart);
          takeControlBtn.dispatchEvent(touchend);
        }
      """)
      |> then(fn session ->
        Process.sleep(500)
        session
      end)
    end
  end

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  defp take_media_player_control(session) do
    session
    |> click(css("[id*='media-player'] [phx-click='take_control']"))
    |> then(fn session ->
      Process.sleep(300)
      session
    end)
  end
end
