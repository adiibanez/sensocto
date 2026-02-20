defmodule Sensocto.RoomServerTest do
  use Sensocto.DataCase, async: false

  alias Sensocto.RoomServer

  @moduletag :integration

  defp room_opts(overrides) do
    room_id = Keyword.get(overrides, :id, Ecto.UUID.generate())
    owner_id = Keyword.get(overrides, :owner_id, Ecto.UUID.generate())

    defaults = [
      id: room_id,
      owner_id: owner_id,
      name: "Test Room #{System.unique_integer([:positive])}"
    ]

    Keyword.merge(defaults, overrides)
  end

  defp start_room(overrides \\ []) do
    opts = room_opts(overrides)
    room_id = Keyword.fetch!(opts, :id)

    {:ok, pid} = RoomServer.start_link(opts)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end)

    {room_id, pid, opts}
  end

  describe "lifecycle" do
    test "starts and registers with Horde" do
      {room_id, pid, _opts} = start_room()

      assert Process.alive?(pid)
      {:ok, state} = RoomServer.get_state(room_id)
      assert state.id == room_id
    end

    test "initializes with owner as member" do
      owner_id = Ecto.UUID.generate()
      {room_id, _pid, _opts} = start_room(owner_id: owner_id)

      {:ok, state} = RoomServer.get_state(room_id)
      assert state.members == %{owner_id => :owner}
    end

    test "generates a join code" do
      {room_id, _pid, _opts} = start_room()

      {:ok, state} = RoomServer.get_state(room_id)
      assert is_binary(state.join_code)
      assert String.length(state.join_code) == 8
    end

    test "accepts custom join code" do
      {room_id, _pid, _opts} = start_room(join_code: "TESTCODE")

      {:ok, state} = RoomServer.get_state(room_id)
      assert state.join_code == "TESTCODE"
    end

    test "expires after configured timeout" do
      {room_id, pid, _opts} = start_room(expiry_ms: 50)

      assert Process.alive?(pid)
      Process.sleep(100)
      refute Process.alive?(pid)

      assert {:error, :not_found} = RoomServer.get_state(room_id)
    end

    test "broadcasts room_closed on termination" do
      {room_id, pid, _opts} = start_room()

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
      GenServer.stop(pid, :normal)

      assert_receive {:room_update, :room_closed}, 500
    end
  end

  describe "get_state/1" do
    test "returns full state" do
      {room_id, _pid, _opts} = start_room()

      {:ok, state} = RoomServer.get_state(room_id)
      assert %RoomServer{} = state
      assert state.id == room_id
      assert %DateTime{} = state.created_at
      assert %DateTime{} = state.last_activity_at
    end

    test "returns error for nonexistent room" do
      assert {:error, :not_found} = RoomServer.get_state(Ecto.UUID.generate())
    end
  end

  describe "get_view_state/1" do
    test "returns serializable view state" do
      {room_id, _pid, _opts} = start_room()

      {:ok, view} = RoomServer.get_view_state(room_id)
      assert is_map(view)
      assert view.id == room_id
      assert view.member_count == 1
      assert view.sensor_count == 0
      assert view.sensor_ids == []
      assert view.is_persisted == false
    end
  end

  describe "member management" do
    test "adds a member" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      assert :ok = RoomServer.add_member(room_id, user_id)

      {:ok, state} = RoomServer.get_state(room_id)
      assert Map.has_key?(state.members, user_id)
      assert state.members[user_id] == :member
    end

    test "adds a member with custom role" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      assert :ok = RoomServer.add_member(room_id, user_id, :admin)

      {:ok, state} = RoomServer.get_state(room_id)
      assert state.members[user_id] == :admin
    end

    test "rejects duplicate member" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      :ok = RoomServer.add_member(room_id, user_id)
      assert {:error, :already_member} = RoomServer.add_member(room_id, user_id)
    end

    test "removes a member" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      :ok = RoomServer.add_member(room_id, user_id)
      assert :ok = RoomServer.remove_member(room_id, user_id)

      {:ok, state} = RoomServer.get_state(room_id)
      refute Map.has_key?(state.members, user_id)
    end

    test "cannot remove owner" do
      owner_id = Ecto.UUID.generate()
      {room_id, _pid, _opts} = start_room(owner_id: owner_id)

      assert {:error, :cannot_remove_owner} = RoomServer.remove_member(room_id, owner_id)
    end

    test "broadcasts member_joined" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
      RoomServer.add_member(room_id, user_id)

      assert_receive {:room_update, {:member_joined, ^user_id, :member}}, 500
    end

    test "broadcasts member_left" do
      {room_id, _pid, _opts} = start_room()
      user_id = Ecto.UUID.generate()

      :ok = RoomServer.add_member(room_id, user_id)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
      RoomServer.remove_member(room_id, user_id)

      assert_receive {:room_update, {:member_left, ^user_id}}, 500
    end
  end

  describe "is_member?/2 and get_member_role/2" do
    test "is_member? returns true for members" do
      owner_id = Ecto.UUID.generate()
      {room_id, _pid, _opts} = start_room(owner_id: owner_id)

      assert RoomServer.is_member?(room_id, owner_id)
      refute RoomServer.is_member?(room_id, Ecto.UUID.generate())
    end

    test "get_member_role returns correct role" do
      owner_id = Ecto.UUID.generate()
      {room_id, _pid, _opts} = start_room(owner_id: owner_id)

      assert RoomServer.get_member_role(room_id, owner_id) == :owner
      assert RoomServer.get_member_role(room_id, Ecto.UUID.generate()) == nil
    end
  end

  describe "sensor management" do
    test "adds a sensor" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      assert :ok = RoomServer.add_sensor(room_id, sensor_id)

      {:ok, state} = RoomServer.get_state(room_id)
      assert MapSet.member?(state.sensor_ids, sensor_id)
    end

    test "rejects duplicate sensor" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)
      assert {:error, :already_added} = RoomServer.add_sensor(room_id, sensor_id)
    end

    test "removes a sensor" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)
      assert :ok = RoomServer.remove_sensor(room_id, sensor_id)

      {:ok, state} = RoomServer.get_state(room_id)
      refute MapSet.member?(state.sensor_ids, sensor_id)
    end

    test "broadcasts sensor_added" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
      RoomServer.add_sensor(room_id, sensor_id)

      assert_receive {:room_update, {:sensor_added, ^sensor_id}}, 500
    end

    test "broadcasts sensor_removed" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
      RoomServer.remove_sensor(room_id, sensor_id)

      assert_receive {:room_update, {:sensor_removed, ^sensor_id}}, 500
    end
  end

  describe "sensor activity tracking" do
    test "updates sensor activity via cast" do
      {room_id, _pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)
      RoomServer.update_sensor_activity(room_id, sensor_id)

      Process.sleep(50)

      {:ok, state} = RoomServer.get_state(room_id)
      assert Map.has_key?(state.sensor_activity, sensor_id)
    end

    test "ignores activity for unknown sensors" do
      {room_id, _pid, _opts} = start_room()

      RoomServer.update_sensor_activity(room_id, "nonexistent_sensor")
      Process.sleep(50)

      {:ok, state} = RoomServer.get_state(room_id)
      assert state.sensor_activity == %{}
    end

    test "sensor_status returns correct status" do
      state = %RoomServer{
        sensor_activity: %{
          "active" => DateTime.utc_now(),
          "idle" => DateTime.add(DateTime.utc_now(), -30, :second),
          "inactive" => DateTime.add(DateTime.utc_now(), -120, :second)
        }
      }

      assert RoomServer.sensor_status(state, "active") == :active
      assert RoomServer.sensor_status(state, "idle") == :idle
      assert RoomServer.sensor_status(state, "inactive") == :inactive
      assert RoomServer.sensor_status(state, "unknown") == :inactive
    end
  end

  describe "measurement handling" do
    test "handles measurement messages and updates activity" do
      {room_id, pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")

      send(pid, {:measurement, %{sensor_id: sensor_id, value: 42}})
      assert_receive {:room_update, {:sensor_measurement, ^sensor_id}}, 500
    end

    test "handles measurements_batch messages" do
      {room_id, pid, _opts} = start_room()
      sensor_id = "sensor_#{System.unique_integer([:positive])}"

      :ok = RoomServer.add_sensor(room_id, sensor_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")

      send(pid, {:measurements_batch, {sensor_id, [%{value: 1}, %{value: 2}]}})
      assert_receive {:room_update, {:sensor_measurement, ^sensor_id}}, 500
    end

    test "ignores measurements for unknown sensors" do
      {room_id, pid, _opts} = start_room()

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")

      send(pid, {:measurement, %{sensor_id: "unknown", value: 42}})
      refute_receive {:room_update, {:sensor_measurement, _}}, 100
    end
  end
end
