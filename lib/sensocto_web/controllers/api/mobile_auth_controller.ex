defmodule SensoctoWeb.Api.MobileAuthController do
  @moduledoc """
  API controller for mobile device authentication.

  Provides endpoints for mobile apps to verify authentication tokens
  and retrieve user information.
  """
  use SensoctoWeb, :controller
  require Logger

  # Catch any crashes and return a proper error
  def call(conn, opts) do
    super(conn, opts)
  rescue
    e ->
      Logger.error("Mobile auth controller crashed: #{inspect(e)}")
      Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        ok: false,
        error: "Internal server error during authentication"
      })
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
            Logger.info("Manually verifying bearer token, length: #{String.length(token)}")

            case verify_token_and_load_user(token) do
              {:ok, user} ->
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

              {:error, reason} ->
                Logger.warning("Mobile auth verification failed: #{reason}")

                conn
                |> put_status(:unauthorized)
                |> json(%{ok: false, error: reason})
            end
        end

      user ->
        Logger.info(
          "Mobile auth verification succeeded for user #{user.id} (via load_from_bearer)"
        )

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
    Logger.info("Debug verify called with token length: #{String.length(token)}")

    if token == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{ok: false, error: "No token provided"})
    else
      # Try to verify the token and load user
      case verify_token_and_load_user(token) do
        {:ok, user} ->
          Logger.info("Debug verify succeeded for user: #{user.id}")

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
      |> json(%{ok: false, error: "Crash: #{inspect(e)}"})
  end

  # Verify JWT token and load the user from database
  defp verify_token_and_load_user(token) do
    # First, verify the JWT signature and get claims
    Logger.info("Attempting JWT verification, token length: #{String.length(token)}")
    result = AshAuthentication.Jwt.verify(token, Sensocto.Accounts.User)
    Logger.info("JWT verify raw result: #{inspect(result, limit: 500)}")

    case result do
      # Returned {:ok, claims_map, resource_module} - this is the actual format!
      {:ok, %{"sub" => _} = claims, _resource} ->
        load_user_from_claims(claims)

      # Returned {:ok, user, claims}
      {:ok, %{id: _} = user, _claims} ->
        {:ok, user}

      # Returned {:ok, user}
      {:ok, %{id: _} = user} ->
        {:ok, user}

      # Returned {:ok, claims_map}
      {:ok, %{"sub" => _} = claims} ->
        load_user_from_claims(claims)

      # Returned {:error, reason}
      {:error, reason} ->
        {:error, "Token verification failed: #{inspect(reason)}"}

      # Returned bare :error - usually means expired or invalid signature
      :error ->
        {:error, "Token verification failed (token may be expired or invalid)"}

      # Returned claims map directly (no :ok wrapper)
      %{"sub" => _} = claims ->
        load_user_from_claims(claims)

      other ->
        {:error, "Unexpected verification result: #{inspect(other)}"}
    end
  end

  # Load user from JWT claims
  defp load_user_from_claims(claims) do
    # The "sub" claim contains "user?id=UUID"
    sub = claims["sub"] || claims[:sub]
    Logger.info("Loading user from sub claim: #{inspect(sub)}")

    case parse_user_id_from_subject(sub) do
      {:ok, user_id} ->
        Logger.info("Parsed user ID: #{user_id}")

        # Try to load via Ash.get with string ID
        Logger.info("Attempting Ash.get with string ID...")
        result = Ash.get(Sensocto.Accounts.User, user_id)
        Logger.info("Ash.get result: #{inspect(result)}")

        case result do
          {:ok, user} ->
            {:ok, user}

          {:error, reason} ->
            # Ash.get failed, try listing all users
            Logger.info("Ash.get failed: #{inspect(reason)}")
            Logger.info("Trying to list all users...")
            try_load_user_by_filter(user_id)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Try loading user by filtering on ID
  defp try_load_user_by_filter(user_id) do
    Logger.info("Trying to load user by ID: #{user_id}")

    # Direct Ecto query - bypass all Ash policies
    # Cast id to text to get string UUID instead of binary
    import Ecto.Query

    query =
      from u in "users",
        where: u.id == type(^user_id, :binary_id),
        select: %{id: type(u.id, :string), email: u.email}

    case Sensocto.Repo.all(query) do
      [user_data] ->
        Logger.info("Found user via direct SQL: #{inspect(user_data)}")
        # Return a struct-like map, using email as display_name fallback
        {:ok, %{id: user_data.id, email: user_data.email, display_name: user_data.email}}

      [] ->
        # List all user IDs for debugging
        all_query = from u in "users", select: type(u.id, :string)
        all_ids = Sensocto.Repo.all(all_query)
        {:error, "User not found. DB has #{length(all_ids)} users: #{inspect(all_ids)}"}

      multiple ->
        Logger.warning("Multiple users found: #{length(multiple)}")
        user_data = hd(multiple)
        {:ok, %{id: user_data.id, email: user_data.email, display_name: user_data.email}}
    end
  rescue
    e ->
      Logger.error("Direct SQL query failed: #{inspect(e)}")
      {:error, "Database query failed: #{Exception.message(e)}"}
  end

  # Parse user ID from subject claim like "user?id=UUID"
  defp parse_user_id_from_subject(nil), do: {:error, "No subject claim in token"}

  defp parse_user_id_from_subject(sub) when is_binary(sub) do
    # Subject format: "user?id=2672b29b-4c43-44f2-a052-b578e32d0b9c"
    case Regex.run(~r/id=([0-9a-f-]+)/i, sub) do
      [_, uuid] -> {:ok, uuid}
      nil -> {:error, "Could not parse user ID from subject: #{sub}"}
    end
  end

  defp parse_user_id_from_subject(sub), do: {:error, "Invalid subject format: #{inspect(sub)}"}

  # Extract token from "Bearer <token>" header
  defp extract_bearer_token("Bearer " <> token), do: token
  defp extract_bearer_token("bearer " <> token), do: token
  defp extract_bearer_token(_), do: nil
end
