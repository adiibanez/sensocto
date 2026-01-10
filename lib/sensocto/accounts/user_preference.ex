defmodule Sensocto.Accounts.UserPreference do
  @moduledoc """
  Schema for storing user UI preferences and state.
  Uses a flexible JSON map (ui_state) for storing various UI settings
  that should persist across sessions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_preferences" do
    field :user_id, :binary_id
    field :ui_state, :map, default: %{}
    field :last_visited_path, :string

    timestamps()
  end

  @doc """
  Changeset for creating/updating user preferences.
  """
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:user_id, :ui_state, :last_visited_path])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end

  @doc """
  Updates a specific key in the ui_state map.
  """
  def update_ui_state(preference, key, value) do
    new_ui_state = Map.put(preference.ui_state || %{}, key, value)
    changeset(preference, %{ui_state: new_ui_state})
  end
end
