defmodule Sensocto.Accounts.UserPreferences do
  @moduledoc """
  Context module for managing user preferences.
  Provides functions to get, set, and update user UI state and preferences.
  """
  alias Sensocto.Repo
  alias Sensocto.Accounts.UserPreference

  @doc """
  Gets user preferences for a given user_id.
  Creates default preferences if none exist.
  Guest users (IDs starting with "guest_") return empty preferences without database access.
  """
  def get_or_create("guest_" <> _ = _guest_id) do
    # Guest users don't have database preferences
    {:ok, %UserPreference{ui_state: %{}}}
  end

  def get_or_create(user_id) when is_binary(user_id) do
    case Repo.get_by(UserPreference, user_id: user_id) do
      nil ->
        %UserPreference{}
        |> UserPreference.changeset(%{user_id: user_id, ui_state: %{}})
        |> Repo.insert()

      preference ->
        {:ok, preference}
    end
  end

  def get_or_create(_), do: {:error, :invalid_user_id}

  @doc """
  Gets user preferences without creating if not exists.
  Guest users return nil (no preferences stored).
  """
  def get("guest_" <> _), do: nil

  def get(user_id) when is_binary(user_id) do
    Repo.get_by(UserPreference, user_id: user_id)
  end

  def get(_), do: nil

  @doc """
  Updates a specific UI state key for a user.
  Creates preferences if they don't exist.
  """
  def set_ui_state("guest_" <> _, _key, _value) do
    # Guest users don't persist preferences
    {:ok, %UserPreference{ui_state: %{}}}
  end

  def set_ui_state(user_id, key, value) when is_binary(user_id) do
    case get_or_create(user_id) do
      {:ok, preference} ->
        new_ui_state = Map.put(preference.ui_state || %{}, to_string(key), value)

        preference
        |> UserPreference.changeset(%{ui_state: new_ui_state})
        |> Repo.update()

      error ->
        error
    end
  end

  def set_ui_state(_, _, _), do: {:error, :invalid_user_id}

  @doc """
  Gets a specific UI state value for a user.
  Returns default if not found.
  """
  def get_ui_state(user_id, key, default \\ nil)

  def get_ui_state(user_id, key, default) when is_binary(user_id) do
    case get(user_id) do
      nil -> default
      preference -> Map.get(preference.ui_state || %{}, to_string(key), default)
    end
  end

  def get_ui_state(_, _, default), do: default

  @doc """
  Updates the last visited path for a user.
  Guest users don't persist this.
  """
  def set_last_visited_path("guest_" <> _, _path), do: {:ok, nil}

  def set_last_visited_path(user_id, path) when is_binary(user_id) and is_binary(path) do
    case get_or_create(user_id) do
      {:ok, preference} ->
        preference
        |> UserPreference.changeset(%{last_visited_path: path})
        |> Repo.update()

      error ->
        error
    end
  end

  def set_last_visited_path(_, _), do: {:error, :invalid_params}

  @doc """
  Gets the last visited path for a user.
  """
  def get_last_visited_path(user_id) when is_binary(user_id) do
    case get(user_id) do
      nil -> nil
      preference -> preference.last_visited_path
    end
  end

  def get_last_visited_path(_), do: nil

  @doc """
  Bulk updates multiple UI state keys at once.
  Guest users don't persist preferences.
  """
  def update_ui_state("guest_" <> _, _updates) do
    {:ok, %UserPreference{ui_state: %{}}}
  end

  def update_ui_state(user_id, updates) when is_binary(user_id) and is_map(updates) do
    case get_or_create(user_id) do
      {:ok, preference} ->
        # Merge updates into existing ui_state, converting keys to strings
        new_ui_state =
          Enum.reduce(updates, preference.ui_state || %{}, fn {k, v}, acc ->
            Map.put(acc, to_string(k), v)
          end)

        preference
        |> UserPreference.changeset(%{ui_state: new_ui_state})
        |> Repo.update()

      error ->
        error
    end
  end

  def update_ui_state(_, _), do: {:error, :invalid_params}

  @doc """
  Gets all UI state for a user as a map.
  """
  def get_all_ui_state(user_id) when is_binary(user_id) do
    case get(user_id) do
      nil -> %{}
      preference -> preference.ui_state || %{}
    end
  end

  def get_all_ui_state(_), do: %{}
end
