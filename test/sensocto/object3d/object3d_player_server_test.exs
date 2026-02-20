defmodule Sensocto.Object3D.Object3DPlayerServerTest do
  @moduledoc """
  Tests for Sensocto.Object3D.Object3DPlayerServer GenServer.

  This GenServer manages synchronized 3D object viewing state for rooms and the lobby.
  It coordinates current object, camera position, and control across all connected clients.
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.Object3D
  alias Sensocto.Object3D.Object3DPlayerServer
  alias Sensocto.Object3D.Object3DPlaylist
  alias Sensocto.Object3D.Object3DPlaylistItem
  alias Sensocto.Sensors.Room
  alias Sensocto.Accounts.User

  @moduletag :integration

  # Helper to create a test user
  defp create_test_user do
    email = "test_#{System.unique_integer([:positive])}@example.com"

    Ash.Seed.seed!(User, %{
      email: email,
      confirmed_at: DateTime.utc_now()
    })
  end

  # Helper to create a test room with a unique ID
  defp create_test_room do
    user = create_test_user()

    room =
      Room
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Test Room #{System.unique_integer([:positive])}",
          is_public: true,
          owner_id: user.id
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, room.id}
  end

  # Helper to create a playlist for a room
  defp create_playlist_for_room(room_id) do
    %Object3DPlaylist{}
    |> Object3DPlaylist.room_changeset(%{room_id: room_id, name: "Test 3D Playlist"})
    |> Sensocto.Repo.insert()
  end

  # Helper to add a playlist item
  defp add_playlist_item(playlist_id, attrs \\ %{}) do
    default_attrs = %{
      playlist_id: playlist_id,
      splat_url: "https://example.com/test-object.splat",
      name: "Test 3D Object",
      description: "A test Gaussian splat",
      thumbnail_url: "https://example.com/thumb.jpg",
      camera_preset_position: nil,
      camera_preset_target: nil,
      position: 0
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %Object3DPlaylistItem{}
    |> Object3DPlaylistItem.changeset(merged_attrs)
    |> Sensocto.Repo.insert()
  end

  # Helper to start a 3D player server for a room
  defp start_player(room_id) do
    case Object3DPlayerServer.start_link(room_id: room_id, is_lobby: false) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # Helper to stop a 3D player server
  defp stop_player(room_id) do
    case GenServer.whereis(Object3DPlayerServer.via_tuple(room_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  describe "start_link/1" do
    test "starts a 3D player server for a room" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, pid} = start_player(room_id)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "creates a playlist if none exists" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      # No playlist exists yet
      assert is_nil(Object3D.get_room_playlist(room_id))

      # Start the server
      {:ok, _pid} = start_player(room_id)

      # Now a playlist should exist
      playlist = Object3D.get_room_playlist(room_id)
      assert not is_nil(playlist)
      assert playlist.room_id == room_id
    end

    test "uses existing playlist if one exists" do
      {:ok, room_id} = create_test_room()
      {:ok, existing_playlist} = create_playlist_for_room(room_id)

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert length(state.playlist_items) == 0

      playlist = Object3D.get_room_playlist(room_id)
      assert playlist.id == existing_playlist.id
    end

    test "initializes with default camera position" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)

      assert state.camera_position == %{x: 0, y: 0, z: 5}
      assert state.camera_target == %{x: 0, y: 0, z: 0}
    end
  end

  describe "get_state/1" do
    test "returns current player state" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)

      assert Map.has_key?(state, :current_item)
      assert Map.has_key?(state, :playlist_items)
      assert Map.has_key?(state, :controller_user_id)
      assert Map.has_key?(state, :controller_user_name)
      assert Map.has_key?(state, :camera_position)
      assert Map.has_key?(state, :camera_target)
    end

    test "returns error when server not found" do
      non_existent_room_id = Ecto.UUID.generate()

      result = Object3DPlayerServer.get_state(non_existent_room_id)

      assert result == {:error, :not_found}
    end

    test "auto-selects first playlist item if none selected" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)

      assert state.current_item != nil
      assert state.current_item.id == item.id
    end
  end

  describe "view_item/3" do
    test "views a specific playlist item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item1} = add_playlist_item(playlist.id, %{position: 0, name: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, name: "Second"})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      # View the second item
      assert :ok = Object3DPlayerServer.view_item(room_id, item2.id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert state.current_item.id == item2.id
    end

    test "returns error for non-existent item" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      fake_item_id = Ecto.UUID.generate()
      result = Object3DPlayerServer.view_item(room_id, fake_item_id)

      assert result == {:error, :item_not_found}
    end

    test "broadcasts item change" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.view_item(room_id, item.id)

      assert_receive {:object3d_item_changed, payload}, 500
      assert payload.item.id == item.id
    end
  end

  describe "next/2" do
    test "advances to next item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_playlist_item(playlist.id, %{position: 0, name: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, name: "Second"})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      Object3DPlayerServer.view_item(room_id, item1.id)

      {:ok, state_before} = Object3DPlayerServer.get_state(room_id)
      assert state_before.current_item.id == item1.id

      assert :ok = Object3DPlayerServer.next(room_id)

      {:ok, state_after} = Object3DPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item2.id
    end

    test "returns end_of_playlist when at last item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      result = Object3DPlayerServer.next(room_id)

      assert result == {:ok, :end_of_playlist}
    end
  end

  describe "previous/2" do
    test "goes back to previous item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_playlist_item(playlist.id, %{position: 0, name: "First"})
      {:ok, item2} = add_playlist_item(playlist.id, %{position: 1, name: "Second"})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      Object3DPlayerServer.view_item(room_id, item2.id)

      {:ok, state_before} = Object3DPlayerServer.get_state(room_id)
      assert state_before.current_item.id == item2.id

      assert :ok = Object3DPlayerServer.previous(room_id)

      {:ok, state_after} = Object3DPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item1.id
    end

    test "returns start_of_playlist when at first item" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      result = Object3DPlayerServer.previous(room_id)

      assert result == {:ok, :start_of_playlist}
    end
  end

  describe "controller management" do
    test "take_control assigns controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      user_id = Ecto.UUID.generate()
      user_name = "Test User"

      assert :ok = Object3DPlayerServer.take_control(room_id, user_id, user_name)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert state.controller_user_id == user_id
      assert state.controller_user_name == user_name
    end

    test "release_control removes controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      user_id = Ecto.UUID.generate()
      user_name = "Test User"

      Object3DPlayerServer.take_control(room_id, user_id, user_name)
      assert :ok = Object3DPlayerServer.release_control(room_id, user_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert is_nil(state.controller_user_id)
      assert is_nil(state.controller_user_name)
    end

    test "release_control fails if not the controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      user_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      Object3DPlayerServer.take_control(room_id, user_id, "User 1")

      result = Object3DPlayerServer.release_control(room_id, other_user_id)

      assert result == {:error, :not_controller}
    end

    test "broadcasts controller change" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()
      Object3DPlayerServer.take_control(room_id, user_id, "Test User")

      assert_receive {:object3d_controller_changed, payload}, 500
      assert payload.controller_user_id == user_id
      assert payload.controller_user_name == "Test User"
    end
  end

  describe "sync_camera/4 (cast)" do
    test "syncs camera position from controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      user_id = Ecto.UUID.generate()
      Object3DPlayerServer.take_control(room_id, user_id, "Controller")

      new_position = %{x: 5.0, y: 10.0, z: 15.0}
      new_target = %{x: 1.0, y: 1.0, z: 1.0}

      Object3DPlayerServer.sync_camera(room_id, new_position, new_target, user_id)

      Process.sleep(50)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert state.camera_position == new_position
      assert state.camera_target == new_target
    end

    test "ignores camera sync from non-controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      controller_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      Object3DPlayerServer.take_control(room_id, controller_id, "Controller")

      {:ok, state_before} = Object3DPlayerServer.get_state(room_id)

      # Non-controller tries to sync camera
      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 100, y: 100, z: 100},
        %{x: 50, y: 50, z: 50},
        other_user_id
      )

      Process.sleep(50)

      {:ok, state_after} = Object3DPlayerServer.get_state(room_id)

      # Camera should not have changed
      assert state_after.camera_position == state_before.camera_position
    end

    test "broadcasts camera sync event" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()
      Object3DPlayerServer.take_control(room_id, user_id, "Controller")

      # Clear previous messages
      flush_messages()

      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 5, y: 10, z: 15},
        %{x: 1, y: 1, z: 1},
        user_id
      )

      assert_receive {:object3d_camera_synced, payload}, 500
      assert payload.camera_position == %{x: 5, y: 10, z: 15}
      assert payload.is_active == true
    end
  end

  describe "item_added/2 (cast)" do
    test "auto-selects item when playlist was empty" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      # Playlist is empty, no current item
      {:ok, state_before} = Object3DPlayerServer.get_state(room_id)
      assert is_nil(state_before.current_item)

      # Add an item
      {:ok, item} = add_playlist_item(playlist.id)

      # Notify the server
      Object3DPlayerServer.item_added(room_id, item)

      Process.sleep(50)

      {:ok, state_after} = Object3DPlayerServer.get_state(room_id)
      assert state_after.current_item.id == item.id
    end

    test "does not change current item if one is already selected" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, first_item} = add_playlist_item(playlist.id, %{position: 0})

      on_exit(fn -> stop_player(room_id) end)

      {:ok, _pid} = start_player(room_id)

      # First item should be auto-selected
      {:ok, state_before} = Object3DPlayerServer.get_state(room_id)
      assert state_before.current_item.id == first_item.id

      # Add another item
      {:ok, second_item} = add_playlist_item(playlist.id, %{position: 1, name: "Second"})
      Object3DPlayerServer.item_added(room_id, second_item)

      Process.sleep(50)

      # Should still be on the first item
      {:ok, state_after} = Object3DPlayerServer.get_state(room_id)
      assert state_after.current_item.id == first_item.id
    end
  end

  describe "lobby mode" do
    test "starts in lobby mode" do
      on_exit(fn -> stop_player(:lobby) end)

      case Object3DPlayerServer.start_link(room_id: :lobby, is_lobby: true) do
        {:ok, pid} -> assert is_pid(pid)
        {:error, {:already_started, pid}} -> assert is_pid(pid)
      end

      {:ok, state} = Object3DPlayerServer.get_state(:lobby)
      assert is_map(state)
    end
  end

  describe "multi-tab sync (socket_id filtering)" do
    test "take_control with socket_id is reflected in controller_changed broadcast" do
      {:ok, room_id} = create_test_room()
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()
      socket_id = "phx-tab-123"

      assert :ok = Object3DPlayerServer.take_control(room_id, user_id, "User", socket_id)

      assert_receive {:object3d_controller_changed, payload}, 500
      assert payload.controller_socket_id == socket_id
      assert payload.controller_user_id == user_id
    end

    test "take_control without socket_id broadcasts nil socket_id" do
      {:ok, room_id} = create_test_room()
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()

      assert :ok = Object3DPlayerServer.take_control(room_id, user_id, "User")

      assert_receive {:object3d_controller_changed, payload}, 500
      assert is_nil(payload.controller_socket_id)
    end

    test "camera sync broadcast includes controller_socket_id" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()
      socket_id = "phx-tab-456"

      Object3DPlayerServer.take_control(room_id, user_id, "Controller", socket_id)

      flush_messages()

      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 1, y: 2, z: 3},
        %{x: 0, y: 0, z: 0},
        user_id
      )

      assert_receive {:object3d_camera_synced, payload}, 500
      assert payload.controller_socket_id == socket_id
    end

    test "release_control broadcasts nil socket_id" do
      {:ok, room_id} = create_test_room()
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()
      socket_id = "phx-tab-abc"

      Object3DPlayerServer.take_control(room_id, user_id, "User", socket_id)
      flush_messages()

      Object3DPlayerServer.release_control(room_id, user_id)

      assert_receive {:object3d_controller_changed, payload}, 500
      assert is_nil(payload.controller_socket_id)
      assert is_nil(payload.controller_user_id)
    end

    test "request_control creates pending request" do
      {:ok, room_id} = create_test_room()
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      user1_id = Ecto.UUID.generate()
      Object3DPlayerServer.take_control(room_id, user1_id, "User1", "tab-1")

      user2_id = Ecto.UUID.generate()
      result = Object3DPlayerServer.request_control(room_id, user2_id, "User2", "tab-2")

      assert result == {:ok, :request_pending}
    end

    test "retaking control from different tab updates socket_id in broadcast" do
      {:ok, room_id} = create_test_room()
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      user_id = Ecto.UUID.generate()

      # Take control from tab 1
      Object3DPlayerServer.take_control(room_id, user_id, "User", "tab-1")
      assert_receive {:object3d_controller_changed, payload1}, 500
      assert payload1.controller_socket_id == "tab-1"

      # Same user takes control from tab 2
      Object3DPlayerServer.take_control(room_id, user_id, "User", "tab-2")
      assert_receive {:object3d_controller_changed, payload2}, 500
      assert payload2.controller_socket_id == "tab-2"
    end

    test "camera sync from different tabs only works for controller" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item} = add_playlist_item(playlist.id)
      on_exit(fn -> stop_player(room_id) end)
      {:ok, _pid} = start_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      controller_id = Ecto.UUID.generate()
      other_id = Ecto.UUID.generate()

      Object3DPlayerServer.take_control(room_id, controller_id, "Controller", "tab-ctrl")
      flush_messages()

      # Non-controller sync should be ignored (no broadcast)
      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 99, y: 99, z: 99},
        %{x: 0, y: 0, z: 0},
        other_id
      )

      refute_receive {:object3d_camera_synced, _}, 100

      # Controller sync should broadcast with socket_id
      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 1, y: 2, z: 3},
        %{x: 0, y: 0, z: 0},
        controller_id
      )

      assert_receive {:object3d_camera_synced, payload}, 500
      assert payload.controller_socket_id == "tab-ctrl"
    end
  end

  # Helper to flush mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
