defmodule SensoctoWeb.Api.RoomTicketController do
  @moduledoc """
  API controller for generating room tickets for P2P connections.

  Provides endpoints for mobile apps to get room tickets for joining
  rooms via P2P (Iroh gossip + docs).
  """
  use SensoctoWeb, :controller
  require Logger

  alias Sensocto.Rooms
  alias Sensocto.P2P.RoomTicket

  @doc """
  Generate a room ticket by room ID.

  GET /api/rooms/:id/ticket

  Requires authentication. User must be a member of the room.

  Query params:
    - include_secret: "true" to include write secret (owner/admin only)
    - expires_in: seconds until expiry (default: 86400 = 24 hours)

  Response:
    {
      "ok": true,
      "ticket": {
        "room_id": "uuid",
        "room_name": "Room Name",
        "docs_namespace": "hex string",
        "gossip_topic": "hex string",
        "bootstrap_peers": [...],
        "relay_url": "https://...",
        "created_at": unix_timestamp,
        "expires_at": unix_timestamp
      },
      "encoded": "base64 encoded ticket",
      "deep_link": "sensocto://room?ticket=...",
      "web_url": "https://.../?ticket=..."
    }
  """
  def show(conn, %{"id" => room_id} = params) do
    user = conn.assigns[:current_user]

    case Rooms.get_room(room_id) do
      {:ok, room} ->
        if can_access_ticket?(room, user) do
          generate_ticket_response(conn, room, user, params)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{ok: false, error: "You must be a member of this room"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Room not found"})
    end
  end

  @doc """
  Generate a room ticket by join code.

  GET /api/rooms/by-code/:code/ticket

  Does not require authentication - anyone with the code can get a ticket.
  However, the ticket will have limited permissions (no write secret).

  Response format same as show/2.
  """
  def show_by_code(conn, %{"code" => code} = params) do
    case Rooms.get_room_by_code(code) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Room not found"})

      {:ok, room} ->
        # No user for code-based access - never include secret
        params = Map.put(params, "include_secret", "false")
        generate_ticket_response(conn, room, nil, params)

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Room not found"})
    end
  end

  @doc """
  Verify and decode a ticket.

  POST /api/rooms/verify-ticket

  Body:
    {"ticket": "base64 encoded ticket"}

  Response:
    {
      "ok": true,
      "valid": true,
      "expired": false,
      "ticket": { ... decoded ticket ... }
    }
  """
  def verify(conn, %{"ticket" => encoded}) do
    case RoomTicket.from_base64(encoded) do
      {:ok, ticket} ->
        expired = RoomTicket.expired?(ticket)

        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          valid: true,
          expired: expired,
          ticket: RoomTicket.to_map(ticket)
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          ok: false,
          valid: false,
          error: "Invalid ticket: #{inspect(reason)}"
        })
    end
  end

  def verify(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{ok: false, error: "Missing 'ticket' parameter"})
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp can_access_ticket?(room, nil), do: room.is_public

  defp can_access_ticket?(room, user) do
    room.is_public || Rooms.member?(room, user)
  end

  defp can_include_secret?(_room, nil), do: false

  defp can_include_secret?(room, user) do
    Rooms.can_manage?(room, user)
  end

  defp generate_ticket_response(conn, room, user, params) do
    include_secret = params["include_secret"] == "true" && can_include_secret?(room, user)
    expires_in = parse_expires_in(params["expires_in"])

    opts = [
      include_secret: include_secret,
      expires_in: expires_in
    ]

    case RoomTicket.generate(room, opts) do
      {:ok, ticket} ->
        encoded = RoomTicket.to_base64(ticket)

        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          ticket: RoomTicket.to_map(ticket),
          encoded: encoded,
          deep_link: RoomTicket.to_deep_link(ticket),
          web_url: RoomTicket.to_web_url(ticket)
        })

      {:error, reason} ->
        Logger.error("Failed to generate room ticket: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{ok: false, error: "Failed to generate ticket"})
    end
  end

  defp parse_expires_in(nil), do: 24 * 60 * 60

  defp parse_expires_in(value) when is_binary(value) do
    case Integer.parse(value) do
      # Max 1 week
      {seconds, _} when seconds > 0 -> min(seconds, 7 * 24 * 60 * 60)
      _ -> 24 * 60 * 60
    end
  end

  defp parse_expires_in(value) when is_integer(value), do: min(value, 7 * 24 * 60 * 60)
  defp parse_expires_in(_), do: 24 * 60 * 60
end
