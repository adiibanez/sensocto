defmodule SensoctoWeb.Api.RoomController do
  @moduledoc """
  API controller for room operations.

  Provides REST endpoints for:
  - GET /api/rooms - list user's rooms
  - GET /api/rooms/public - list public rooms
  - GET /api/rooms/:id - get room details
  """
  use SensoctoWeb, :controller
  require Logger

  alias Sensocto.Rooms
  alias Sensocto.RoomStore

  @doc """
  GET /api/rooms

  Lists rooms the authenticated user is a member of.
  Requires authentication.
  """
  def index(conn, _params) do
    case get_current_user(conn) do
      {:ok, user} ->
        Logger.info("Listing rooms for user: #{user.id}")
        rooms = Rooms.list_user_rooms(user)
        Logger.info("Found #{length(rooms)} user rooms")
        json(conn, %{rooms: Enum.map(rooms, &room_to_json/1)})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/rooms/public

  Lists all public rooms.
  Requires authentication.
  """
  def public(conn, _params) do
    case get_current_user(conn) do
      {:ok, _user} ->
        Logger.info("Listing public rooms")
        rooms = Rooms.list_public_rooms()
        Logger.info("Found #{length(rooms)} public rooms")
        json(conn, %{rooms: Enum.map(rooms, &room_to_json/1)})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/rooms/:id

  Gets details for a specific room.
  Requires authentication and room membership.
  """
  def show(conn, %{"id" => room_id}) do
    case get_current_user(conn) do
      {:ok, user} ->
        case Rooms.get_room(room_id) do
          {:ok, room} ->
            # Check if user is a member
            if RoomStore.is_member?(room_id, user.id) or room.is_public do
              json(conn, %{room: room_to_json(room)})
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Not a member of this room"})
            end

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Room not found"})
        end

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_current_user(conn) do
    # Get token from Authorization header
    auth_header = Plug.Conn.get_req_header(conn, "authorization")

    token = case auth_header do
      ["Bearer " <> t] -> t
      [t] -> t  # Try without Bearer prefix
      _ -> nil
    end

    if token do
      verify_token_and_load_user(token)
    else
      {:error, "Missing authorization header"}
    end
  end

  # Verify JWT token and load the user - same pattern as MobileAuthController
  defp verify_token_and_load_user(token) do
    Logger.debug("Verifying token for room API, length: #{String.length(token)}")
    result = AshAuthentication.Jwt.verify(token, Sensocto.Accounts.User)

    case result do
      # Returned {:ok, claims_map, resource_module}
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

      # Returned bare :error
      :error ->
        {:error, "Token verification failed (token may be expired or invalid)"}

      # Returned claims map directly
      %{"sub" => _} = claims ->
        load_user_from_claims(claims)

      other ->
        {:error, "Unexpected verification result: #{inspect(other)}"}
    end
  end

  # Load user from JWT claims
  defp load_user_from_claims(claims) do
    sub = claims["sub"] || claims[:sub]

    case parse_user_id_from_subject(sub) do
      {:ok, user_id} ->
        case Ash.get(Sensocto.Accounts.User, user_id) do
          {:ok, user} -> {:ok, user}
          {:error, _} -> load_user_by_query(user_id)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_user_id_from_subject(nil), do: {:error, "No subject in token"}
  defp parse_user_id_from_subject(sub) when is_binary(sub) do
    # Subject is in format "user?id=UUID"
    case Regex.run(~r/id=([a-f0-9-]+)/i, sub) do
      [_, id] -> {:ok, id}
      _ ->
        # Maybe it's just the UUID directly
        if String.match?(sub, ~r/^[a-f0-9-]+$/i) do
          {:ok, sub}
        else
          {:error, "Could not parse user ID from subject: #{sub}"}
        end
    end
  end

  defp load_user_by_query(user_id) do
    import Ecto.Query
    query = from u in "users",
      where: u.id == type(^user_id, :binary_id),
      select: %{id: type(u.id, :string), email: u.email}

    case Sensocto.Repo.all(query) do
      [user_data] ->
        {:ok, %{id: user_data.id, email: user_data.email, display_name: user_data.email}}
      _ ->
        {:error, "User not found"}
    end
  end

  defp room_to_json(room) do
    %{
      id: room.id,
      name: room.name,
      description: Map.get(room, :description),
      owner_id: room.owner_id,
      join_code: Map.get(room, :join_code),
      is_public: Map.get(room, :is_public, false),
      is_persisted: Map.get(room, :is_persisted, false),
      calls_enabled: Map.get(room, :calls_enabled, false),
      media_playback_enabled: Map.get(room, :media_playback_enabled, false),
      object_3d_enabled: Map.get(room, :object_3d_enabled, false),
      created_at: Map.get(room, :created_at),
      updated_at: Map.get(room, :updated_at),
      sensors: Enum.map(Map.get(room, :sensors, []) || [], &sensor_to_json/1),
      member_count: length(Map.get(room, :members, []) || [])
    }
  end

  defp sensor_to_json(sensor) do
    %{
      sensor_id: Map.get(sensor, :sensor_id) || Map.get(sensor, :id),
      sensor_name: Map.get(sensor, :sensor_name) || Map.get(sensor, :name) || "Unknown",
      sensor_type: Map.get(sensor, :sensor_type) || "generic",
      connector_id: Map.get(sensor, :connector_id) || Map.get(sensor, :user_id),
      connector_name: Map.get(sensor, :connector_name) || "Unknown",
      activity_status: Map.get(sensor, :activity_status) || "unknown",
      attributes: Enum.map(Map.get(sensor, :attributes, []) || [], &attribute_to_json/1)
    }
  end

  defp attribute_to_json(attr) do
    %{
      id: Map.get(attr, :id) || Ecto.UUID.generate(),
      attribute_type: Map.get(attr, :attribute_type) || Map.get(attr, :type),
      attribute_name: Map.get(attr, :attribute_name) || Map.get(attr, :name) || Map.get(attr, :attribute_type) || Map.get(attr, :type),
      last_value: Map.get(attr, :last_value),
      last_updated: Map.get(attr, :last_updated) || Map.get(attr, :last_updated_at)
    }
  end
end
