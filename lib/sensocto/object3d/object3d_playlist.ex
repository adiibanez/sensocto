defmodule Sensocto.Object3D.Object3DPlaylist do
  @moduledoc """
  Ecto schema for 3D object playlists.
  A playlist can belong to a room or be the global lobby playlist.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sensocto.Object3D.Object3DPlaylistItem
  alias Sensocto.Sensors.Room

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "object3d_playlists" do
    field :name, :string, default: "3D Objects"
    field :is_lobby, :boolean, default: false

    belongs_to :room, Room

    has_many :items, Object3DPlaylistItem,
      foreign_key: :playlist_id,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a room playlist.
  """
  def room_changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:name, :room_id])
    |> validate_required([:room_id])
    |> put_change(:is_lobby, false)
    |> unique_constraint(:room_id, name: "object3d_playlists_unique_room_index")
  end

  @doc """
  Changeset for creating the lobby playlist.
  """
  def lobby_changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:name])
    |> put_change(:is_lobby, true)
    |> put_change(:room_id, nil)
    |> unique_constraint(:is_lobby, name: "object3d_playlists_unique_lobby_index")
  end

  @doc """
  Changeset for updating a playlist.
  """
  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
