defmodule SensoctoWeb.Api.MobileAuthController do
  @moduledoc """
  API controller for mobile device authentication.

  Provides endpoints for mobile apps to verify authentication tokens
  and retrieve user information.
  """
  use SensoctoWeb, :controller
  require Logger

  @doc """
  Verify a JWT token and return user information.

  The token should be sent as a Bearer token in the Authorization header.
  This endpoint is used by the mobile app after scanning a QR code or
  receiving a deep link with an authentication token.

  ## Response

  On success, returns the authenticated user's information:

      {
        "ok": true,
        "user": {
          "id": "uuid",
          "email": "user@example.com",
          "display_name": "User Name"
        }
      }

  On failure, returns an error:

      {
        "ok": false,
        "error": "Invalid or expired token"
      }
  """
  def verify(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        Logger.warning("Mobile auth verification failed: no current user")

        conn
        |> put_status(:unauthorized)
        |> json(%{
          ok: false,
          error: "Invalid or expired token"
        })

      user ->
        Logger.info("Mobile auth verification succeeded for user #{user.id}")

        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          user: %{
            id: user.id,
            email: user.email,
            display_name: user.display_name || user.email
          }
        })
    end
  end

  @doc """
  Returns the current user's information.

  Same as verify/2 but semantically for getting user info after auth.
  """
  def me(conn, _params) do
    verify(conn, %{})
  end
end
