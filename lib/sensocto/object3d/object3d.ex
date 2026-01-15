defmodule Sensocto.Object3D do
  @moduledoc """
  Context module for 3D object viewing and playlists.
  Handles playlist CRUD operations and coordinates with Object3DPlayerServer.
  """

  import Ecto.Query
  alias Sensocto.Repo
  alias Sensocto.Object3D.{Object3DPlaylist, Object3DPlaylistItem, Object3DPlayerServer}

  require Logger

  # ============================================================================
  # Playlist Operations
  # ============================================================================

  @doc """
  Gets or creates a playlist for a room.
  """
  def get_or_create_room_playlist(room_id) do
    case get_room_playlist(room_id) do
      nil ->
        create_room_playlist(room_id)

      playlist ->
        {:ok, playlist}
    end
  end

  @doc """
  Gets the playlist for a room.
  """
  def get_room_playlist(room_id) do
    Repo.one(
      from p in Object3DPlaylist,
        where: p.room_id == ^room_id,
        preload: [items: ^from(i in Object3DPlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Creates a playlist for a room.
  """
  def create_room_playlist(room_id, name \\ "3D Objects") do
    %Object3DPlaylist{}
    |> Object3DPlaylist.room_changeset(%{room_id: room_id, name: name})
    |> Repo.insert()
    |> case do
      {:ok, playlist} ->
        {:ok, Repo.preload(playlist, :items)}

      error ->
        error
    end
  end

  @doc """
  Gets or creates the global lobby playlist.
  """
  def get_or_create_lobby_playlist do
    case get_lobby_playlist() do
      nil ->
        create_lobby_playlist()

      playlist ->
        {:ok, playlist}
    end
  end

  @doc """
  Gets the lobby playlist.
  """
  def get_lobby_playlist do
    Repo.one(
      from p in Object3DPlaylist,
        where: p.is_lobby == true,
        preload: [items: ^from(i in Object3DPlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Creates the lobby playlist.
  """
  def create_lobby_playlist(name \\ "Lobby 3D Objects") do
    %Object3DPlaylist{}
    |> Object3DPlaylist.lobby_changeset(%{name: name})
    |> Repo.insert()
    |> case do
      {:ok, playlist} ->
        {:ok, Repo.preload(playlist, :items)}

      error ->
        error
    end
  end

  @doc """
  Gets a playlist by ID with items preloaded.
  """
  def get_playlist(nil), do: nil

  def get_playlist(playlist_id) do
    Repo.one(
      from p in Object3DPlaylist,
        where: p.id == ^playlist_id,
        preload: [items: ^from(i in Object3DPlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Gets all items in a playlist ordered by position.
  """
  def get_playlist_items(playlist_id) do
    Repo.all(
      from i in Object3DPlaylistItem,
        where: i.playlist_id == ^playlist_id,
        order_by: i.position,
        preload: [:added_by_user]
    )
  end

  # ============================================================================
  # Playlist Item Operations
  # ============================================================================

  @doc """
  Adds a 3D object (Gaussian splat) to a playlist.
  """
  def add_to_playlist(playlist_id, attrs, user_id \\ nil) when is_map(attrs) do
    splat_url = attrs[:splat_url] || attrs["splat_url"]

    if is_nil(splat_url) or splat_url == "" do
      {:error, "splat_url is required"}
    else
      next_position = get_next_position(playlist_id)

      item_attrs = %{
        playlist_id: playlist_id,
        splat_url: splat_url,
        name: attrs[:name] || attrs["name"] || extract_name_from_url(splat_url),
        description: attrs[:description] || attrs["description"],
        thumbnail_url: attrs[:thumbnail_url] || attrs["thumbnail_url"],
        source_url: attrs[:source_url] || attrs["source_url"],
        camera_preset_position: attrs[:camera_preset_position] || attrs["camera_preset_position"],
        camera_preset_target: attrs[:camera_preset_target] || attrs["camera_preset_target"],
        added_by_user_id: user_id,
        position: next_position
      }

      %Object3DPlaylistItem{}
      |> Object3DPlaylistItem.changeset(item_attrs)
      |> Repo.insert()
      |> case do
        {:ok, item} ->
          item = Repo.preload(item, :added_by_user)
          broadcast_playlist_update(playlist_id)
          notify_item_added(playlist_id, item)
          {:ok, item}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Removes an item from a playlist.
  """
  def remove_from_playlist(item_id) do
    case Repo.get(Object3DPlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        playlist_id = item.playlist_id

        case Repo.delete(item) do
          {:ok, _} ->
            reorder_after_removal(playlist_id)
            broadcast_playlist_update(playlist_id)
            :ok

          error ->
            error
        end
    end
  end

  @doc """
  Reorders items in a playlist.
  item_ids should be a list of item IDs in the desired order.
  """
  def reorder_playlist(playlist_id, item_ids) when is_list(item_ids) do
    Repo.transaction(fn ->
      item_ids
      |> Enum.with_index()
      |> Enum.each(fn {item_id, position} ->
        from(i in Object3DPlaylistItem,
          where: i.id == ^item_id and i.playlist_id == ^playlist_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)

    broadcast_playlist_update(playlist_id)
    :ok
  end

  @doc """
  Moves an item to a new position in the playlist.
  """
  def move_item(item_id, new_position) do
    case Repo.get(Object3DPlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        playlist_id = item.playlist_id
        old_position = item.position

        Repo.transaction(fn ->
          cond do
            new_position > old_position ->
              from(i in Object3DPlaylistItem,
                where:
                  i.playlist_id == ^playlist_id and i.position > ^old_position and
                    i.position <= ^new_position
              )
              |> Repo.update_all(inc: [position: -1])

            new_position < old_position ->
              from(i in Object3DPlaylistItem,
                where:
                  i.playlist_id == ^playlist_id and i.position >= ^new_position and
                    i.position < ^old_position
              )
              |> Repo.update_all(inc: [position: 1])

            true ->
              :ok
          end

          item
          |> Object3DPlaylistItem.position_changeset(new_position)
          |> Repo.update!()
        end)

        broadcast_playlist_update(playlist_id)
        :ok
    end
  end

  @doc """
  Marks a playlist item as viewed.
  """
  def mark_item_viewed(item_id) do
    case Repo.get(Object3DPlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        item
        |> Object3DPlaylistItem.viewed_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Gets the next item in the playlist after the given item.
  """
  def get_next_item(playlist_id, current_item_id) do
    current_item = Repo.get(Object3DPlaylistItem, current_item_id)

    if current_item do
      Repo.one(
        from i in Object3DPlaylistItem,
          where: i.playlist_id == ^playlist_id and i.position > ^current_item.position,
          order_by: i.position,
          limit: 1
      )
    else
      get_first_item(playlist_id)
    end
  end

  @doc """
  Gets the previous item in the playlist.
  """
  def get_previous_item(playlist_id, current_item_id) do
    current_item = Repo.get(Object3DPlaylistItem, current_item_id)

    if current_item do
      Repo.one(
        from i in Object3DPlaylistItem,
          where: i.playlist_id == ^playlist_id and i.position < ^current_item.position,
          order_by: [desc: i.position],
          limit: 1
      )
    else
      nil
    end
  end

  @doc """
  Gets the first item in a playlist.
  """
  def get_first_item(playlist_id) do
    Repo.one(
      from i in Object3DPlaylistItem,
        where: i.playlist_id == ^playlist_id,
        order_by: i.position,
        limit: 1
    )
  end

  @doc """
  Gets a playlist item by ID.
  """
  def get_item(item_id) do
    Repo.get(Object3DPlaylistItem, item_id)
    |> Repo.preload(:added_by_user)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_next_position(playlist_id) do
    max_position =
      Repo.one(
        from i in Object3DPlaylistItem,
          where: i.playlist_id == ^playlist_id,
          select: max(i.position)
      )

    (max_position || -1) + 1
  end

  defp reorder_after_removal(playlist_id) do
    items =
      Repo.all(
        from i in Object3DPlaylistItem,
          where: i.playlist_id == ^playlist_id,
          order_by: i.position
      )

    items
    |> Enum.with_index()
    |> Enum.each(fn {item, index} ->
      if item.position != index do
        item
        |> Object3DPlaylistItem.position_changeset(index)
        |> Repo.update!()
      end
    end)
  end

  defp broadcast_playlist_update(playlist_id) do
    playlist = get_playlist(playlist_id)

    if playlist do
      topic =
        if playlist.is_lobby do
          "object3d:lobby"
        else
          "object3d:#{playlist.room_id}"
        end

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        topic,
        {:object3d_playlist_updated, %{playlist: playlist, items: playlist.items}}
      )
    end
  end

  defp notify_item_added(playlist_id, item) do
    playlist = get_playlist(playlist_id)

    if playlist do
      room_id = if playlist.is_lobby, do: :lobby, else: playlist.room_id
      Object3DPlayerServer.item_added(room_id, item)
    end
  end

  defp extract_name_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> String.replace(~r/\.(ply|splat|ksplat)$/i, "")
    |> String.replace(~r/[_-]/, " ")
    |> String.trim()
    |> case do
      "" -> "3D Object"
      name -> name
    end
  end
end
