defmodule Sensocto.Rooms do
  @moduledoc """
  Context module for room operations.
  Provides a unified interface for both persisted (database) and temporary (in-memory) rooms.
  """
  require Logger
  require Ash.Query

  alias Sensocto.Sensors.Room
  alias Sensocto.Sensors.RoomMembership
  alias Sensocto.Sensors.SensorConnection
  alias Sensocto.RoomsDynamicSupervisor
  alias Sensocto.RoomServer

  # ============================================================================
  # Room Creation
  # ============================================================================

  @doc """
  Creates a new room.
  If is_persisted is true, stores in database. Otherwise creates a temporary room.
  """
  def create_room(attrs, user) do
    is_persisted = Map.get(attrs, :is_persisted, true)

    if is_persisted do
      create_persisted_room(attrs, user)
    else
      create_temporary_room(attrs, user)
    end
  end

  defp create_persisted_room(attrs, user) do
    # Merge owner_id as an argument (required by the :create action)
    attrs_with_owner = Map.put(attrs, :owner_id, user.id)

    Room
    |> Ash.Changeset.for_create(:create, attrs_with_owner, actor: user)
    |> Ash.create()
    |> case do
      {:ok, room} ->
        create_owner_membership(room, user)
        {:ok, room}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_temporary_room(attrs, user) do
    opts = [
      id: Ecto.UUID.generate(),
      owner_id: user.id,
      name: Map.get(attrs, :name, "Untitled Room"),
      description: Map.get(attrs, :description),
      is_public: Map.get(attrs, :is_public, true),
      configuration: Map.get(attrs, :configuration, %{})
    ]

    case RoomsDynamicSupervisor.create_room(opts) do
      {:ok, room_id, _pid} ->
        {:ok, get_room!(room_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_owner_membership(room, user) do
    RoomMembership
    |> Ash.Changeset.for_create(:create, %{role: :owner}, actor: user)
    |> Ash.Changeset.force_change_attribute(:room_id, room.id)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.create()
  end

  # ============================================================================
  # Room Retrieval
  # ============================================================================

  @doc """
  Gets a room by ID. Works for both persisted and temporary rooms.
  Returns room struct or view state map.
  """
  def get_room(room_id) do
    case RoomsDynamicSupervisor.get_room_state(room_id) do
      {:ok, state} ->
        {:ok, state}

      {:error, :not_found} ->
        Room
        |> Ash.Query.for_read(:by_id, %{id: room_id})
        |> Ash.Query.load(:owner)
        |> Ash.read_one(authorize?: false)
    end
  end

  @doc """
  Gets a room by ID, raises if not found.
  """
  def get_room!(room_id) do
    case get_room(room_id) do
      {:ok, room} -> room
      {:error, _} -> raise "Room not found: #{room_id}"
    end
  end

  @doc """
  Gets a room by join code. Works for both persisted and temporary rooms.
  """
  def get_room_by_code(code) do
    case RoomsDynamicSupervisor.find_by_join_code(code) do
      {:ok, room_id} ->
        RoomsDynamicSupervisor.get_room_state(room_id)

      {:error, :not_found} ->
        Room
        |> Ash.Query.for_read(:by_join_code, %{code: code})
        |> Ash.read_one()
    end
  end

  @doc """
  Gets a room with its sensors' state for display.
  """
  def get_room_with_sensors(room_id) do
    case get_room(room_id) do
      {:ok, room} ->
        sensors = get_room_sensors_state(room)
        {:ok, Map.put(room, :sensors, sensors)}

      error ->
        error
    end
  end

  defp get_room_sensors_state(room) when is_map(room) do
    sensor_ids = get_sensor_ids(room)

    sensor_ids
    |> Enum.map(fn sensor_id ->
      case Sensocto.SimpleSensor.get_view_state(sensor_id) do
        nil -> nil
        state -> Map.put(state, :activity_status, get_sensor_activity_status(room, sensor_id))
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_sensor_ids(%{sensor_ids: sensor_ids}) when is_list(sensor_ids), do: sensor_ids
  defp get_sensor_ids(%{sensor_ids: sensor_ids}), do: MapSet.to_list(sensor_ids)

  defp get_sensor_ids(room) do
    case Map.get(room, :sensor_connections) do
      nil -> []
      connections when is_list(connections) -> Enum.map(connections, & &1.sensor_id)
      _ -> []
    end
  end

  defp get_sensor_activity_status(%{sensor_activity: activity}, sensor_id) when is_map(activity) do
    case Map.get(activity, sensor_id) do
      nil ->
        :inactive

      last_activity ->
        diff_ms = DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)

        cond do
          diff_ms < 5000 -> :active
          diff_ms < 60_000 -> :idle
          true -> :inactive
        end
    end
  end

  defp get_sensor_activity_status(_, _), do: :unknown

  # ============================================================================
  # Room Listing
  # ============================================================================

  @doc """
  Lists rooms for a specific user (owned + member of).
  Combines persisted and temporary rooms.
  """
  def list_user_rooms(user) do
    persisted_owned =
      Room
      |> Ash.Query.for_read(:user_owned_rooms, %{user_id: user.id})
      |> Ash.read!()
      |> Enum.map(&normalize_room/1)

    persisted_member =
      Room
      |> Ash.Query.for_read(:user_member_rooms, %{user_id: user.id})
      |> Ash.read!()
      |> Enum.map(&normalize_room/1)

    temporary = RoomsDynamicSupervisor.list_user_rooms(user.id)

    (persisted_owned ++ persisted_member ++ temporary)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Lists all public rooms.
  Combines persisted and temporary public rooms.
  """
  def list_public_rooms do
    persisted =
      Room
      |> Ash.Query.for_read(:public_rooms)
      |> Ash.read!()
      |> Enum.map(&normalize_room/1)

    temporary = RoomsDynamicSupervisor.list_public_rooms()

    (persisted ++ temporary)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  defp normalize_room(%Room{} = room) do
    %{
      id: room.id,
      name: room.name,
      description: room.description,
      owner_id: room.owner_id,
      join_code: room.join_code,
      is_public: room.is_public,
      is_persisted: true,
      configuration: room.configuration,
      inserted_at: room.inserted_at,
      updated_at: room.updated_at
    }
  end

  defp normalize_room(room) when is_map(room), do: room

  # ============================================================================
  # Room Membership
  # ============================================================================

  @doc """
  Joins a user to a room by join code.
  """
  def join_by_code(code, user) do
    case get_room_by_code(code) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, room} ->
        join_room(room, user)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Joins a user to a room.
  """
  def join_room(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      join_persisted_room(room_id, user)
    else
      join_temporary_room(room_id, user)
    end
  end

  defp join_persisted_room(room_id, user) do
    RoomMembership
    |> Ash.Changeset.for_create(:join, %{}, actor: user)
    |> Ash.Changeset.force_change_attribute(:room_id, room_id)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.create()
    |> case do
      {:ok, _membership} -> {:ok, get_room!(room_id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp join_temporary_room(room_id, user) do
    case RoomServer.add_member(room_id, user.id) do
      :ok -> {:ok, get_room!(room_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a user from a room.
  """
  def leave_room(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      leave_persisted_room(room_id, user)
    else
      RoomServer.remove_member(room_id, user.id)
    end
  end

  defp leave_persisted_room(room_id, user) do
    RoomMembership
    |> Ash.Query.filter(room_id: room_id, user_id: user.id)
    |> Ash.read_one!()
    |> case do
      nil -> {:error, :not_member}
      membership -> Ash.destroy(membership)
    end
  end

  @doc """
  Checks if a user is a member of a room.
  """
  def member?(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      RoomMembership
      |> Ash.Query.filter(room_id: room_id, user_id: user.id)
      |> Ash.exists?()
    else
      RoomServer.is_member?(room_id, user.id)
    end
  end

  @doc """
  Gets the user's role in a room.
  """
  def get_role(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      RoomMembership
      |> Ash.Query.filter(room_id: room_id, user_id: user.id)
      |> Ash.read_one!()
      |> case do
        nil -> nil
        membership -> membership.role
      end
    else
      RoomServer.get_member_role(room_id, user.id)
    end
  end

  @doc """
  Checks if user can manage the room (owner or admin).
  """
  def can_manage?(room, user) do
    role = get_role(room, user)
    role in [:owner, :admin]
  end

  @doc """
  Checks if user is the owner of the room.
  """
  def owner?(room, user) do
    Map.get(room, :owner_id) == user.id
  end

  # ============================================================================
  # Sensor Management
  # ============================================================================

  @doc """
  Adds a sensor to a room.
  """
  def add_sensor_to_room(room, sensor_id) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      add_sensor_to_persisted_room(room_id, sensor_id)
    else
      RoomServer.add_sensor(room_id, sensor_id)
    end
  end

  defp add_sensor_to_persisted_room(room_id, sensor_id) do
    SensorConnection
    |> Ash.Changeset.for_create(:create, %{
      id: Ecto.UUID.generate(),
      sensor_id: sensor_id,
      room_id: room_id,
      connected_at: DateTime.utc_now()
    })
    |> Ash.create()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a sensor from a room.
  """
  def remove_sensor_from_room(room, sensor_id) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      remove_sensor_from_persisted_room(room_id, sensor_id)
    else
      RoomServer.remove_sensor(room_id, sensor_id)
    end
  end

  defp remove_sensor_from_persisted_room(room_id, sensor_id) do
    SensorConnection
    |> Ash.Query.filter(room_id: room_id, sensor_id: sensor_id)
    |> Ash.read_one!()
    |> case do
      nil -> {:error, :not_found}
      connection -> Ash.destroy(connection)
    end
  end

  # ============================================================================
  # Room Management
  # ============================================================================

  @doc """
  Updates a room's settings.
  """
  def update_room(room, attrs, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      Room
      |> Ash.Query.for_read(:by_id, %{id: room_id})
      |> Ash.read_one!()
      |> Ash.Changeset.for_update(:update, attrs, actor: user)
      |> Ash.update()
      |> case do
        {:ok, updated_room} ->
          # Reload with owner relationship
          {:ok, Ash.load!(updated_room, :owner, authorize?: false)}

        error ->
          error
      end
    else
      {:error, :temporary_rooms_immutable}
    end
  end

  @doc """
  Regenerates the join code for a room.
  """
  def regenerate_join_code(room, user) when is_map(room) do
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      Room
      |> Ash.Query.for_read(:by_id, %{id: room.id})
      |> Ash.read_one!()
      |> Ash.Changeset.for_update(:regenerate_join_code, %{}, actor: user)
      |> Ash.update()
    else
      {:error, :temporary_rooms_code_fixed}
    end
  end

  @doc """
  Deletes a room.
  """
  def delete_room(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      Room
      |> Ash.Query.for_read(:by_id, %{id: room_id})
      |> Ash.read_one!()
      |> Ash.destroy(actor: user)
    else
      RoomsDynamicSupervisor.stop_room(room_id)
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Generates a share URL for a room.
  """
  def share_url(room) when is_map(room) do
    join_code = Map.get(room, :join_code)
    SensoctoWeb.Endpoint.url() <> "/rooms/join/#{join_code}"
  end

  @doc """
  Upgrades a temporary room to a persisted room.
  """
  def persist_room(room, user) when is_map(room) do
    is_persisted = Map.get(room, :is_persisted, true)

    if is_persisted do
      {:error, :already_persisted}
    else
      attrs = %{
        name: room.name,
        description: room.description,
        is_public: room.is_public,
        is_persisted: true,
        configuration: room.configuration
      }

      case create_persisted_room(attrs, user) do
        {:ok, new_room} ->
          sensor_ids = Map.get(room, :sensor_ids, [])

          Enum.each(sensor_ids, fn sensor_id ->
            add_sensor_to_room(new_room, sensor_id)
          end)

          RoomsDynamicSupervisor.stop_room(room.id)

          {:ok, new_room}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
