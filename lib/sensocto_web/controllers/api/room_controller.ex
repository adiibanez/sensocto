defmodule SensoctoWeb.Api.RoomController do
  @moduledoc """
  API controller for room operations.

  Provides REST endpoints for:
  - GET /api/rooms - list user's rooms
  - GET /api/rooms/public - list public rooms
  - GET /api/rooms/:id - get room details
  """
  use SensoctoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias Sensocto.Rooms
  alias Sensocto.RoomStore
  alias SensoctoWeb.Schemas.{Common, Room}

  tags(["Rooms"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "List user's rooms",
    description: "Lists all rooms the authenticated user is a member of.",
    responses: [
      ok: {"List of rooms", "application/json", Room.RoomListResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error}
    ]
  )

  operation(:public,
    summary: "List public rooms",
    description: "Lists all public rooms available on the platform.",
    responses: [
      ok: {"List of public rooms", "application/json", Room.RoomListResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error}
    ]
  )

  operation(:show,
    summary: "Get room details",
    description: "Gets details for a specific room. Requires authentication and room membership.",
    parameters: [
      id: [in: :path, description: "Room UUID", type: :string, required: true]
    ],
    responses: [
      ok: {"Room details", "application/json", Room.RoomResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error},
      forbidden: {"Not a member of this room", "application/json", Common.Error},
      not_found: {"Room not found", "application/json", Common.Error}
    ]
  )

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

    token =
      case auth_header do
        ["Bearer " <> t] -> t
        # Try without Bearer prefix
        [t] -> t
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
      [_, id] ->
        {:ok, id}

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

    query =
      from u in "users",
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
      sensors: resolve_room_sensors(room),
      member_count: room |> Map.get(:members, %{}) |> map_size()
    }
  end

  # Resolve sensor_ids (MapSet of UUIDs) to sensor state data.
  # In-memory rooms store sensor_ids, not full sensor objects.
  defp resolve_room_sensors(room) do
    sensor_ids =
      case Map.get(room, :sensor_ids) do
        %MapSet{} = set -> MapSet.to_list(set)
        list when is_list(list) -> list
        _ -> []
      end

    # Fall back to :sensors if present (e.g. from Ash/DB-backed rooms)
    if sensor_ids == [] do
      Enum.map(Map.get(room, :sensors, []) || [], &sensor_to_json/1)
    else
      Enum.map(sensor_ids, fn sensor_id ->
        case Sensocto.SensorsDynamicSupervisor.get_sensor_state(sensor_id, :view, 1) do
          %{} = wrapper when map_size(wrapper) > 0 ->
            # get_sensor_state returns %{"sensor_id" => sensor_state_map}
            sensor_state = wrapper |> Map.values() |> List.first()
            sensor_to_json(sensor_state)

          _ ->
            %{
              sensor_id: to_string(sensor_id),
              sensor_name: "Unknown",
              sensor_type: "generic",
              connector_id: nil,
              connector_name: "Unknown",
              activity_status: "offline",
              attributes: []
            }
        end
      end)
    end
  end

  defp sensor_to_json(sensor) do
    attrs = Map.get(sensor, :attributes, %{}) || %{}

    attributes_list =
      case attrs do
        # View state format: %{"heartrate" => %{attribute_type: ..., lastvalue: ...}}
        m when is_map(m) and not is_struct(m) ->
          Enum.map(m, fn {attr_name, attr_data} ->
            attribute_to_json(attr_name, attr_data)
          end)

        # List format from Ash/DB
        l when is_list(l) ->
          Enum.map(l, fn attr -> attribute_to_json(attr) end)

        _ ->
          []
      end

    %{
      sensor_id: Map.get(sensor, :sensor_id) || Map.get(sensor, :id),
      sensor_name: Map.get(sensor, :sensor_name) || Map.get(sensor, :name) || "Unknown",
      sensor_type: to_string(Map.get(sensor, :sensor_type) || "generic"),
      connector_id: Map.get(sensor, :connector_id) || Map.get(sensor, :user_id),
      connector_name: Map.get(sensor, :connector_name) || "Unknown",
      activity_status: to_string(Map.get(sensor, :activity_status) || "unknown"),
      attributes: attributes_list
    }
  end

  # View state format: attribute name + data map
  defp attribute_to_json(attr_name, attr_data) when is_map(attr_data) do
    %{
      id: Map.get(attr_data, :attribute_id) || attr_name,
      attribute_type: to_string(Map.get(attr_data, :attribute_type) || attr_name),
      attribute_name: attr_name,
      last_value: Map.get(attr_data, :lastvalue),
      last_updated: nil
    }
  end

  # DB/Ash format: single map with all fields
  defp attribute_to_json(attr) when is_map(attr) do
    %{
      id: Map.get(attr, :id) || Ecto.UUID.generate(),
      attribute_type: to_string(Map.get(attr, :attribute_type) || Map.get(attr, :type)),
      attribute_name:
        Map.get(attr, :attribute_name) || Map.get(attr, :name) || to_string(Map.get(attr, :attribute_type) ||
          Map.get(attr, :type)),
      last_value: Map.get(attr, :last_value),
      last_updated: Map.get(attr, :last_updated) || Map.get(attr, :last_updated_at)
    }
  end
end
