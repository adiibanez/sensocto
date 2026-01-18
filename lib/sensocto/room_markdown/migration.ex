defmodule Sensocto.RoomMarkdown.Migration do
  @moduledoc """
  Handles migration of room data between PostgreSQL and the new
  markdown-based storage format.

  ## Migration Strategy

  The migration is designed to be gradual and reversible:

  1. **Phase 1**: PostgreSQL remains authoritative, markdown is secondary
  2. **Phase 2**: Feature flag controls which source is authoritative
  3. **Phase 3**: Markdown becomes authoritative, PostgreSQL is backup

  ## Usage

  ```elixir
  # Migrate all rooms from PostgreSQL to Tigris
  Migration.migrate_all_to_tigris()

  # Migrate a single room
  Migration.migrate_room_to_tigris(room_id)

  # Restore all rooms from Tigris to PostgreSQL
  Migration.restore_all_from_tigris()
  ```
  """

  require Logger

  alias Sensocto.RoomMarkdown.{RoomDocument, TigrisStorage}
  alias Sensocto.RoomStore
  alias Sensocto.Sensors.Room, as: RoomResource

  @doc """
  Migrates all rooms from PostgreSQL to Tigris storage.

  Returns `{:ok, %{migrated: count, failed: count}}`.
  """
  @spec migrate_all_to_tigris() :: {:ok, map()} | {:error, term()}
  def migrate_all_to_tigris do
    Logger.info("[Migration] Starting migration of all rooms to Tigris")

    rooms = RoomResource |> Ash.read!(action: :all) |> Ash.load!(:room_memberships)

    results =
      rooms
      |> Enum.map(&migrate_room_to_tigris/1)
      |> Enum.reduce(%{migrated: 0, failed: 0, errors: []}, fn result, acc ->
        case result do
          {:ok, _} ->
            %{acc | migrated: acc.migrated + 1}

          {:error, reason} ->
            %{acc | failed: acc.failed + 1, errors: [reason | acc.errors]}
        end
      end)

    Logger.info("[Migration] Completed: #{results.migrated} migrated, #{results.failed} failed")

    {:ok, results}
  end

  @doc """
  Migrates a single room from PostgreSQL to Tigris.
  """
  @spec migrate_room_to_tigris(String.t() | struct()) :: {:ok, String.t()} | {:error, term()}
  def migrate_room_to_tigris(room_id) when is_binary(room_id) do
    case RoomResource |> Ash.get(room_id) |> then(&Ash.load!(&1, :room_memberships)) do
      {:ok, room} when not is_nil(room) ->
        migrate_room_to_tigris(room)

      _ ->
        {:error, :room_not_found}
    end
  end

  def migrate_room_to_tigris(%RoomResource{} = room) do
    # Convert to RoomDocument
    doc = postgres_room_to_document(room)

    # Upload to Tigris
    case TigrisStorage.upload(doc) do
      {:ok, _} ->
        Logger.debug("[Migration] Migrated room #{room.id} to Tigris")
        {:ok, room.id}

      {:error, reason} ->
        Logger.warning("[Migration] Failed to migrate room #{room.id}: #{inspect(reason)}")
        {:error, {:upload_failed, room.id, reason}}
    end
  end

  @doc """
  Restores all rooms from Tigris to PostgreSQL.

  This is useful for disaster recovery or rollback.
  """
  @spec restore_all_from_tigris() :: {:ok, map()} | {:error, term()}
  def restore_all_from_tigris do
    Logger.info("[Migration] Restoring all rooms from Tigris to PostgreSQL")

    case TigrisStorage.list_rooms() do
      {:ok, room_ids} ->
        results =
          room_ids
          |> Enum.map(&restore_room_from_tigris/1)
          |> Enum.reduce(%{restored: 0, failed: 0, errors: []}, fn result, acc ->
            case result do
              {:ok, _} ->
                %{acc | restored: acc.restored + 1}

              {:error, reason} ->
                %{acc | failed: acc.failed + 1, errors: [reason | acc.errors]}
            end
          end)

        Logger.info(
          "[Migration] Restore completed: #{results.restored} restored, #{results.failed} failed"
        )

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restores a single room from Tigris to PostgreSQL.
  """
  @spec restore_room_from_tigris(String.t()) :: {:ok, String.t()} | {:error, term()}
  def restore_room_from_tigris(room_id) do
    case TigrisStorage.download(room_id) do
      {:ok, doc} ->
        case create_or_update_postgres_room(doc) do
          {:ok, _room} ->
            Logger.debug("[Migration] Restored room #{room_id} to PostgreSQL")
            {:ok, room_id}

          {:error, reason} ->
            {:error, {:postgres_error, room_id, reason}}
        end

      {:error, reason} ->
        {:error, {:download_failed, room_id, reason}}
    end
  end

  @doc """
  Syncs a room from the in-memory RoomStore to both PostgreSQL and Tigris.

  This ensures all storage backends are in sync.
  """
  @spec sync_room(String.t()) :: :ok | {:error, term()}
  def sync_room(room_id) do
    case RoomStore.get_room(room_id) do
      {:ok, room_data} ->
        doc = RoomDocument.from_room_store(room_data)

        # Sync to Tigris
        tigris_result = TigrisStorage.upload(doc)

        # Sync to PostgreSQL
        postgres_result = sync_to_postgres(room_data)

        case {tigris_result, postgres_result} do
          {{:ok, _}, {:ok, _}} ->
            :ok

          {{:error, t_err}, {:ok, _}} ->
            Logger.warning("[Migration] Tigris sync failed for #{room_id}: #{inspect(t_err)}")
            {:error, {:tigris_failed, t_err}}

          {{:ok, _}, {:error, p_err}} ->
            Logger.warning("[Migration] PostgreSQL sync failed for #{room_id}: #{inspect(p_err)}")
            {:error, {:postgres_failed, p_err}}

          {{:error, t_err}, {:error, p_err}} ->
            Logger.error("[Migration] Both syncs failed for #{room_id}")
            {:error, {:both_failed, t_err, p_err}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies that a room exists in all storage backends and data matches.
  """
  @spec verify_room(String.t()) :: {:ok, :consistent} | {:error, term()}
  def verify_room(room_id) do
    with {:ok, memory_data} <- RoomStore.get_room(room_id),
         {:ok, tigris_doc} <- TigrisStorage.download(room_id),
         {:ok, postgres_room} <- get_postgres_room(room_id) do
      # Compare key fields
      memory_doc = RoomDocument.from_room_store(memory_data)

      issues = []

      issues =
        if memory_doc.name != tigris_doc.name,
          do: [:name_mismatch_tigris | issues],
          else: issues

      issues =
        if memory_doc.version != tigris_doc.version,
          do: [:version_mismatch_tigris | issues],
          else: issues

      issues =
        if memory_doc.name != postgres_room.name,
          do: [:name_mismatch_postgres | issues],
          else: issues

      case issues do
        [] -> {:ok, :consistent}
        _ -> {:error, {:inconsistent, issues}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates a migration report for all rooms.
  """
  @spec generate_report() :: map()
  def generate_report do
    memory_rooms = RoomStore.list_all_rooms() |> Enum.map(& &1.id) |> MapSet.new()
    postgres_rooms = RoomResource |> Ash.read!(action: :all) |> Enum.map(& &1.id) |> MapSet.new()

    tigris_rooms =
      case TigrisStorage.list_rooms() do
        {:ok, ids} -> MapSet.new(ids)
        _ -> MapSet.new()
      end

    all_rooms = MapSet.union(memory_rooms, MapSet.union(postgres_rooms, tigris_rooms))

    %{
      total_rooms: MapSet.size(all_rooms),
      in_memory: MapSet.size(memory_rooms),
      in_postgres: MapSet.size(postgres_rooms),
      in_tigris: MapSet.size(tigris_rooms),
      only_memory:
        MapSet.difference(memory_rooms, MapSet.union(postgres_rooms, tigris_rooms))
        |> MapSet.size(),
      only_postgres:
        MapSet.difference(postgres_rooms, MapSet.union(memory_rooms, tigris_rooms))
        |> MapSet.size(),
      only_tigris:
        MapSet.difference(tigris_rooms, MapSet.union(memory_rooms, postgres_rooms))
        |> MapSet.size(),
      in_all_three:
        MapSet.intersection(memory_rooms, MapSet.intersection(postgres_rooms, tigris_rooms))
        |> MapSet.size()
    }
  end

  # Private functions

  defp postgres_room_to_document(%RoomResource{} = room) do
    # Build members list from memberships
    members =
      (room.room_memberships || [])
      |> Enum.map(fn m ->
        %{id: m.user_id, role: m.role}
      end)

    # Ensure owner is included
    members =
      if Enum.any?(members, &(&1.id == room.owner_id)) do
        members
      else
        [%{id: room.owner_id, role: :owner} | members]
      end

    RoomDocument.new(%{
      id: room.id,
      name: room.name,
      description: room.description,
      owner_id: room.owner_id,
      join_code: room.join_code,
      version: 1,
      created_at: room.inserted_at,
      updated_at: room.updated_at,
      features: %{
        is_public: room.is_public,
        calls_enabled: room.calls_enabled,
        media_playback_enabled: room.media_playback_enabled,
        object_3d_enabled: room.object_3d_enabled
      },
      admins: %{
        signature: nil,
        updated_by: nil,
        members: members
      },
      configuration: room.configuration || %{},
      body: ""
    })
  end

  defp create_or_update_postgres_room(%RoomDocument{} = doc) do
    case RoomResource |> Ash.get(doc.id, error?: false) do
      {:ok, nil} ->
        # Create new room
        RoomResource
        |> Ash.Changeset.for_create(:sync_create, %{
          id: doc.id,
          name: doc.name,
          description: doc.description,
          owner_id: doc.owner_id,
          join_code: doc.join_code,
          is_public: doc.features.is_public,
          calls_enabled: doc.features.calls_enabled,
          media_playback_enabled: doc.features.media_playback_enabled,
          object_3d_enabled: doc.features.object_3d_enabled,
          configuration: doc.configuration
        })
        |> Ash.create()

      {:ok, existing} ->
        # Update existing room
        existing
        |> Ash.Changeset.for_update(:sync_update, %{
          name: doc.name,
          description: doc.description,
          is_public: doc.features.is_public,
          calls_enabled: doc.features.calls_enabled,
          media_playback_enabled: doc.features.media_playback_enabled,
          object_3d_enabled: doc.features.object_3d_enabled,
          configuration: doc.configuration,
          join_code: doc.join_code
        })
        |> Ash.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_to_postgres(room_data) do
    attrs = %{
      id: room_data.id,
      name: room_data.name,
      description: room_data.description,
      owner_id: room_data.owner_id,
      join_code: room_data.join_code,
      is_public: room_data.is_public,
      calls_enabled: Map.get(room_data, :calls_enabled, true),
      media_playback_enabled: Map.get(room_data, :media_playback_enabled, true),
      object_3d_enabled: Map.get(room_data, :object_3d_enabled, false),
      configuration: room_data.configuration || %{}
    }

    case RoomResource |> Ash.get(room_data.id, error?: false) do
      {:ok, nil} ->
        RoomResource
        |> Ash.Changeset.for_create(:sync_create, attrs)
        |> Ash.create()

      {:ok, existing} ->
        existing
        |> Ash.Changeset.for_update(:sync_update, Map.drop(attrs, [:id, :owner_id]))
        |> Ash.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_postgres_room(room_id) do
    case RoomResource |> Ash.get(room_id) do
      {:ok, room} when not is_nil(room) -> {:ok, room}
      _ -> {:error, :not_found}
    end
  end
end
