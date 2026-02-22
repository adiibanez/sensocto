defmodule SensoctoWeb.Plugs.ApiCookieAuth do
  @moduledoc """
  Plug that reads JWT from an HttpOnly cookie as a fallback for Bearer auth.

  Checks for a `sensocto_api_token` cookie and, if found, sets the token
  in the Authorization header so `load_from_bearer` can pick it up.
  """

  import Plug.Conn

  @cookie_name "sensocto_api_token"
  @cookie_opts [
    http_only: true,
    secure: true,
    same_site: "Lax",
    max_age: 30 * 24 * 60 * 60,
    path: "/api"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only add cookie auth if no Bearer token is present
    case get_req_header(conn, "authorization") do
      [] ->
        conn = fetch_cookies(conn)

        case conn.cookies[@cookie_name] do
          nil -> conn
          token -> put_req_header(conn, "authorization", "Bearer #{token}")
        end

      _ ->
        conn
    end
  end

  @doc """
  Set the API token cookie on a response.
  """
  def set_token_cookie(conn, token) do
    put_resp_cookie(conn, @cookie_name, token, @cookie_opts)
  end

  @doc """
  Clear the API token cookie.
  """
  def clear_token_cookie(conn) do
    delete_resp_cookie(conn, @cookie_name, @cookie_opts)
  end

  @doc """
  Returns the cookie name for external reference.
  """
  def cookie_name, do: @cookie_name
end
