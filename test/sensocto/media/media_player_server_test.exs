defmodule Sensocto.Media.MediaPlayerServerTest do
  @moduledoc """
  Tests for Sensocto.Media.MediaPlayerServer GenServer.

  This GenServer manages synchronized media playback state for rooms and the lobby.
  It coordinates playback position, play/pause state, and playlist navigation
  across all connected clients.
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.Media
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Media.Playlist
  alias Sensocto.Media.PlaylistItem

  @moduletag :integration

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

  # Helper to add a playlist item
  defp add_playlist_item(playlist_id, attrs \\ %{}) do
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

  # Helper to start a media player server for a room
  defp start_media_player(room_id) do
    case MediaPlayerServer.start_link(room_id: room_id, is_lobby: false) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # Helper to stop a media player server
  defp stop_media_player(room_id) do
    case GenServer.whereis(MediaPlayerServer.via_tuple(room_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  describe "start_link/1" do
    test "starts a media player server for a room" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, pid} = start_media_player(room_id)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "creates a playlist if none exists" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      # No playlist exists yet
      assert is_nil(Media.get_room_playlist(room_id))

      # Start the server
      {:ok, _pid} = start_media_player(room_id)

      # Now a playlist should exist
      playlist = Media.get_room_playlist(room_id)
      assert not is_nil(playlist)
      assert playlist.room_id == room_id
    end

    test "uses existing playlist if one exists" do
      {:ok, room_id} = create_test_room()

      # Create a playlist first
      {:ok, existing_playlist} = create_playlist_for_room(room_id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      assert length(state.playlist_items) == 0
      # The server should use the existing playlist
      playlist = Media.get_room_playlist(room_id)
      assert playlist.id == existing_playlist.id
    end

    test "starts in stopped state" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      assert state.state == :stopped
      assert state.position_seconds == 0.0
    end
  end

  describe "get_state/1" do
    test "returns current player state" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      assert Map.has_key?(state, :state)
      assert Map.has_key?(state, :position_seconds)
      assert Map.has_key?(state, :current_item)
      assert Map.has_key?(state, :playlist_items)
      assert Map.has_key?(state, :controller_user_id)
      assert Map.has_key?(state, :controller_user_name)
      assert Map.has_key?(state, :volume)
    end

    test "returns error when server not found" do
      non_existent_room_id = Ecto.UUID.generate()

      result = MediaPlayerServer.get_state(non_existent_room_id)

      assert result == {:error, :not_found}
    end

    test "auto-selects first playlist item if none selected" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      assert state.current_item != nil
      assert state.current_item.id == item.id
    end
  end

  describe "play/2" do
    test "starts playback" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      assert :ok = MediaPlayerServer.play(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.state == :playing
    end

    test "returns error on empty playlist" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      result = MediaPlayerServer.play(room_id)

      assert result == {:error, :empty_playlist}
    end

    test "broadcasts state change on play" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Subscribe to media topic
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.play(room_id)

      assert_receive {:media_state_changed, payload}, 500
      assert payload.state == :playing
    end
  end

  describe "pause/2" do
    test "pauses playback" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # First play
      MediaPlayerServer.play(room_id)

      {:ok, playing_state} = MediaPlayerServer.get_state(room_id)
      assert playing_state.state == :playing

      # Then pause
      assert :ok = MediaPlayerServer.pause(room_id)

      {:ok, paused_state} = MediaPlayerServer.get_state(room_id)
      assert paused_state.state == :paused
    end

    test "preserves position when pausing" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play(room_id)

      # Wait a bit
      Process.sleep(100)

      MediaPlayerServer.pause(room_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)

      # Position should be slightly greater than 0 (elapsed time)
      assert state.position_seconds >= 0.0
    end
  end

  describe "seek/3" do
    test "seeks to specific position" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Seek to 30 seconds
      assert :ok = MediaPlayerServer.seek(room_id, 30.0)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.position_seconds >= 30.0
    end

    test "broadcasts seek event" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.seek(room_id, 45.0)

      assert_receive {:media_state_changed, payload}, 500
      assert payload.position_seconds >= 45.0
    end
  end

  describe "play_item/3" do
    test "plays a specific playlist item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item1} = add_playlist_item(playlist.id, %{position: 0, title: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, title: "Second"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Play the second item
      assert :ok = MediaPlayerServer.play_item(room_id, item2.id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.current_item.id == item2.id
      assert state.state == :playing
      # Position should be near 0 (within a small delta due to timing)
      assert_in_delta state.position_seconds, 0.0, 0.1
    end

    test "returns error for non-existent item" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      fake_item_id = Ecto.UUID.generate()
      result = MediaPlayerServer.play_item(room_id, fake_item_id)

      assert result == {:error, :item_not_found}
    end
  end

  describe "next/2" do
    test "advances to next item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_playlist_item(playlist.id, %{position: 0, title: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, title: "Second"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Play the first item
      MediaPlayerServer.play_item(room_id, item1.id)

      {:ok, state_before} = MediaPlayerServer.get_state(room_id)
      assert state_before.current_item.id == item1.id

      # Advance to next
      assert :ok = MediaPlayerServer.next(room_id)

      {:ok, state_after} = MediaPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item2.id
    end

    test "returns end_of_playlist when at last item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Only one item, so next should return end_of_playlist
      result = MediaPlayerServer.next(room_id)

      assert result == {:ok, :end_of_playlist}
    end
  end

  describe "previous/2" do
    test "goes back to previous item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_playlist_item(playlist.id, %{position: 0, title: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, title: "Second"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Play the second item
      MediaPlayerServer.play_item(room_id, item2.id)

      {:ok, state_before} = MediaPlayerServer.get_state(room_id)
      assert state_before.current_item.id == item2.id

      # Go back to previous
      assert :ok = MediaPlayerServer.previous(room_id)

      {:ok, state_after} = MediaPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item1.id
    end

    test "returns start_of_playlist when at first item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      result = MediaPlayerServer.previous(room_id)

      assert result == {:ok, :start_of_playlist}
    end
  end

  describe "controller management" do
    test "take_control assigns controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      user_id = Ecto.UUID.generate()
      user_name = "Test User"

      assert :ok = MediaPlayerServer.take_control(room_id, user_id, user_name)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.controller_user_id == user_id
      assert state.controller_user_name == user_name
    end

    test "release_control removes controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      user_id = Ecto.UUID.generate()
      user_name = "Test User"

      MediaPlayerServer.take_control(room_id, user_id, user_name)
      assert :ok = MediaPlayerServer.release_control(room_id, user_id)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert is_nil(state.controller_user_id)
      assert is_nil(state.controller_user_name)
    end

    test "release_control fails if not the controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      user_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      MediaPlayerServer.take_control(room_id, user_id, "User 1")

      result = MediaPlayerServer.release_control(room_id, other_user_id)

      assert result == {:error, :not_controller}
    end

    test "only controller can control playback when assigned" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      controller_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      MediaPlayerServer.take_control(room_id, controller_id, "Controller")

      # Controller can play
      assert :ok = MediaPlayerServer.play(room_id, controller_id)

      # Other user cannot pause
      result = MediaPlayerServer.pause(room_id, other_user_id)
      assert result == {:error, :not_controller}

      # Controller can pause
      assert :ok = MediaPlayerServer.pause(room_id, controller_id)
    end

    test "anyone can control when no controller is assigned" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      random_user_id = Ecto.UUID.generate()

      # Should work without a controller
      assert :ok = MediaPlayerServer.play(room_id, random_user_id)
      assert :ok = MediaPlayerServer.pause(room_id, random_user_id)
    end
  end

  describe "video_ended/1 (cast)" do
    test "advances to next item when video ends" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_playlist_item(playlist.id, %{position: 0, title: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, title: "Second"})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play_item(room_id, item1.id)

      # Simulate video ending
      MediaPlayerServer.video_ended(room_id)

      # Wait for cast to process
      Process.sleep(50)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.current_item.id == item2.id
      assert state.state == :playing
    end

    test "stops playback at end of playlist" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play_item(room_id, item.id)
      MediaPlayerServer.video_ended(room_id)

      Process.sleep(50)

      {:ok, state} = MediaPlayerServer.get_state(room_id)
      assert state.state == :stopped
    end
  end

  describe "item_added/2 (cast)" do
    test "auto-selects item when playlist was empty" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # Playlist is empty, no current item
      {:ok, state_before} = MediaPlayerServer.get_state(room_id)
      assert is_nil(state_before.current_item)

      # Add an item through the context
      {:ok, item} = add_playlist_item(playlist.id)

      # Notify the server
      MediaPlayerServer.item_added(room_id, item)

      Process.sleep(50)

      {:ok, state_after} = MediaPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item.id
    end

    test "does not change current item if one is already selected" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, first_item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      # First item should be auto-selected
      {:ok, state_before} = MediaPlayerServer.get_state(room_id)
      assert state_before.current_item.id == first_item.id

      # Add another item
      {:ok, second_item} = add_playlist_item(playlist.id, %{position: 1, title: "Second"})
      MediaPlayerServer.item_added(room_id, second_item)

      Process.sleep(50)

      # Should still be on the first item
      {:ok, state_after} = MediaPlayerServer.get_state(room_id)
      assert state_after.current_item.id == first_item.id
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts controller change" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      user_id = Ecto.UUID.generate()
      MediaPlayerServer.take_control(room_id, user_id, "Test User")

      assert_receive {:media_controller_changed, payload}, 500
      assert payload.controller_user_id == user_id
      assert payload.controller_user_name == "Test User"
    end

    test "broadcasts video change when playing new item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.play_item(room_id, item.id)

      assert_receive {:media_video_changed, payload}, 500
      assert payload.item.id == item.id
      assert payload.position_seconds == 0.0
    end
  end

  describe "heartbeat and sync" do
    test "heartbeat broadcasts position during playback" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

      MediaPlayerServer.play(room_id)

      # Wait for heartbeat (every 250ms)
      assert_receive {:media_state_changed, _payload}, 500
    end
  end

  describe "lobby mode" do
    test "starts in lobby mode" do
      on_exit(fn -> stop_media_player(:lobby) end)

      case MediaPlayerServer.start_link(room_id: :lobby, is_lobby: true) do
        {:ok, pid} -> assert is_pid(pid)
        {:error, {:already_started, pid}} -> assert is_pid(pid)
      end

      {:ok, state} = MediaPlayerServer.get_state(:lobby)
      assert is_map(state)
    end
  end

  describe "position calculation" do
    test "position advances while playing" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play(room_id)

      {:ok, state1} = MediaPlayerServer.get_state(room_id)
      pos1 = state1.position_seconds

      Process.sleep(200)

      {:ok, state2} = MediaPlayerServer.get_state(room_id)
      pos2 = state2.position_seconds

      # Position should have advanced
      assert pos2 > pos1
    end

    test "position is frozen while paused" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_media_player(room_id) end)

      {:ok, _pid} = start_media_player(room_id)

      MediaPlayerServer.play(room_id)
      Process.sleep(100)
      MediaPlayerServer.pause(room_id)

      {:ok, state1} = MediaPlayerServer.get_state(room_id)
      pos1 = state1.position_seconds

      Process.sleep(200)

      {:ok, state2} = MediaPlayerServer.get_state(room_id)
      pos2 = state2.position_seconds

      # Position should be the same (frozen)
      assert_in_delta pos1, pos2, 0.01
    end
  end
end
