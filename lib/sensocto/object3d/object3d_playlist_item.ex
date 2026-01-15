defmodule Sensocto.Object3D.Object3DPlaylistItem do
  @moduledoc """
  Ecto schema for 3D object playlist items (Gaussian splats).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Sensocto.Object3D.Object3DPlaylist
  alias Sensocto.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: [
             :id,
             :splat_url,
             :name,
             :description,
             :thumbnail_url,
             :source_url,
             :camera_preset_position,
             :camera_preset_target,
             :position,
             :viewed_at
           ]}

  schema "object3d_playlist_items" do
    field :splat_url, :string
    field :name, :string
    field :description, :string
    field :thumbnail_url, :string
    field :source_url, :string
    field :camera_preset_position, :string
    field :camera_preset_target, :string
    field :position, :integer, default: 0
    field :viewed_at, :utc_datetime_usec

    belongs_to :playlist, Object3DPlaylist
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
      :splat_url,
      :name,
      :description,
      :thumbnail_url,
      :source_url,
      :camera_preset_position,
      :camera_preset_target,
      :added_by_user_id,
      :position
    ])
    |> validate_required([:playlist_id, :splat_url])
    |> validate_splat_url()
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
  Changeset for marking as viewed.
  """
  def viewed_changeset(item) do
    item
    |> change(viewed_at: DateTime.utc_now())
  end

  defp validate_splat_url(changeset) do
    validate_change(changeset, :splat_url, fn :splat_url, url ->
      uri = URI.parse(url)

      cond do
        uri.scheme not in ["http", "https"] ->
          [splat_url: "must be a valid HTTP(S) URL"]

        true ->
          []
      end
    end)
  end
end
