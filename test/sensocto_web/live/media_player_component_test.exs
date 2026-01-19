defmodule SensoctoWeb.Live.MediaPlayerComponentTest do
  @moduledoc """
  Integration tests for the MediaPlayerComponent functionality.

  These tests verify the server-side behavior of the media player
  without requiring browser automation or authentication.
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.Media
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Media.Playlist
  alias Sensocto.Media.PlaylistItem

  @moduletag :integration
  @moduletag :media_player

  # Helper to create a test room with a unique ID
  defp create_test_room do
    room_id = Ecto.UUID.generate()
    {:ok, room_id}
  end

  # Helper to create a playlist for a room
  defp create_playlist_for_room(room_id) do
    %Playlist{}
    |> Playlist.room_changeset(%{room_id: room_id, name: "Test Playlist"})
    |> Sensocto.Repo.insert()
  end

  defp add_test_video(playlist_id, attrs) do
    default_attrs = %{
      playlist_id: playlist_id,
      youtube_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      youtube_video_id: "dQw4w9WgXcQ",
      title: "Test Video",
      duration_seconds: 180,
      thumbnail_url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
      position: 0
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %PlaylistItem{}
    |> PlaylistItem.changeset(merged_attrs)
    |> Sensocto.Repo.insert()
  end

  defp start_media_player(room_id) do
    case MediaPlayerServer.start_link(room_id: room_id, is_lobby: false) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp stop_media_player(room_id) do
    case GenServer.whereis(MediaPlayerServer.via_tuple(room_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  defp clear_playlist(playlist) do
    playlist.id
    |> Media.get_playlist_items()
    |> Enum.each(fn item -> Media.remove_from_playlist(item.id) end)
  end

  describe "media player server state management" do
    test "starts in stopped state" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      assert state.state == :stopped
      assert state.position_seconds == 0.0
    end

    test "play changes state to playing" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_test_video(playlist.id, %{title: "Play Test Video"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Play without taking control (anyone can play when no controller)
      assert :ok = MediaPlayerServer.play(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.state == :playing

      clear_playlist(playlist)
    end

    test "pause changes state to paused" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_test_video(playlist.id, %{title: "Pause Test Video"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play(room_id)
      MediaPlayerServer.pause(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.state == :paused

      clear_playlist(playlist)
    end
  end

  describe "controller management" do
    test "take_control assigns controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.take_control(room_id, "test_user_123", "Test User")

      assert_receive {:media_controller_changed, %{controller_user_id: "test_user_123"}}, 2_000

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.controller_user_id == "test_user_123"
    end

    test "release_control clears controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.take_control(room_id, "test_user", "Test User")
      assert_receive {:media_controller_changed, _}, 2_000

      MediaPlayerServer.release_control(room_id, "test_user")

      assert_receive {:media_controller_changed, %{controller_user_id: nil}}, 2_000
    end

    test "non-controller cannot play" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_test_video(playlist.id, %{title: "Control Test Video"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Another user takes control
      MediaPlayerServer.take_control(room_id, "other_user", "Other User")

      {:ok, initial_state} = MediaPlayerServer.get_state(room_id)

      # Try to play as a different user (not the controller)
      result = MediaPlayerServer.play(room_id, "non_controller_user")

      # Should fail
      assert result == {:error, :not_controller}

      {:ok, final_state} = MediaPlayerServer.get_state(room_id)

      # State should be unchanged (still stopped, not playing)
      assert final_state.state == initial_state.state

      clear_playlist(playlist)
    end
  end

  describe "navigation" do
    test "next advances to next video" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_test_video(playlist.id, %{title: "Video 1", position: 0})
      {:ok, item2} = add_test_video(playlist.id, %{title: "Video 2", position: 1, youtube_video_id: "xQw4w9WgXcR"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Verify first item is selected
      {:ok, initial_state} = MediaPlayerServer.get_state(room_id)
      assert initial_state.current_item.id == item1.id

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.next(room_id)

      assert_receive {:media_video_changed, %{item: current}}, 2_000
      assert current.id == item2.id

      clear_playlist(playlist)
    end

    test "previous goes to previous video" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_test_video(playlist.id, %{title: "Video 1", position: 0})
      {:ok, item2} = add_test_video(playlist.id, %{title: "Video 2", position: 1, youtube_video_id: "xQw4w9WgXcR"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Go to second video first
      MediaPlayerServer.play_item(room_id, item2.id)
      Process.sleep(100)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.previous(room_id)

      assert_receive {:media_video_changed, %{item: current}}, 2_000
      assert current.id == item1.id

      clear_playlist(playlist)
    end
  end

  describe "PubSub synchronization" do
    test "state changes are broadcast" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_test_video(playlist.id, %{title: "Broadcast Test"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.play(room_id)

      assert_receive {:media_state_changed, %{state: :playing}}, 2_000

      clear_playlist(playlist)
    end

    test "seek updates position" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_test_video(playlist.id, %{title: "Position Test"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.seek(room_id, 30.0)

      assert_receive {:media_state_changed, %{position_seconds: pos}}, 2_000
      assert_in_delta pos, 30.0, 1.0

      clear_playlist(playlist)
    end
  end
end
