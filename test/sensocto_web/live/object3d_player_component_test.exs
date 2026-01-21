defmodule SensoctoWeb.Live.Object3DPlayerComponentTest do
  @moduledoc """
  Integration tests for the Object3DPlayerComponent functionality.

  These tests verify the server-side behavior of the 3D object player
  without requiring browser automation or authentication.
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.Object3D
  alias Sensocto.Object3D.Object3DPlayerServer
  alias Sensocto.Object3D.Object3DPlaylist
  alias Sensocto.Object3D.Object3DPlaylistItem
  alias Sensocto.Sensors.Room
  alias Sensocto.Accounts.User

  @moduletag :integration
  @moduletag :object3d_player

  # Helper to create a test user
  defp create_test_user do
    email = "test_3d_#{System.unique_integer([:positive])}@example.com"

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
          name: "Test 3D Room #{System.unique_integer([:positive])}",
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

  defp add_test_object(playlist_id, attrs) do
    default_attrs = %{
      playlist_id: playlist_id,
      splat_url: "https://example.com/test.splat",
      name: "Test Object",
      description: "A test 3D object",
      position: 0
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %Object3DPlaylistItem{}
    |> Object3DPlaylistItem.changeset(merged_attrs)
    |> Sensocto.Repo.insert()
  end

  defp start_object3d_player(room_id) do
    case Object3DPlayerServer.start_link(room_id: room_id, is_lobby: false) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp stop_object3d_player(room_id) do
    case GenServer.whereis(Object3DPlayerServer.via_tuple(room_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  defp clear_playlist(playlist) do
    playlist.id
    |> Object3D.get_playlist_items()
    |> Enum.each(fn item -> Object3D.remove_from_playlist(item.id) end)
  end

  describe "3D player server state management" do
    test "initializes with default camera position" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      {:ok, state} = Object3DPlayerServer.get_state(room_id)

      assert state.camera_position == %{x: 0, y: 0, z: 5}
      assert state.camera_target == %{x: 0, y: 0, z: 0}
    end

    test "camera sync updates position" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Object3DPlayerServer.take_control(room_id, "test_user", "Test User")

      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 3.0, y: 2.0, z: 4.0},
        %{x: 0.0, y: 0.0, z: 0.0},
        "test_user"
      )

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert_in_delta state.camera_position.x, 3.0, 0.1
      assert_in_delta state.camera_position.y, 2.0, 0.1
      assert_in_delta state.camera_position.z, 4.0, 0.1
    end
  end

  describe "controller management" do
    test "take_control assigns controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.take_control(room_id, "test_user_123", "Test User")

      assert_receive {:object3d_controller_changed, %{controller_user_id: "test_user_123"}}, 2_000

      {:ok, state} = Object3DPlayerServer.get_state(room_id)
      assert state.controller_user_id == "test_user_123"
    end

    test "release_control clears controller" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.take_control(room_id, "test_user", "Test User")
      assert_receive {:object3d_controller_changed, _}, 2_000

      Object3DPlayerServer.release_control(room_id, "test_user")

      assert_receive {:object3d_controller_changed, %{controller_user_id: nil}}, 2_000
    end
  end

  describe "navigation" do
    test "next advances to next object" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_test_object(playlist.id, %{name: "Object 1", position: 0})

      {:ok, item2} =
        add_test_object(playlist.id, %{
          name: "Object 2",
          position: 1,
          splat_url: "https://example.com/obj2.splat"
        })

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      # Verify first item is selected
      {:ok, initial_state} = Object3DPlayerServer.get_state(room_id)
      assert initial_state.current_item.id == item1.id

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.next(room_id)

      assert_receive {:object3d_item_changed, %{item: current}}, 2_000
      assert current.id == item2.id

      clear_playlist(playlist)
    end

    test "previous goes to previous object" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, item1} = add_test_object(playlist.id, %{name: "Object 1", position: 0})

      {:ok, item2} =
        add_test_object(playlist.id, %{
          name: "Object 2",
          position: 1,
          splat_url: "https://example.com/obj2.splat"
        })

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      # Go to second object first using view_item
      Object3DPlayerServer.view_item(room_id, item2.id)
      Process.sleep(100)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.previous(room_id)

      assert_receive {:object3d_item_changed, %{item: current}}, 2_000
      assert current.id == item1.id

      clear_playlist(playlist)
    end

    test "view_item changes current object" do
      {:ok, room_id} = create_test_room()
      {:ok, playlist} = create_playlist_for_room(room_id)
      {:ok, _item1} = add_test_object(playlist.id, %{name: "Object 1", position: 0})

      {:ok, item2} =
        add_test_object(playlist.id, %{
          name: "Object 2",
          position: 1,
          splat_url: "https://example.com/obj2.splat"
        })

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.view_item(room_id, item2.id)

      assert_receive {:object3d_item_changed, %{item: current}}, 2_000
      assert current.id == item2.id

      clear_playlist(playlist)
    end
  end

  describe "PubSub synchronization" do
    test "camera sync is broadcast" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Object3DPlayerServer.take_control(room_id, "test_user", "Test User")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.sync_camera(
        room_id,
        %{x: 5.0, y: 3.0, z: 2.0},
        %{x: 0.0, y: 0.0, z: 0.0},
        "test_user"
      )

      assert_receive {:object3d_camera_synced, %{camera_position: pos}}, 2_000
      assert pos.x == 5.0
    end

    test "controller changes are broadcast" do
      {:ok, room_id} = create_test_room()

      on_exit(fn -> stop_object3d_player(room_id) end)

      {:ok, _pid} = start_object3d_player(room_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

      Object3DPlayerServer.take_control(room_id, "test_user", "Test User")

      assert_receive {:object3d_controller_changed,
                      %{
                        controller_user_id: "test_user",
                        controller_user_name: "Test User"
                      }},
                     2_000
    end
  end
end
