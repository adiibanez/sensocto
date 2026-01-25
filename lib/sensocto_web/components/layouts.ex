defmodule SensoctoWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use SensoctoWeb, :controller` and
  `use SensoctoWeb, :live_view`.
  """
  use SensoctoWeb, :html

  embed_templates "layouts/*"

  @doc """
  Generates session data for the SenseLive component.
  Extracts bearer token from current_user in socket assigns.
  """
  def sense_session(socket, opts \\ []) do
    base_session = %{"parent_id" => self()}

    # Add any extra options (like "mobile" => true)
    base_session =
      Enum.reduce(opts, base_session, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)

    # Safely get current_user - socket.assigns may be AssignsNotInSocket during static render
    current_user = get_current_user(socket)

    case current_user do
      # Guest user (map with :id and :token)
      %{id: guest_id, token: token} when is_binary(guest_id) and is_binary(token) ->
        Map.merge(base_session, %{
          "is_guest" => true,
          "guest_id" => guest_id,
          "guest_token" => token
        })

      # Regular user with token (Ash user struct)
      %{__struct__: _} = user ->
        # For regular users, we need to get their JWT token
        # This is stored in the session, but we can regenerate it
        case get_user_token(user) do
          {:ok, token} ->
            Map.put(base_session, "user_token", token)

          _ ->
            base_session
        end

      _ ->
        base_session
    end
  end

  defp get_current_user(socket) do
    # During static render, socket.assigns is AssignsNotInSocket struct
    # We need to check if assigns is a map before accessing it
    case socket.assigns do
      %{current_user: user} -> user
      _ -> nil
    end
  end

  defp get_user_token(user) do
    # Try to generate a token for the user
    case AshAuthentication.Jwt.token_for_user(user) do
      {:ok, token, _claims} -> {:ok, token}
      error -> error
    end
  end
end
