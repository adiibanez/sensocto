defmodule Sensocto.Graph.Context do
  @moduledoc """
  Context module for Neo4j graph operations.

  Provides high-level functions for:
  - User room membership with sensors
  - Room presence tracking
  - Graph-based room queries
  """
  require Logger
  require Ash.Query

  alias Sensocto.Graph.{RoomNode, UserNode, RoomPresence}

  # ============================================================================
  # Room Node Operations
  # ============================================================================

  @doc """
  Syncs a room to the Neo4j graph.
  Creates or updates the room node with current data.
  """
  def sync_room(room) when is_map(room) do
    attrs = %{
      id: room.id,
      name: room.name,
      join_code: Map.get(room, :join_code),
      is_public: Map.get(room, :is_public, true)
    }

    RoomNode
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
    |> case do
      {:ok, node} -> {:ok, node}
      {:error, %{errors: errors}} = error ->
        if identity_error?(errors) do
          # Room already exists, update it
          update_room_node(room.id, attrs)
        else
          error
        end
    end
  end

  defp update_room_node(room_id, attrs) do
    case get_room_node(room_id) do
      {:ok, node} ->
        node
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.update()

      error -> error
    end
  end

  @doc """
  Gets a room node from Neo4j by ID.
  """
  def get_room_node(room_id) do
    RoomNode
    |> Ash.Query.for_read(:by_id, %{id: room_id})
    |> Ash.read_one()
  end

  # ============================================================================
  # User Node Operations
  # ============================================================================

  @doc """
  Syncs a user to the Neo4j graph.
  Creates or updates the user node with current data.
  """
  def sync_user(user) when is_struct(user) do
    attrs = %{
      id: user.id,
      email: to_string(user.email),
      display_name: get_display_name(user)
    }

    UserNode
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
    |> case do
      {:ok, node} -> {:ok, node}
      {:error, %{errors: errors}} = error ->
        if identity_error?(errors) do
          update_user_node(user.id, attrs)
        else
          error
        end
    end
  end

  defp update_user_node(user_id, attrs) do
    case get_user_node(user_id) do
      {:ok, node} ->
        node
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.update()

      error -> error
    end
  end

  @doc """
  Gets a user node from Neo4j by ID.
  """
  def get_user_node(user_id) do
    UserNode
    |> Ash.Query.for_read(:by_id, %{id: user_id})
    |> Ash.read_one()
  end

  defp get_display_name(user) do
    case Map.get(user, :email) do
      nil -> "Unknown"
      email -> email |> to_string() |> String.split("@") |> List.first()
    end
  end

  # ============================================================================
  # Room Presence Operations
  # ============================================================================

  @doc """
  Joins a user to a room with all their available sensors.

  1. Syncs user and room nodes to Neo4j
  2. Gets all sensor IDs available to the user
  3. Creates a RoomPresence edge linking user to room with sensors
  4. Broadcasts room update via PubSub
  """
  def join_room_with_sensors(room, user, opts \\ []) do
    role = Keyword.get(opts, :role, :member)

    with {:ok, _room_node} <- sync_room(room),
         {:ok, _user_node} <- sync_user(user),
         sensor_ids <- get_user_sensor_ids(user),
         {:ok, presence} <- create_or_update_presence(room, user, sensor_ids, role) do

      # Broadcast room update
      broadcast_room_update(room.id, {:user_joined, %{
        user_id: user.id,
        sensor_ids: sensor_ids,
        role: role
      }})

      {:ok, presence}
    end
  end

  @doc """
  Leaves a room. Removes user's presence and their sensors from the room context.
  Returns {:ok, :left} on success.
  """
  def leave_room(room, user) do
    room_id = Map.get(room, :id)
    user_id = user.id

    case get_room_presence(user_id, room_id) do
      {:ok, nil} ->
        {:error, :not_in_room}

      {:ok, presence} ->
        sensor_ids = presence.sensor_ids

        case Ash.destroy(presence) do
          :ok ->
            broadcast_room_update(room_id, {:user_left, %{
              user_id: user_id,
              sensor_ids: sensor_ids
            }})
            {:ok, :left}

          error -> error
        end

      error -> error
    end
  end

  @doc """
  Gets a user's room presence.
  """
  def get_room_presence(user_id, room_id) do
    RoomPresence
    |> Ash.Query.for_read(:by_user_and_room, %{user_id: user_id, room_id: room_id})
    |> Ash.read_one()
  end

  @doc """
  Lists all users present in a room with their sensors.
  """
  def list_room_presences(room_id) do
    RoomPresence
    |> Ash.Query.for_read(:by_room, %{room_id: room_id})
    |> Ash.read!()
  end

  @doc """
  Lists all rooms a user is present in.
  """
  def list_user_rooms(user_id) do
    RoomPresence
    |> Ash.Query.for_read(:by_user, %{user_id: user_id})
    |> Ash.read!()
  end

  @doc """
  Checks if a user is present in a room.
  """
  def in_room?(user_id, room_id) do
    case get_room_presence(user_id, room_id) do
      {:ok, nil} -> false
      {:ok, _presence} -> true
      _ -> false
    end
  end

  @doc """
  Gets all sensor IDs associated with a room from all present users.
  Returns empty list if Neo4j is not available.
  """
  def get_room_sensor_ids(room_id) do
    try do
      room_id
      |> list_room_presences()
      |> Enum.flat_map(& &1.sensor_ids)
      |> Enum.uniq()
    rescue
      e ->
        Logger.debug("Neo4j not available for get_room_sensor_ids: #{inspect(e)}")
        []
    catch
      :exit, reason ->
        Logger.debug("Neo4j not available (exit): #{inspect(reason)}")
        []
    end
  end

  @doc """
  Lists all room presences across all rooms.
  Used for hydrating GenServer state on startup.
  Returns empty list if Neo4j is not available.
  """
  def list_all_presences do
    try do
      RoomPresence
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
    rescue
      e ->
        Logger.debug("Neo4j not available for list_all_presences: #{inspect(e)}")
        []
    catch
      :exit, reason ->
        Logger.debug("Neo4j not available (exit): #{inspect(reason)}")
        []
    end
  end

  @doc """
  Updates a user's sensors in their room presence.
  Called when sensors connect/disconnect.
  """
  def update_user_sensors(user_id, room_id, sensor_ids) do
    case get_room_presence(user_id, room_id) do
      {:ok, nil} ->
        {:error, :not_in_room}

      {:ok, presence} ->
        presence
        |> Ash.Changeset.for_update(:update, %{sensor_ids: sensor_ids})
        |> Ash.update()
        |> case do
          {:ok, updated} ->
            broadcast_room_update(room_id, {:sensors_updated, %{
              user_id: user_id,
              sensor_ids: sensor_ids
            }})
            {:ok, updated}

          error -> error
        end

      error -> error
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp create_or_update_presence(room, user, sensor_ids, role) do
    room_id = Map.get(room, :id)
    user_id = user.id

    attrs = %{
      user_id: user_id,
      room_id: room_id,
      sensor_ids: sensor_ids,
      role: role,
      joined_at: DateTime.utc_now()
    }

    case get_room_presence(user_id, room_id) do
      {:ok, nil} ->
        # Create new presence
        RoomPresence
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      {:ok, presence} ->
        # Update existing presence with new sensors
        presence
        |> Ash.Changeset.for_update(:update, %{sensor_ids: sensor_ids})
        |> Ash.update()

      error -> error
    end
  end

  defp get_user_sensor_ids(_user) do
    # Get all sensors currently connected via the SensorsDynamicSupervisor
    # These are the sensors available to the user
    Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    |> Map.keys()
  end

  defp broadcast_room_update(room_id, message) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "room:#{room_id}",
      {:room_update, message}
    )
  end

  defp identity_error?(errors) when is_list(errors) do
    Enum.any?(errors, fn error ->
      case error do
        %{class: :invalid, field: :id} -> true
        %Ash.Error.Changes.InvalidChanges{fields: fields} when is_list(fields) ->
          :id in fields
        _ -> false
      end
    end)
  end
  defp identity_error?(_), do: false
end
