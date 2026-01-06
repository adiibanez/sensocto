defmodule Sensocto.Media do
  @moduledoc """
  Context module for media playback and playlists.
  Handles playlist CRUD operations and coordinates with MediaPlayerServer.
  """

  import Ecto.Query
  alias Sensocto.Repo
  alias Sensocto.Media.{Playlist, PlaylistItem, YouTube, MediaPlayerServer}

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
      from p in Playlist,
        where: p.room_id == ^room_id,
        preload: [items: ^from(i in PlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Creates a playlist for a room.
  """
  def create_room_playlist(room_id, name \\ "Room Playlist") do
    %Playlist{}
    |> Playlist.room_changeset(%{room_id: room_id, name: name})
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
      from p in Playlist,
        where: p.is_lobby == true,
        preload: [items: ^from(i in PlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Creates the lobby playlist.
  """
  def create_lobby_playlist(name \\ "Lobby Playlist") do
    %Playlist{}
    |> Playlist.lobby_changeset(%{name: name})
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
      from p in Playlist,
        where: p.id == ^playlist_id,
        preload: [items: ^from(i in PlaylistItem, order_by: i.position)]
    )
  end

  @doc """
  Gets all items in a playlist ordered by position.
  """
  def get_playlist_items(playlist_id) do
    Repo.all(
      from i in PlaylistItem,
        where: i.playlist_id == ^playlist_id,
        order_by: i.position,
        preload: [:added_by_user]
    )
  end

  # ============================================================================
  # Playlist Item Operations
  # ============================================================================

  @doc """
  Adds a YouTube video to a playlist.
  Automatically fetches metadata from YouTube.
  """
  def add_to_playlist(playlist_id, youtube_url, user_id \\ nil) do
    with {:ok, video_id} <- YouTube.extract_video_id(youtube_url),
         {:ok, metadata} <- YouTube.fetch_metadata(video_id),
         {:ok, normalized_url} <- YouTube.normalize_url(youtube_url) do
      # Get the next position
      next_position = get_next_position(playlist_id)

      attrs = %{
        playlist_id: playlist_id,
        youtube_url: normalized_url,
        youtube_video_id: video_id,
        title: metadata.title,
        duration_seconds: metadata.duration_seconds,
        thumbnail_url: metadata.thumbnail_url,
        added_by_user_id: user_id,
        position: next_position
      }

      %PlaylistItem{}
      |> PlaylistItem.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, item} ->
          item = Repo.preload(item, :added_by_user)
          broadcast_playlist_update(playlist_id)
          notify_item_added(playlist_id, item)
          {:ok, item}

        error ->
          error
      end
    end
  end

  @doc """
  Adds a YouTube video to a playlist with minimal metadata (for when oEmbed fails).
  """
  def add_to_playlist_minimal(playlist_id, youtube_url, user_id \\ nil) do
    with {:ok, video_id} <- YouTube.extract_video_id(youtube_url),
         {:ok, normalized_url} <- YouTube.normalize_url(youtube_url) do
      next_position = get_next_position(playlist_id)

      attrs = %{
        playlist_id: playlist_id,
        youtube_url: normalized_url,
        youtube_video_id: video_id,
        title: "YouTube Video",
        thumbnail_url: YouTube.build_thumbnail_url(video_id),
        added_by_user_id: user_id,
        position: next_position
      }

      %PlaylistItem{}
      |> PlaylistItem.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, item} ->
          item = Repo.preload(item, :added_by_user)
          broadcast_playlist_update(playlist_id)
          notify_item_added(playlist_id, item)
          {:ok, item}

        error ->
          error
      end
    end
  end

  @doc """
  Removes an item from a playlist.
  """
  def remove_from_playlist(item_id) do
    case Repo.get(PlaylistItem, item_id) do
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
        from(i in PlaylistItem,
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
    case Repo.get(PlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        playlist_id = item.playlist_id
        old_position = item.position

        Repo.transaction(fn ->
          cond do
            new_position > old_position ->
              # Moving down - shift items between old and new position up
              from(i in PlaylistItem,
                where:
                  i.playlist_id == ^playlist_id and i.position > ^old_position and
                    i.position <= ^new_position
              )
              |> Repo.update_all(inc: [position: -1])

            new_position < old_position ->
              # Moving up - shift items between new and old position down
              from(i in PlaylistItem,
                where:
                  i.playlist_id == ^playlist_id and i.position >= ^new_position and
                    i.position < ^old_position
              )
              |> Repo.update_all(inc: [position: 1])

            true ->
              :ok
          end

          # Update the item's position
          item
          |> PlaylistItem.position_changeset(new_position)
          |> Repo.update!()
        end)

        broadcast_playlist_update(playlist_id)
        :ok
    end
  end

  @doc """
  Marks a playlist item as played.
  """
  def mark_item_played(item_id) do
    case Repo.get(PlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        item
        |> PlaylistItem.played_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Updates the duration of a playlist item (called when player reports actual duration).
  """
  def update_item_duration(item_id, duration_seconds) do
    case Repo.get(PlaylistItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        item
        |> Ecto.Changeset.change(duration_seconds: duration_seconds)
        |> Repo.update()
    end
  end

  @doc """
  Gets the next item in the playlist after the given item.
  """
  def get_next_item(playlist_id, current_item_id) do
    current_item = Repo.get(PlaylistItem, current_item_id)

    if current_item do
      Repo.one(
        from i in PlaylistItem,
          where: i.playlist_id == ^playlist_id and i.position > ^current_item.position,
          order_by: i.position,
          limit: 1
      )
    else
      # If no current item, get the first item
      get_first_item(playlist_id)
    end
  end

  @doc """
  Gets the previous item in the playlist.
  """
  def get_previous_item(playlist_id, current_item_id) do
    current_item = Repo.get(PlaylistItem, current_item_id)

    if current_item do
      Repo.one(
        from i in PlaylistItem,
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
      from i in PlaylistItem,
        where: i.playlist_id == ^playlist_id,
        order_by: i.position,
        limit: 1
    )
  end

  @doc """
  Gets a playlist item by ID.
  """
  def get_item(item_id) do
    Repo.get(PlaylistItem, item_id)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_next_position(playlist_id) do
    max_position =
      Repo.one(
        from i in PlaylistItem,
          where: i.playlist_id == ^playlist_id,
          select: max(i.position)
      )

    (max_position || -1) + 1
  end

  defp reorder_after_removal(playlist_id) do
    # Get all items ordered by position and reindex
    items =
      Repo.all(
        from i in PlaylistItem,
          where: i.playlist_id == ^playlist_id,
          order_by: i.position
      )

    items
    |> Enum.with_index()
    |> Enum.each(fn {item, index} ->
      if item.position != index do
        item
        |> PlaylistItem.position_changeset(index)
        |> Repo.update!()
      end
    end)
  end

  defp broadcast_playlist_update(playlist_id) do
    playlist = get_playlist(playlist_id)

    if playlist do
      topic =
        if playlist.is_lobby do
          "media:lobby"
        else
          "media:#{playlist.room_id}"
        end

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        topic,
        {:media_playlist_updated, %{playlist: playlist, items: playlist.items}}
      )
    end
  end

  defp notify_item_added(playlist_id, item) do
    playlist = get_playlist(playlist_id)

    if playlist do
      room_id = if playlist.is_lobby, do: :lobby, else: playlist.room_id

      # Notify the media player server that an item was added
      # It will auto-select it if there's no current item
      MediaPlayerServer.item_added(room_id, item)
    end
  end
end
