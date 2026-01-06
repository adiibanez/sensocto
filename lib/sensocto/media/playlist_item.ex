defmodule Sensocto.Media.PlaylistItem do
  @moduledoc """
  Ecto schema for playlist items (YouTube videos).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sensocto.Media.Playlist
  alias Sensocto.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "playlist_items" do
    field :youtube_url, :string
    field :youtube_video_id, :string
    field :title, :string
    field :duration_seconds, :integer
    field :thumbnail_url, :string
    field :position, :integer, default: 0
    field :played_at, :utc_datetime_usec

    belongs_to :playlist, Playlist
    belongs_to :added_by_user, User, foreign_key: :added_by_user_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a playlist item.
  """
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :playlist_id,
      :youtube_url,
      :youtube_video_id,
      :title,
      :duration_seconds,
      :thumbnail_url,
      :added_by_user_id,
      :position
    ])
    |> validate_required([:playlist_id, :youtube_url, :youtube_video_id])
    |> validate_length(:youtube_video_id, min: 11, max: 11)
    |> foreign_key_constraint(:playlist_id)
    |> foreign_key_constraint(:added_by_user_id)
  end

  @doc """
  Changeset for updating position.
  """
  def position_changeset(item, position) do
    item
    |> change(position: position)
  end

  @doc """
  Changeset for marking as played.
  """
  def played_changeset(item) do
    item
    |> change(played_at: DateTime.utc_now())
  end
end
