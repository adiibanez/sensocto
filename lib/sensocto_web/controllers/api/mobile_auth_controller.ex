defmodule SensoctoWeb.Api.MobileAuthController do
  @moduledoc """
  API controller for mobile device authentication.

  Provides endpoints for mobile apps to verify authentication tokens
  and retrieve user information.
  """
  use SensoctoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias SensoctoWeb.Schemas.Auth
  alias SensoctoWeb.Schemas.Common

  tags(["Authentication"])

  security([%{"bearerAuth" => []}])

  operation(:verify,
    summary: "Verify authentication token",
    description: """
    Verifies a JWT token and returns the authenticated user's information.
    The token should be sent as a Bearer token in the Authorization header.
    This endpoint is used by mobile apps after scanning a QR code or
    receiving a deep link with an authentication token.
    """,
    responses: [
      ok: {"Successful verification", "application/json", Auth.VerifyResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error}
    ]
  )

  operation(:me,
    summary: "Get current user info",
    description: """
    Returns the current authenticated user's information.
    Same as verify but semantically for getting user info after auth.
    """,
    responses: [
      ok: {"User information", "application/json", Auth.VerifyResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error}
    ]
  )

  operation(:debug_verify,
    summary: "Debug token verification",
    description: """
    Debug endpoint to manually verify a token without the load_from_bearer plug.
    For testing purposes only.
    """,
    security: [],
    request_body: {"Token to verify", "application/json", Auth.DebugVerifyRequest},
    responses: [
      ok: {"Successful verification", "application/json", Auth.VerifyResponse},
      bad_request: {"Missing token", "application/json", Common.Error},
      unauthorized: {"Invalid token", "application/json", Common.Error}
    ]
  )

  operation(:refresh,
    summary: "Refresh authentication token",
    description: """
    Issues a new JWT token using the current valid token.
    Also sets an HttpOnly cookie with the new token for browser clients.
    """,
    responses: [
      ok: {"New token issued", "application/json", Auth.VerifyResponse},
      unauthorized: {"Invalid or expired token", "application/json", Common.Error}
    ]
  )

  @doc """
  POST /api/auth/refresh

  Refreshes the current JWT token. Returns a new token and sets HttpOnly cookie.
  """
  def refresh(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        # Try manual token extraction
        auth_header = Plug.Conn.get_req_header(conn, "authorization")

        token =
          case auth_header do
            [header] -> extract_bearer_token(header)
            _ -> nil
          end

        case token && verify_token_and_load_user(token) do
          {:ok, user} ->
            issue_refreshed_token(conn, user)

          _ ->
            conn
            |> put_status(:unauthorized)
            |> json(%{ok: false, error: "Invalid or expired token"})
        end

      user ->
        issue_refreshed_token(conn, user)
    end
  end

  defp issue_refreshed_token(conn, user) do
    case AshAuthentication.Jwt.token_for_user(user) do
      {:ok, token, _claims} ->
        conn
        |> SensoctoWeb.Plugs.ApiCookieAuth.set_token_cookie(token)
        |> put_status(:ok)
        |> json(%{
          ok: true,
          token: token,
          user: %{
            id: user.id,
            email: user.email,
            display_name: Map.get(user, :display_name) || user.email
          }
        })

      {:error, reason} ->
        Logger.warning("Token refresh failed: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{ok: false, error: "Failed to issue new token"})
    end
  end

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
    # First check if load_from_bearer already loaded the user
    case conn.assigns[:current_user] do
      nil ->
        # Try to manually extract and verify the token
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        Logger.debug("Auth header: #{inspect(auth_header)}")

        token =
          case auth_header do
            [header] -> extract_bearer_token(header)
            _ -> nil
          end

        case token do
          nil ->
            Logger.warning("Mobile auth verification failed: no bearer token")

            conn
            |> put_status(:unauthorized)
            |> json(%{ok: false, error: "No authorization token provided"})

          token ->
            Logger.debug("Verifying bearer token")

            case verify_token_and_load_user(token) do
              {:ok, user} ->
                Logger.debug("Auth verified for user #{user.id}")

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

              {:error, reason} ->
                Logger.warning("Mobile auth verification failed: #{reason}")

                conn
                |> put_status(:unauthorized)
                |> json(%{ok: false, error: reason})
            end
        end

      user ->
        Logger.debug("Auth verified for user #{user.id} (via pipeline)")

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

  @doc """
  Debug endpoint to manually verify a token without the load_from_bearer plug.
  POST /api/auth/debug with {"token": "..."} body
  """
  def debug_verify(conn, params) do
    token = params["token"] || ""
    Logger.debug("Debug verify called")

    if token == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{ok: false, error: "No token provided"})
    else
      # Try to verify the token and load user
      case verify_token_and_load_user(token) do
        {:ok, user} ->
          Logger.debug("Debug verify succeeded for user: #{user.id}")

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

        {:error, reason} ->
          Logger.error("Debug verify failed: #{inspect(reason)}")

          conn
          |> put_status(:unauthorized)
          |> json(%{ok: false, error: "#{reason}"})
      end
    end
  rescue
    e ->
      Logger.error("Debug verify crashed: #{inspect(e)}")
      Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")

      conn
      |> put_status(:internal_server_error)
      |> json(%{ok: false, error: "Internal error"})
  end

  defp verify_token_and_load_user(token) do
    SensoctoWeb.Auth.TokenVerifier.verify_and_load(token)
  end

  @doc """
  POST /api/auth/exchange

  Exchanges a Phoenix.Token (from deep link / QR code) for a JWT session token.
  Accepts both `{"token": "..."}` body and `Authorization: Bearer ...` header.
  """
  def exchange(conn, params) do
    token =
      params["token"] ||
        case Plug.Conn.get_req_header(conn, "authorization") do
          [header] -> extract_bearer_token(header)
          _ -> nil
        end

    case token do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "No token provided"})

      token ->
        Logger.debug("Token exchange: verifying Phoenix.Token")

        # First try as Phoenix.Token (mobile_auth salt, 10 min max age)
        case Phoenix.Token.verify(SensoctoWeb.Endpoint, "mobile_auth", token, max_age: 600) do
          {:ok, %{user_id: user_id} = data} ->
            Logger.debug("Phoenix.Token verified, user_id=#{user_id}")

            # Guest users have non-UUID IDs like "guest_xxx" — skip DB lookup
            socket_token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "user_socket", user_id)

            if String.starts_with?(to_string(user_id), "guest_") do
              guest_user = %{
                id: user_id,
                email: Map.get(data, :email, "guest"),
                display_name: Map.get(data, :email, "Guest"),
                is_guest: true
              }

              case issue_jwt_for_user(guest_user) do
                {:ok, jwt, user_info} ->
                  conn
                  |> put_status(:ok)
                  |> json(%{ok: true, token: jwt, socket_token: socket_token, user: user_info})

                {:error, reason} ->
                  conn
                  |> put_status(:internal_server_error)
                  |> json(%{ok: false, error: "Failed to issue JWT: #{reason}"})
              end
            else
              # Regular user — load from DB
              case load_user_by_id(user_id) do
                {:ok, user} ->
                  case issue_jwt_for_user(user) do
                    {:ok, jwt, user_info} ->
                      conn
                      |> put_status(:ok)
                      |> json(%{
                        ok: true,
                        token: jwt,
                        socket_token: socket_token,
                        user: user_info
                      })

                    {:error, reason} ->
                      conn
                      |> put_status(:internal_server_error)
                      |> json(%{ok: false, error: "Failed to issue JWT: #{reason}"})
                  end

                {:error, reason} ->
                  conn
                  |> put_status(:unauthorized)
                  |> json(%{ok: false, error: reason})
              end
            end

          {:error, :expired} ->
            # Maybe it's already a JWT - try verifying as JWT
            case verify_token_and_load_user(token) do
              {:ok, user} ->
                st = Phoenix.Token.sign(SensoctoWeb.Endpoint, "user_socket", user.id)

                conn
                |> put_status(:ok)
                |> json(%{
                  ok: true,
                  token: token,
                  socket_token: st,
                  user: %{
                    id: user.id,
                    email: user.email,
                    display_name: Map.get(user, :display_name) || user.email
                  }
                })

              {:error, _} ->
                conn
                |> put_status(:unauthorized)
                |> json(%{ok: false, error: "Token expired"})
            end

          {:error, reason} ->
            # Not a Phoenix.Token — try as JWT directly
            case verify_token_and_load_user(token) do
              {:ok, user} ->
                st = Phoenix.Token.sign(SensoctoWeb.Endpoint, "user_socket", user.id)

                conn
                |> put_status(:ok)
                |> json(%{
                  ok: true,
                  token: token,
                  socket_token: st,
                  user: %{
                    id: user.id,
                    email: user.email,
                    display_name: Map.get(user, :display_name) || user.email
                  }
                })

              {:error, jwt_reason} ->
                Logger.warning(
                  "Token exchange failed: Phoenix.Token=#{inspect(reason)}, JWT=#{jwt_reason}"
                )

                conn
                |> put_status(:unauthorized)
                |> json(%{ok: false, error: "Invalid token"})
            end
        end
    end
  end

  defp load_user_by_id(user_id) when is_binary(user_id) do
    SensoctoWeb.Auth.TokenVerifier.load_user(user_id)
  end

  # Issue a JWT for a user (works for both Ash structs and plain maps)
  defp issue_jwt_for_user(%{id: id} = user) do
    # Try Ash JWT first
    case Ash.get(Sensocto.Accounts.User, id) do
      {:ok, ash_user} ->
        case AshAuthentication.Jwt.token_for_user(ash_user) do
          {:ok, token, _claims} ->
            {:ok, token,
             %{
               id: ash_user.id,
               email: ash_user.email,
               display_name: Map.get(ash_user, :display_name) || ash_user.email
             }}

          {:error, reason} ->
            {:error, inspect(reason)}
        end

      {:error, _} ->
        # Guest user - generate a Phoenix.Token with long expiry as fallback
        token =
          Phoenix.Token.sign(SensoctoWeb.Endpoint, "mobile_auth", %{
            user_id: id,
            email: Map.get(user, :email, "unknown"),
            exp: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30 * 24 * 3600, :second)),
            iat: DateTime.to_unix(DateTime.utc_now())
          })

        {:ok, token,
         %{
           id: id,
           email: Map.get(user, :email, "unknown"),
           display_name: Map.get(user, :display_name) || Map.get(user, :email, "unknown")
         }}
    end
  end

  # Extract token from "Bearer <token>" header
  defp extract_bearer_token("Bearer " <> token), do: token
  defp extract_bearer_token("bearer " <> token), do: token
  defp extract_bearer_token(_), do: nil
end
