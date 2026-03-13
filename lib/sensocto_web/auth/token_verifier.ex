defmodule SensoctoWeb.Auth.TokenVerifier do
  @moduledoc """
  Shared JWT token verification and user loading.

  Consolidates token verification logic previously duplicated across
  MobileAuthController and RoomController.
  """
  require Logger

  @doc """
  Verifies a JWT token and loads the associated user.

  Returns `{:ok, user}` on success or `{:error, reason}` on failure.
  """
  def verify_and_load(token) when is_binary(token) do
    result = AshAuthentication.Jwt.verify(token, Sensocto.Accounts.User)

    case result do
      {:ok, %{"sub" => _} = claims, _resource} ->
        load_user_from_claims(claims)

      {:ok, %{id: _} = user, _claims} ->
        {:ok, user}

      {:ok, %{id: _} = user} ->
        {:ok, user}

      {:ok, %{"sub" => _} = claims} ->
        load_user_from_claims(claims)

      {:error, reason} ->
        {:error, "Token verification failed: #{inspect(reason)}"}

      :error ->
        {:error, "Token verification failed (token may be expired or invalid)"}

      %{"sub" => _} = claims ->
        load_user_from_claims(claims)

      _other ->
        {:error, "Token verification failed"}
    end
  end

  def verify_and_load(_), do: {:error, "Invalid token"}

  @doc """
  Parses a user UUID from an AshAuthentication subject string.

  Subject format: `"user?id=2672b29b-4c43-44f2-a052-b578e32d0b9c"`
  """
  def parse_user_id_from_subject(nil), do: {:error, "No subject claim in token"}

  def parse_user_id_from_subject(sub) when is_binary(sub) do
    case Regex.run(~r/id=([0-9a-f-]+)/i, sub) do
      [_, uuid] ->
        {:ok, uuid}

      nil ->
        # Maybe it's just the UUID directly
        if String.match?(sub, ~r/^[a-f0-9-]+$/i) do
          {:ok, sub}
        else
          {:error, "Could not parse user ID from subject: #{sub}"}
        end
    end
  end

  def parse_user_id_from_subject(_), do: {:error, "Invalid subject format"}

  @doc """
  Loads a user by ID using Ash (never raw Ecto).

  Returns `{:ok, user}` or `{:error, "User not found"}`.
  """
  def load_user(user_id) when is_binary(user_id) do
    case Ash.get(Sensocto.Accounts.User, user_id, authorize?: false) do
      {:ok, user} ->
        {:ok, user}

      {:error, _reason} ->
        {:error, "User not found"}
    end
  end

  def load_user(_), do: {:error, "Invalid user ID"}

  # Private

  defp load_user_from_claims(claims) do
    sub = claims["sub"] || claims[:sub]

    case parse_user_id_from_subject(sub) do
      {:ok, user_id} -> load_user(user_id)
      {:error, reason} -> {:error, reason}
    end
  end
end
