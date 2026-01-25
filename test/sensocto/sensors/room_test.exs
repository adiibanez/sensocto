defmodule Sensocto.Sensors.RoomTest do
  @moduledoc """
  Tests for the Room Ash resource.
  """
  use Sensocto.DataCase, async: true

  alias Sensocto.Sensors.Room
  alias Sensocto.Accounts.User

  # Helper to create a test user
  defp create_user(attrs \\ %{}) do
    default_attrs = %{
      email: "test_#{System.unique_integer([:positive])}@example.com",
      confirmed_at: DateTime.utc_now()
    }

    Ash.Seed.seed!(User, Map.merge(default_attrs, attrs))
  end

  # Helper to create a room with an owner
  defp create_room(owner, attrs \\ %{}) do
    Room
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{name: "Test Room", owner_id: owner.id}, attrs)
    )
    |> Ash.create()
  end

  describe "create action" do
    test "creates room with valid attributes" do
      owner = create_user()

      assert {:ok, room} = create_room(owner, %{name: "Test Room"})

      assert room.name == "Test Room"
      assert room.owner_id == owner.id
      assert room.is_public == true
      assert room.is_persisted == true
    end

    test "generates unique join code on create" do
      owner = create_user()

      {:ok, room1} = create_room(owner, %{name: "Room 1"})
      {:ok, room2} = create_room(owner, %{name: "Room 2"})

      assert room1.join_code != nil
      assert room2.join_code != nil
      assert room1.join_code != room2.join_code
      assert String.length(room1.join_code) == 8
    end

    test "validates required name field" do
      owner = create_user()

      assert {:error, changeset} =
               Room
               |> Ash.Changeset.for_create(:create, %{owner_id: owner.id})
               |> Ash.create()

      assert changeset.errors != []
    end

    test "creates room with optional description" do
      owner = create_user()

      {:ok, room} =
        create_room(owner, %{name: "Room with Desc", description: "A test room for sensors"})

      assert room.description == "A test room for sensors"
    end

    test "creates private room" do
      owner = create_user()

      {:ok, room} = create_room(owner, %{name: "Private Room", is_public: false})

      assert room.is_public == false
    end

    test "creates non-persisted (temporary) room" do
      owner = create_user()

      {:ok, room} = create_room(owner, %{name: "Temp Room", is_persisted: false})

      assert room.is_persisted == false
    end
  end

  describe "read actions" do
    test "by_id returns room when found" do
      owner = create_user()
      {:ok, created_room} = create_room(owner, %{name: "Find Me"})

      {:ok, found_room} =
        Room
        |> Ash.Query.for_read(:by_id, %{id: created_room.id})
        |> Ash.read_one()

      assert found_room.id == created_room.id
      assert found_room.name == "Find Me"
    end

    test "by_join_code returns room when found" do
      owner = create_user()
      {:ok, room} = create_room(owner, %{name: "Join Me"})

      {:ok, found_room} =
        Room
        |> Ash.Query.for_read(:by_join_code, %{code: room.join_code})
        |> Ash.read_one()

      assert found_room.id == room.id
    end

    test "public_rooms returns only public persisted rooms" do
      owner = create_user()

      # Create a public room
      {:ok, public_room} = create_room(owner, %{name: "Public Room", is_public: true})

      # Create a private room
      {:ok, _private_room} = create_room(owner, %{name: "Private Room", is_public: false})

      {:ok, public_rooms} =
        Room
        |> Ash.Query.for_read(:public_rooms)
        |> Ash.read()

      room_ids = Enum.map(public_rooms, & &1.id)
      assert public_room.id in room_ids
    end

    test "user_owned_rooms returns rooms owned by user" do
      owner1 = create_user()
      owner2 = create_user()

      {:ok, room1} = create_room(owner1, %{name: "Owner1 Room"})
      {:ok, _room2} = create_room(owner2, %{name: "Owner2 Room"})

      {:ok, owned_rooms} =
        Room
        |> Ash.Query.for_read(:user_owned_rooms, %{user_id: owner1.id})
        |> Ash.read()

      assert length(owned_rooms) == 1
      assert hd(owned_rooms).id == room1.id
    end
  end

  describe "update actions" do
    test "update changes room attributes" do
      owner = create_user()
      {:ok, room} = create_room(owner, %{name: "Original Name"})

      {:ok, updated_room} =
        room
        |> Ash.Changeset.for_update(:update, %{name: "New Name", description: "Updated desc"})
        |> Ash.update()

      assert updated_room.name == "New Name"
      assert updated_room.description == "Updated desc"
    end

    test "regenerate_join_code creates new code" do
      owner = create_user()
      {:ok, room} = create_room(owner, %{name: "Code Room"})
      old_code = room.join_code

      {:ok, updated_room} =
        room
        |> Ash.Changeset.for_update(:regenerate_join_code, %{})
        |> Ash.update()

      assert updated_room.join_code != old_code
      assert String.length(updated_room.join_code) == 8
    end
  end

  describe "destroy action" do
    test "destroys room" do
      owner = create_user()
      {:ok, room} = create_room(owner, %{name: "Delete Me"})
      room_id = room.id

      assert :ok = Ash.destroy(room)

      assert {:ok, nil} =
               Room
               |> Ash.Query.for_read(:by_id, %{id: room_id})
               |> Ash.read_one()
    end
  end

  describe "generate_join_code/1" do
    test "generates code of specified length" do
      code = Room.generate_join_code(10)
      assert String.length(code) == 10
    end

    test "generates alphanumeric uppercase codes" do
      code = Room.generate_join_code()
      assert code =~ ~r/^[A-Z0-9]+$/
    end

    test "excludes confusing characters (O, 0, I, 1)" do
      # The alphabet is ABCDEFGHJKLMNPQRSTUVWXYZ23456789
      # Excludes: O (looks like 0), I (looks like 1), 0, 1
      # Generate many codes and check none contain confusing chars
      codes = for _ <- 1..100, do: Room.generate_join_code()

      for code <- codes do
        refute String.contains?(code, "O")
        refute String.contains?(code, "0")
        refute String.contains?(code, "I")
        refute String.contains?(code, "1")
      end
    end
  end

  describe "feature flags" do
    test "creates room with media playback enabled by default" do
      owner = create_user()
      {:ok, room} = create_room(owner, %{name: "Media Room"})

      assert room.media_playback_enabled == true
      assert room.calls_enabled == true
      assert room.object_3d_enabled == false
      assert room.skeleton_composite_enabled == false
    end

    test "creates room with custom feature flags" do
      owner = create_user()

      {:ok, room} =
        create_room(owner, %{
          name: "Custom Room",
          media_playback_enabled: false,
          calls_enabled: false,
          object_3d_enabled: true,
          skeleton_composite_enabled: true
        })

      assert room.media_playback_enabled == false
      assert room.calls_enabled == false
      assert room.object_3d_enabled == true
      assert room.skeleton_composite_enabled == true
    end
  end
end
