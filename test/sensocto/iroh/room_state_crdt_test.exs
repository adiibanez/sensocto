defmodule Sensocto.Iroh.RoomStateCRDTTest do
  @moduledoc """
  Tests for the RoomStateCRDT module.
  """
  use ExUnit.Case, async: false
  alias Sensocto.Iroh.RoomStateCRDT

  @moduletag :iroh
  @moduletag timeout: 120_000

  setup_all do
    # Use the existing RoomStateCRDT process started by the application supervisor
    # Don't try to stop/restart it - just wait for it to be ready
    pid =
      case GenServer.whereis(RoomStateCRDT) do
        nil ->
          # If not started by app, start it for tests
          {:ok, new_pid} = RoomStateCRDT.start_link([])
          new_pid

        existing_pid ->
          existing_pid
      end

    # Wait for initialization - the iroh node needs time to initialize
    wait_for_ready(pid, 30)

    {:ok, pid: pid}
  end

  defp wait_for_ready(pid, attempts) when attempts > 0 do
    if Process.alive?(pid) do
      Process.sleep(500)

      try do
        if RoomStateCRDT.ready?() do
          :ok
        else
          wait_for_ready(pid, attempts - 1)
        end
      catch
        :exit, _ -> wait_for_ready(pid, attempts - 1)
      end
    else
      raise "RoomStateCRDT process died during initialization"
    end
  end

  defp wait_for_ready(_pid, 0) do
    raise "RoomStateCRDT did not become ready in time"
  end

  describe "initialization" do
    test "starts and becomes ready", %{pid: pid} do
      assert Process.alive?(pid)
      assert RoomStateCRDT.ready?()
    end
  end

  describe "room document management" do
    test "creates a new room document" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"

      {:ok, doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      assert is_binary(doc_id)
      assert byte_size(doc_id) > 0

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "returns existing document for same room" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"

      {:ok, doc_id1} = RoomStateCRDT.get_or_create_room_doc(room_id)
      {:ok, doc_id2} = RoomStateCRDT.get_or_create_room_doc(room_id)

      assert doc_id1 == doc_id2

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "gets room state as map" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)
      {:ok, state} = RoomStateCRDT.get_room_state(room_id)

      assert is_map(state)
      assert state["room_id"] == room_id
      assert is_map(state["media"])
      assert is_map(state["object_3d"])
      assert is_map(state["participants"])

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "deletes room document" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)
      :ok = RoomStateCRDT.delete_room_doc(room_id)

      # Getting state should fail now
      assert {:error, :doc_not_found} = RoomStateCRDT.get_room_state(room_id)
    end
  end

  describe "media playback operations" do
    test "sets and gets media URL" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-123"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      :ok = RoomStateCRDT.set_media_url(room_id, "https://youtube.com/watch?v=abc", user_id)

      {:ok, media} = RoomStateCRDT.get_media_state(room_id)

      assert media["current_url"] == "https://youtube.com/watch?v=abc"
      assert media["updated_by"] == user_id

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "sets and gets media position" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-123"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      :ok = RoomStateCRDT.set_media_position(room_id, 12345, user_id)

      {:ok, media} = RoomStateCRDT.get_media_state(room_id)

      assert media["position_ms"] == 12345

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "sets and gets media playing state" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-123"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      :ok = RoomStateCRDT.set_media_playing(room_id, true, user_id)

      {:ok, media} = RoomStateCRDT.get_media_state(room_id)

      assert media["is_playing"] == true

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end
  end

  describe "3D object operations" do
    test "sets and gets 3D object URL" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-123"
      splat_url = "https://example.com/model.ply"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      :ok = RoomStateCRDT.set_object3d_url(room_id, splat_url, user_id)

      {:ok, object3d} = RoomStateCRDT.get_object3d_state(room_id)

      assert object3d["splat_url"] == splat_url
      assert object3d["updated_by"] == user_id

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "sets and gets 3D camera position" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-123"
      position = %{x: 1.0, y: 2.0, z: 3.0}
      target = %{x: 0.0, y: 0.0, z: 0.0}

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      :ok = RoomStateCRDT.set_object3d_camera(room_id, position, target, user_id)

      {:ok, object3d} = RoomStateCRDT.get_object3d_state(room_id)

      assert object3d["camera_position"]["x"] == 1.0
      assert object3d["camera_position"]["y"] == 2.0
      assert object3d["camera_position"]["z"] == 3.0
      assert object3d["camera_target"]["x"] == 0.0

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end
  end

  describe "participant presence operations" do
    test "updates participant presence" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-456"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      presence_data = %{
        "name" => "Alice",
        "cursor_x" => 100,
        "cursor_y" => 200
      }

      :ok = RoomStateCRDT.update_participant_presence(room_id, user_id, presence_data)

      {:ok, participants} = RoomStateCRDT.get_participants(room_id)

      assert is_map(participants[user_id])
      assert participants[user_id]["name"] == "Alice"
      assert participants[user_id]["cursor_x"] == 100
      assert participants[user_id]["last_seen"] != nil

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end

    test "removes participant" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"
      user_id = "user-789"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      # Add participant
      :ok = RoomStateCRDT.update_participant_presence(room_id, user_id, %{"name" => "Bob"})

      # Verify added
      {:ok, participants1} = RoomStateCRDT.get_participants(room_id)
      assert participants1[user_id] != nil

      # Remove participant
      :ok = RoomStateCRDT.remove_participant(room_id, user_id)

      # Verify removed
      {:ok, participants2} = RoomStateCRDT.get_participants(room_id)
      assert participants2[user_id] == nil

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end
  end

  describe "export and sync operations" do
    test "exports room document" do
      room_id = "test-room-#{:rand.uniform(1_000_000)}"

      {:ok, _doc_id} = RoomStateCRDT.get_or_create_room_doc(room_id)

      # Add some data
      :ok = RoomStateCRDT.set_media_url(room_id, "https://test.com/video", "user-1")

      {:ok, doc_bytes} = RoomStateCRDT.export_room_doc(room_id)

      assert is_binary(doc_bytes)
      assert byte_size(doc_bytes) > 0

      # Cleanup
      RoomStateCRDT.delete_room_doc(room_id)
    end
  end
end
