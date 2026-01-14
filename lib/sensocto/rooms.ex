defmodule Sensocto.Rooms do
  @moduledoc """
  Context module for room operations.
  Uses in-memory RoomStore with iroh docs sync for persistence.
  """
  require Logger

  alias Sensocto.RoomStore

  # ============================================================================
  # Room Creation
  # ============================================================================

  @doc """
  Creates a new room.
  All rooms are now stored in-memory with iroh docs persistence.
  """
  def create_room(attrs, user) do
    case RoomStore.create_room(attrs, user.id) do
      {:ok, room} ->
        {:ok, room}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Room Retrieval
  # ============================================================================

  @doc """
  Gets a room by ID.
  Returns {:ok, room} or {:error, :not_found}.
  """
  def get_room(room_id) do
    RoomStore.get_room(room_id)
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
  Gets a room by join code.
  """
  def get_room_by_code(code) do
    RoomStore.get_room_by_code(code)
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
    # Get sensor IDs from RoomStore (fast in-memory)
    room_sensor_ids = get_sensor_ids(room)

    room_sensor_ids
    |> Enum.map(fn sensor_id ->
      try do
        case Sensocto.SimpleSensor.get_view_state(sensor_id) do
          nil -> nil
          state -> Map.put(state, :activity_status, get_sensor_activity_status(room, sensor_id))
        end
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_sensor_ids(%{sensor_ids: sensor_ids}) when is_list(sensor_ids), do: sensor_ids
  defp get_sensor_ids(%{sensor_ids: %MapSet{} = sensor_ids}), do: MapSet.to_list(sensor_ids)
  defp get_sensor_ids(_), do: []

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
  """
  def list_user_rooms(user) do
    RoomStore.list_user_rooms(user.id)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Lists all public rooms.
  """
  def list_public_rooms do
    RoomStore.list_public_rooms()
    |> Enum.sort_by(& &1.name)
  end

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

    case RoomStore.join_room(room_id, user.id, :member) do
      {:ok, updated_room} ->
        {:ok, updated_room}

      {:error, :already_member} ->
        # Already a member, just return the room
        get_room(room_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Joins a user to a room with all their available sensors.
  Returns {:ok, room} on success.
  """
  def join_room_with_sensors(room, user) when is_map(room) do
    # First join using the RoomStore
    with {:ok, updated_room} <- join_room(room, user) do
      # Get all currently connected sensors for this user
      sensor_ids =
        Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
        |> Map.keys()

      # Add all sensors to the room
      Enum.each(sensor_ids, fn sensor_id ->
        RoomStore.add_sensor(room.id, sensor_id)
      end)

      {:ok, updated_room}
    end
  end

  @doc """
  Removes a user from a room.
  """
  def leave_room(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.leave_room(room_id, user.id)
  end

  @doc """
  Lists all users present in a room with their associated sensors.
  """
  def list_room_presences(room_id) do
    case RoomStore.get_room(room_id) do
      {:ok, room} ->
        # Return members with their sensor info
        room.members
        |> Enum.map(fn {user_id, role} ->
          %{user_id: user_id, role: role}
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Checks if a user is currently present in a room.
  """
  def user_in_room?(user_id, room_id) do
    RoomStore.is_member?(room_id, user_id)
  end

  @doc """
  Checks if a user is a member of a room.
  """
  def member?(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.is_member?(room_id, user.id)
  end

  @doc """
  Gets the user's role in a room.
  """
  def get_role(room, user) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.get_member_role(room_id, user.id)
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

  @doc """
  Checks if user is an admin of the room (not owner).
  """
  def admin?(room, user) do
    get_role(room, user) == :admin
  end

  @doc """
  Promotes a member to admin.
  Only owners can promote members.
  """
  def promote_to_admin(room, user_to_promote, acting_user) when is_map(room) do
    if owner?(room, acting_user) do
      room_id = Map.get(room, :id)
      RoomStore.promote_to_admin(room_id, user_to_promote.id)
    else
      {:error, :not_owner}
    end
  end

  @doc """
  Demotes an admin to member.
  Only owners can demote admins.
  """
  def demote_to_member(room, user_to_demote, acting_user) when is_map(room) do
    if owner?(room, acting_user) do
      room_id = Map.get(room, :id)
      RoomStore.demote_to_member(room_id, user_to_demote.id)
    else
      {:error, :not_owner}
    end
  end

  @doc """
  Kicks a user from a room.
  Owners can kick anyone except themselves.
  Admins can kick members but not other admins or the owner.
  """
  def kick_member(room, user_to_kick, acting_user) when is_map(room) do
    acting_role = get_role(room, acting_user)
    target_role = get_role(room, user_to_kick)

    cond do
      acting_user.id == user_to_kick.id ->
        {:error, :cannot_kick_self}

      acting_role == :owner ->
        # Owner can kick anyone except themselves
        room_id = Map.get(room, :id)
        RoomStore.kick_member(room_id, user_to_kick.id)

      acting_role == :admin and target_role == :member ->
        # Admin can only kick members
        room_id = Map.get(room, :id)
        RoomStore.kick_member(room_id, user_to_kick.id)

      acting_role == :admin ->
        {:error, :cannot_kick_admin_or_owner}

      true ->
        {:error, :not_authorized}
    end
  end

  @doc """
  Lists all members of a room with their roles.
  Returns list of maps with user info and roles.
  """
  def list_members(room) when is_map(room) do
    room_id = Map.get(room, :id)

    case RoomStore.list_members(room_id) do
      {:ok, members} ->
        # Enrich with user data
        enriched =
          members
          |> Enum.map(fn {user_id, role} ->
            user = get_user_info(user_id)
            %{user_id: user_id, role: role, user: user}
          end)
          |> Enum.sort_by(fn m ->
            # Sort by role priority: owner first, then admin, then member
            case m.role do
              :owner -> 0
              :admin -> 1
              :member -> 2
            end
          end)

        {:ok, enriched}

      error ->
        error
    end
  end

  defp get_user_info(user_id) do
    case Sensocto.Accounts.User |> Ash.get(user_id, error?: false) do
      {:ok, user} when not is_nil(user) ->
        %{
          id: user.id,
          email: user.email,
          display_name: user.display_name
        }

      _ ->
        %{id: user_id, email: "Unknown", display_name: nil}
    end
  end

  # ============================================================================
  # Sensor Management
  # ============================================================================

  @doc """
  Adds a sensor to a room.
  """
  def add_sensor_to_room(room, sensor_id) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.add_sensor(room_id, sensor_id)
  end

  @doc """
  Removes a sensor from a room.
  """
  def remove_sensor_from_room(room, sensor_id) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.remove_sensor(room_id, sensor_id)
  end

  @doc """
  Gets all sensor IDs for a room.
  """
  def get_room_sensor_ids(room_id) do
    case RoomStore.get_room(room_id) do
      {:ok, room} -> MapSet.to_list(room.sensor_ids)
      {:error, _} -> []
    end
  end

  # ============================================================================
  # Room Management
  # ============================================================================

  @doc """
  Updates a room's settings.
  """
  def update_room(room, attrs, _user) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.update_room(room_id, attrs)
  end

  @doc """
  Regenerates the join code for a room.
  """
  def regenerate_join_code(room, _user) when is_map(room) do
    room_id = Map.get(room, :id)

    case RoomStore.regenerate_join_code(room_id) do
      {:ok, new_code} ->
        # Return updated room
        case get_room(room_id) do
          {:ok, updated_room} -> {:ok, updated_room}
          _error -> {:ok, %{room | join_code: new_code}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a room.
  """
  def delete_room(room, _user) when is_map(room) do
    room_id = Map.get(room, :id)
    RoomStore.delete_room(room_id)
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
  Checks if a room exists.
  """
  def exists?(room_id) do
    RoomStore.exists?(room_id)
  end
end
