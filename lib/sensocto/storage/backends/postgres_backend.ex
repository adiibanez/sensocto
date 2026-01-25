defmodule Sensocto.Storage.Backends.PostgresBackend do
  @moduledoc """
  PostgreSQL storage backend for room snapshots.

  Uses the existing Ash Room resource for persistent storage.
  This is the primary (most reliable) backend with priority 1.

  ## Storage Model

  Room data is stored using the `Sensocto.Sensors.Room` Ash resource,
  which persists to the `rooms` PostgreSQL table. The snapshot format
  is converted to/from the Ash resource format.

  ## Memberships

  This backend also handles room memberships via `Sensocto.Sensors.RoomMembership`.
  Membership data is embedded in the snapshot's `data.members` field.
  """

  @behaviour Sensocto.Storage.Backends.RoomBackend

  require Logger

  alias Sensocto.Sensors.Room, as: RoomResource
  alias Sensocto.Sensors.RoomMembership
  alias Sensocto.Storage.Backends.RoomBackend

  defstruct [
    :enabled,
    ready: false
  ]

  # ============================================================================
  # Behaviour Callbacks
  # ============================================================================

  @impl true
  def backend_id, do: :postgres

  @impl true
  def priority, do: 1

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)

    state = %__MODULE__{
      enabled: enabled,
      ready: enabled && check_repo_ready()
    }

    if state.ready do
      Logger.info("[PostgresBackend] Initialized and ready")
    else
      Logger.debug("[PostgresBackend] Initialized but not ready (enabled: #{enabled})")
    end

    {:ok, state}
  end

  @impl true
  def ready?(%__MODULE__{enabled: false}), do: false
  def ready?(%__MODULE__{ready: ready}), do: ready

  @impl true
  def store_snapshot(_snapshot, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def store_snapshot(snapshot, state) do
    %{room_id: room_id, data: data, version: version, timestamp: timestamp} = snapshot

    try do
      attrs = build_room_attrs(room_id, data, version, timestamp)

      case RoomResource |> Ash.get(room_id, error?: false) do
        {:ok, nil} ->
          # Room doesn't exist, create it
          RoomResource
          |> Ash.Changeset.for_create(:sync_create, attrs)
          |> Ash.create!()

          # Store memberships
          store_memberships(room_id, data)

          Logger.debug("[PostgresBackend] Created room #{room_id}")
          {:ok, state}

        {:ok, existing} ->
          # Room exists, update it
          existing
          |> Ash.Changeset.for_update(:sync_update, Map.drop(attrs, [:id, :owner_id]))
          |> Ash.update!()

          # Update memberships
          sync_memberships(room_id, data)

          Logger.debug("[PostgresBackend] Updated room #{room_id}")
          {:ok, state}

        {:error, reason} ->
          Logger.error("[PostgresBackend] Failed to get room #{room_id}: #{inspect(reason)}")
          {:error, reason, state}
      end
    rescue
      e ->
        Logger.error("[PostgresBackend] Failed to store snapshot: #{Exception.message(e)}")
        {:error, {:exception, e}, state}
    end
  end

  @impl true
  def get_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def get_snapshot(room_id, state) do
    try do
      case RoomResource |> Ash.get(room_id, error?: false) |> load_memberships() do
        {:ok, nil} ->
          {:error, :not_found, state}

        {:ok, room} ->
          snapshot = build_snapshot_from_room(room)
          {:ok, snapshot, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    rescue
      e ->
        Logger.error("[PostgresBackend] Failed to get snapshot: #{Exception.message(e)}")
        {:error, {:exception, e}, state}
    end
  end

  @impl true
  def delete_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def delete_snapshot(room_id, state) do
    try do
      case RoomResource |> Ash.get(room_id, error?: false) do
        {:ok, nil} ->
          {:ok, state}

        {:ok, room} ->
          Ash.destroy!(room)
          Logger.debug("[PostgresBackend] Deleted room #{room_id}")
          {:ok, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    rescue
      e ->
        Logger.error("[PostgresBackend] Failed to delete snapshot: #{Exception.message(e)}")
        {:error, {:exception, e}, state}
    end
  end

  @impl true
  def list_snapshots(%__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def list_snapshots(state) do
    try do
      room_ids =
        RoomResource
        |> Ash.read!(action: :all)
        |> Enum.map(& &1.id)

      {:ok, room_ids, state}
    rescue
      e ->
        Logger.error("[PostgresBackend] Failed to list snapshots: #{Exception.message(e)}")
        {:error, {:exception, e}, state}
    end
  end

  @impl true
  def flush(state) do
    # PostgreSQL commits are immediate, nothing to flush
    {:ok, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp check_repo_ready do
    # Check if the Repo is available and can execute queries
    try do
      Sensocto.Repo.query!("SELECT 1")
      true
    rescue
      _ -> false
    catch
      _, _ -> false
    end
  end

  defp load_memberships({:ok, nil}), do: {:ok, nil}

  defp load_memberships({:ok, room}) do
    {:ok, Ash.load!(room, :room_memberships)}
  end

  defp load_memberships(error), do: error

  defp build_room_attrs(room_id, data, _version, _timestamp) do
    %{
      id: room_id,
      name: Map.get(data, :name) || Map.get(data, "name") || "Untitled Room",
      description: Map.get(data, :description) || Map.get(data, "description"),
      owner_id: Map.get(data, :owner_id) || Map.get(data, "owner_id"),
      join_code: Map.get(data, :join_code) || Map.get(data, "join_code"),
      is_public: Map.get(data, :is_public, Map.get(data, "is_public", true)),
      is_persisted: true,
      calls_enabled: Map.get(data, :calls_enabled, Map.get(data, "calls_enabled", true)),
      media_playback_enabled:
        Map.get(data, :media_playback_enabled, Map.get(data, "media_playback_enabled", true)),
      object_3d_enabled:
        Map.get(data, :object_3d_enabled, Map.get(data, "object_3d_enabled", false)),
      configuration: Map.get(data, :configuration) || Map.get(data, "configuration") || %{}
    }
  end

  defp build_snapshot_from_room(room) do
    # Build members map from room_memberships
    members = build_members_map(room)

    room_data = %{
      id: room.id,
      name: room.name,
      description: room.description,
      owner_id: room.owner_id,
      join_code: room.join_code,
      is_public: room.is_public,
      calls_enabled: room.calls_enabled,
      media_playback_enabled: room.media_playback_enabled,
      object_3d_enabled: room.object_3d_enabled,
      configuration: room.configuration || %{},
      members: members,
      sensor_ids: [],
      created_at: room.inserted_at,
      updated_at: room.updated_at
    }

    # Use updated_at as version (convert to millisecond timestamp)
    version =
      room.updated_at
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix(:millisecond)

    RoomBackend.create_snapshot(room.id, room_data)
    |> Map.put(:version, version)
    |> Map.put(:timestamp, DateTime.from_naive!(room.updated_at, "Etc/UTC"))
  end

  defp build_members_map(room) do
    base = %{room.owner_id => :owner}

    case room.room_memberships do
      memberships when is_list(memberships) ->
        Enum.reduce(memberships, base, fn membership, acc ->
          Map.put(acc, membership.user_id, membership.role)
        end)

      _ ->
        base
    end
  end

  defp store_memberships(room_id, data) do
    members = Map.get(data, :members) || Map.get(data, "members") || %{}

    Enum.each(members, fn {user_id, role} ->
      store_membership(room_id, user_id, role)
    end)
  end

  defp store_membership(room_id, user_id, role) do
    import Ecto.Query

    # Check if membership already exists
    {:ok, room_uuid} = Ecto.UUID.dump(room_id)
    {:ok, user_uuid} = Ecto.UUID.dump(user_id)

    existing =
      Sensocto.Repo.one(
        from m in "room_memberships",
          where: m.room_id == ^room_uuid and m.user_id == ^user_uuid,
          select: m.id
      )

    unless existing do
      RoomMembership
      |> Ash.Changeset.for_create(:sync_create, %{
        room_id: room_id,
        user_id: user_id,
        role: normalize_role(role)
      })
      |> Ash.create!()
    end
  rescue
    e ->
      Logger.warning(
        "[PostgresBackend] Failed to store membership #{room_id}:#{user_id}: #{Exception.message(e)}"
      )
  end

  defp sync_memberships(room_id, data) do
    members = Map.get(data, :members) || Map.get(data, "members") || %{}

    # Store/update all memberships from the snapshot
    Enum.each(members, fn {user_id, role} ->
      upsert_membership(room_id, user_id, role)
    end)
  end

  defp upsert_membership(room_id, user_id, role) do
    import Ecto.Query

    {:ok, room_uuid} = Ecto.UUID.dump(room_id)
    {:ok, user_uuid} = Ecto.UUID.dump(user_id)

    existing =
      Sensocto.Repo.one(
        from m in "room_memberships",
          where: m.room_id == ^room_uuid and m.user_id == ^user_uuid,
          select: m.id
      )

    if existing do
      # Update role if changed
      role_string = Atom.to_string(normalize_role(role))
      now = DateTime.utc_now()

      Sensocto.Repo.update_all(
        from(m in "room_memberships",
          where: m.room_id == ^room_uuid and m.user_id == ^user_uuid
        ),
        set: [role: role_string, updated_at: now]
      )
    else
      RoomMembership
      |> Ash.Changeset.for_create(:sync_create, %{
        room_id: room_id,
        user_id: user_id,
        role: normalize_role(role)
      })
      |> Ash.create!()
    end
  rescue
    e ->
      Logger.warning(
        "[PostgresBackend] Failed to upsert membership #{room_id}:#{user_id}: #{Exception.message(e)}"
      )
  end

  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role("owner"), do: :owner
  defp normalize_role("admin"), do: :admin
  defp normalize_role("member"), do: :member
  defp normalize_role(_), do: :member
end
