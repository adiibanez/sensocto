defmodule Sensocto.RoomStoreTest do
  use ExUnit.Case, async: false

  alias Sensocto.RoomStore

  @owner_id "owner_#{:erlang.phash2(make_ref())}"

  setup do
    owner_id = "owner_#{System.unique_integer([:positive])}"
    user_id = "user_#{System.unique_integer([:positive])}"

    {:ok, owner_id: owner_id, user_id: user_id}
  end

  defp create_test_room(owner_id, attrs \\ %{}) do
    default = %{
      name: "Test Room #{System.unique_integer([:positive])}",
      is_public: true
    }

    RoomStore.create_room(Map.merge(default, attrs), owner_id)
  end

  describe "room CRUD" do
    test "creates a room with owner", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert room.name =~ "Test Room"
      assert room.owner_id == owner_id
      assert room.is_public == true
      assert %MapSet{} = room.sensor_ids
      assert MapSet.size(room.sensor_ids) == 0
      assert room.members == %{owner_id => :owner}
      assert is_binary(room.join_code)
      assert String.length(room.join_code) == 8
    end

    test "gets a room by ID", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:ok, fetched} = RoomStore.get_room(room.id)
      assert fetched.id == room.id
      assert fetched.name == room.name
    end

    test "returns error for non-existent room" do
      assert {:error, :not_found} = RoomStore.get_room("nonexistent-id")
    end

    test "gets a room by join code", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:ok, fetched} = RoomStore.get_room_by_code(room.join_code)
      assert fetched.id == room.id
    end

    test "returns error for non-existent join code" do
      assert {:error, :not_found} = RoomStore.get_room_by_code("NONEXIST")
    end

    test "updates room attributes", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      {:ok, updated} = RoomStore.update_room(room.id, %{name: "Updated Name", is_public: false})

      assert updated.name == "Updated Name"
      assert updated.is_public == false
      assert updated.id == room.id
    end

    test "update preserves unchanged fields", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id, %{description: "Original"})

      {:ok, updated} = RoomStore.update_room(room.id, %{name: "New Name"})

      assert updated.name == "New Name"
      assert updated.description == "Original"
    end

    test "deletes a room", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert :ok = RoomStore.delete_room(room.id)
      assert {:error, :not_found} = RoomStore.get_room(room.id)
    end

    test "delete removes join code mapping", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      join_code = room.join_code

      RoomStore.delete_room(room.id)

      assert {:error, :not_found} = RoomStore.get_room_by_code(join_code)
    end

    test "exists? returns true for existing room", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      assert RoomStore.exists?(room.id)
    end

    test "exists? returns false for non-existent room" do
      refute RoomStore.exists?("nonexistent-id")
    end

    test "count reflects room operations", %{owner_id: owner_id} do
      initial_count = RoomStore.count()

      {:ok, room} = create_test_room(owner_id)
      assert RoomStore.count() == initial_count + 1

      RoomStore.delete_room(room.id)
      assert RoomStore.count() == initial_count
    end
  end

  describe "member management" do
    test "owner is automatically a member", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert RoomStore.is_member?(room.id, owner_id)
      assert RoomStore.get_member_role(room.id, owner_id) == :owner
    end

    test "join room adds member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)

      {:ok, _updated} = RoomStore.join_room(room.id, user_id)

      assert RoomStore.is_member?(room.id, user_id)
      assert RoomStore.get_member_role(room.id, user_id) == :member
    end

    test "cannot join room twice", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)

      {:ok, _} = RoomStore.join_room(room.id, user_id)
      assert {:error, :already_member} = RoomStore.join_room(room.id, user_id)
    end

    test "leave room removes member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)

      assert :ok = RoomStore.leave_room(room.id, user_id)
      refute RoomStore.is_member?(room.id, user_id)
    end

    test "owner cannot leave room", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :owner_cannot_leave} = RoomStore.leave_room(room.id, owner_id)
    end

    test "list members returns all members with roles", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)

      {:ok, members} = RoomStore.list_members(room.id)

      assert length(members) == 2
      assert {owner_id, :owner} in members
      assert {user_id, :member} in members
    end
  end

  describe "role management" do
    test "promote member to admin", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)

      {:ok, _} = RoomStore.promote_to_admin(room.id, user_id)

      assert RoomStore.get_member_role(room.id, user_id) == :admin
    end

    test "cannot promote non-member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :not_a_member} = RoomStore.promote_to_admin(room.id, user_id)
    end

    test "cannot promote owner", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :cannot_change_owner} = RoomStore.promote_to_admin(room.id, owner_id)
    end

    test "cannot promote already-admin", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)
      {:ok, _} = RoomStore.promote_to_admin(room.id, user_id)

      assert {:error, :already_admin} = RoomStore.promote_to_admin(room.id, user_id)
    end

    test "demote admin to member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)
      {:ok, _} = RoomStore.promote_to_admin(room.id, user_id)

      {:ok, _} = RoomStore.demote_to_member(room.id, user_id)

      assert RoomStore.get_member_role(room.id, user_id) == :member
    end

    test "cannot demote owner", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :cannot_change_owner} = RoomStore.demote_to_member(room.id, owner_id)
    end

    test "cannot demote regular member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)

      assert {:error, :already_member} = RoomStore.demote_to_member(room.id, user_id)
    end
  end

  describe "kick member" do
    test "kicks a member from room", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room.id, user_id)

      {:ok, _} = RoomStore.kick_member(room.id, user_id)

      refute RoomStore.is_member?(room.id, user_id)
    end

    test "cannot kick owner", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :cannot_kick_owner} = RoomStore.kick_member(room.id, owner_id)
    end

    test "cannot kick non-member", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)

      assert {:error, :not_a_member} = RoomStore.kick_member(room.id, user_id)
    end
  end

  describe "sensor management" do
    test "adds sensor to room", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      assert :ok = RoomStore.add_sensor(room.id, sensor_id)

      {:ok, updated} = RoomStore.get_room(room.id)
      assert MapSet.member?(updated.sensor_ids, sensor_id)
    end

    test "removes sensor from room", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      RoomStore.add_sensor(room.id, sensor_id)
      assert :ok = RoomStore.remove_sensor(room.id, sensor_id)

      {:ok, updated} = RoomStore.get_room(room.id)
      refute MapSet.member?(updated.sensor_ids, sensor_id)
    end

    test "adding sensor to non-existent room returns error" do
      assert {:error, :not_found} = RoomStore.add_sensor("nonexistent", "sensor_1")
    end

    test "adding same sensor twice is idempotent (MapSet)", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      RoomStore.add_sensor(room.id, sensor_id)
      RoomStore.add_sensor(room.id, sensor_id)

      {:ok, updated} = RoomStore.get_room(room.id)
      assert MapSet.size(updated.sensor_ids) == 1
    end
  end

  describe "join code" do
    test "regenerates join code", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      old_code = room.join_code

      {:ok, new_code} = RoomStore.regenerate_join_code(room.id)

      assert new_code != old_code
      assert String.length(new_code) == 8

      # Old code should no longer work
      assert {:error, :not_found} = RoomStore.get_room_by_code(old_code)

      # New code should work
      assert {:ok, _} = RoomStore.get_room_by_code(new_code)
    end
  end

  describe "listing" do
    test "list_user_rooms returns rooms user is member of", %{
      owner_id: owner_id,
      user_id: user_id
    } do
      {:ok, room1} = create_test_room(owner_id)
      {:ok, room2} = create_test_room(owner_id)
      {:ok, _} = RoomStore.join_room(room1.id, user_id)

      rooms = RoomStore.list_user_rooms(user_id)
      room_ids = Enum.map(rooms, & &1.id)

      assert room1.id in room_ids
      refute room2.id in room_ids
    end

    test "list_user_rooms includes owned rooms", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)

      rooms = RoomStore.list_user_rooms(owner_id)
      room_ids = Enum.map(rooms, & &1.id)

      assert room.id in room_ids
    end

    test "list_public_rooms only returns public rooms", %{owner_id: owner_id} do
      {:ok, public_room} = create_test_room(owner_id, %{is_public: true})
      {:ok, private_room} = create_test_room(owner_id, %{is_public: false})

      public_rooms = RoomStore.list_public_rooms()
      public_ids = Enum.map(public_rooms, & &1.id)

      assert public_room.id in public_ids
      refute private_room.id in public_ids

      # Clean up
      RoomStore.delete_room(public_room.id)
      RoomStore.delete_room(private_room.id)
    end

    test "list_all_rooms returns all rooms", %{owner_id: owner_id} do
      {:ok, room1} = create_test_room(owner_id, %{is_public: true})
      {:ok, room2} = create_test_room(owner_id, %{is_public: false})

      all_rooms = RoomStore.list_all_rooms()
      all_ids = Enum.map(all_rooms, & &1.id)

      assert room1.id in all_ids
      assert room2.id in all_ids

      # Clean up
      RoomStore.delete_room(room1.id)
      RoomStore.delete_room(room2.id)
    end
  end

  describe "hydration" do
    test "ready? returns true (app is already hydrated)" do
      assert RoomStore.ready?()
    end

    test "hydrate_room inserts room data" do
      room_id = Ecto.UUID.generate()
      owner_id = "hydration_owner_#{System.unique_integer([:positive])}"

      room_data = %{
        id: room_id,
        name: "Hydrated Room",
        description: "From hydration",
        owner_id: owner_id,
        join_code: "HYD#{System.unique_integer([:positive])}",
        is_public: true,
        members: %{owner_id => :owner},
        sensor_ids: ["sensor_a", "sensor_b"],
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      assert :ok = RoomStore.hydrate_room(room_data)

      {:ok, room} = RoomStore.get_room(room_id)
      assert room.name == "Hydrated Room"
      assert %MapSet{} = room.sensor_ids
      assert MapSet.member?(room.sensor_ids, "sensor_a")
      assert MapSet.member?(room.sensor_ids, "sensor_b")

      # Clean up
      RoomStore.delete_room(room_id)
    end

    test "hydrate_room normalizes string member roles" do
      room_id = Ecto.UUID.generate()
      owner_id = "hydration_owner_#{System.unique_integer([:positive])}"

      room_data = %{
        "id" => room_id,
        "name" => "String Keys Room",
        "owner_id" => owner_id,
        "join_code" => "STR#{System.unique_integer([:positive])}",
        "members" => %{owner_id => "owner"},
        "sensor_ids" => []
      }

      assert :ok = RoomStore.hydrate_room(room_data)

      {:ok, room} = RoomStore.get_room(room_id)
      assert room.members[owner_id] == :owner

      # Clean up
      RoomStore.delete_room(room_id)
    end
  end

  describe "PubSub broadcasts" do
    test "room creation broadcasts to room topic", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room.id}")

      # Update triggers broadcast on the room topic
      RoomStore.update_room(room.id, %{name: "Broadcast Test"})

      assert_receive {:room_update, :room_updated}, 1000

      # Clean up
      RoomStore.delete_room(room.id)
    end

    test "room deletion broadcasts", %{owner_id: owner_id} do
      {:ok, room} = create_test_room(owner_id)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room.id}")

      RoomStore.delete_room(room.id)

      assert_receive {:room_update, :room_deleted}, 1000
    end

    test "member join broadcasts", %{owner_id: owner_id, user_id: user_id} do
      {:ok, room} = create_test_room(owner_id)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room.id}")

      RoomStore.join_room(room.id, user_id)

      assert_receive {:room_update, {:member_joined, ^user_id, :member}}, 1000

      # Clean up
      RoomStore.delete_room(room.id)
    end
  end
end
