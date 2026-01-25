defmodule SensoctoWeb.Plugs.AuthenticatedTidewave do
  @moduledoc """
  A plug that wraps Tidewave with authentication for production use.

  This plug intercepts requests to `/tidewave/*` and requires valid credentials
  before delegating to the actual Tidewave plug. Non-tidewave requests pass through
  unchanged.

  ## Configuration

  Environment variables:
  - `ENABLE_TIDEWAVE` - Set to "true" to enable Tidewave (runtime check)
  - `TIDEWAVE_USER` - The username for Basic Auth
  - `TIDEWAVE_PASS` - The password for Basic Auth
  - `TIDEWAVE_API_KEY` - Optional API key for header-based auth (easier for MCP clients)

  ## Authentication Methods

  The plug supports two authentication methods (in order of preference):

  1. **API Key** (recommended for MCP clients): Set `X-Tidewave-Key` header
     or `api_key` query parameter to match `TIDEWAVE_API_KEY`

  2. **Basic Auth** (for browser access): Standard HTTP Basic Authentication
     using `TIDEWAVE_USER` and `TIDEWAVE_PASS`

  ## Usage

  In your endpoint.ex:

      plug SensoctoWeb.Plugs.AuthenticatedTidewave,
        allow_remote_access: true,
        allowed_origins: ["https://your-app.fly.dev"]

  For MCP client configuration, use URL with api_key parameter:

      https://your-app.fly.dev/tidewave/mcp?api_key=YOUR_API_KEY

  ## Security Notes

  - Uses `Plug.Crypto.secure_compare/2` for timing-attack resistant comparison
  - API key auth is checked first (for MCP clients without Basic Auth support)
  - Falls back to Basic Auth (for browser access)
  - All Tidewave options (allow_remote_access, allowed_origins, etc.) are passed through
  """

  @behaviour Plug

  require Logger

  @doc false
  def init(opts) do
    Tidewave.init(opts)
  end

  @doc false
  def call(%Plug.Conn{path_info: ["tidewave" | _]} = conn, opts) do
    if tidewave_enabled?() do
      case authenticate(conn) do
        :ok ->
          Logger.info("[Tidewave] Authenticated access from #{inspect(conn.remote_ip)}")
          Tidewave.call(conn, opts)

        :error ->
          Logger.warning(
            "[Tidewave] Failed authentication attempt from #{inspect(conn.remote_ip)}"
          )

          conn
          |> Plug.BasicAuth.request_basic_auth(realm: "Tidewave")
          |> Plug.Conn.halt()
      end
    else
      conn
      |> Plug.Conn.send_resp(404, "Not Found")
      |> Plug.Conn.halt()
    end
  end

  def call(conn, opts) do
    if tidewave_enabled?() do
      Tidewave.call(conn, opts)
    else
      conn
    end
  end

  defp tidewave_enabled? do
    Application.get_env(:sensocto, :enable_tidewave, false)
  end

  defp authenticate(conn) do
    cond do
      authenticate_api_key(conn) == :ok ->
        :ok

      authenticate_basic_auth(conn) == :ok ->
        :ok

      true ->
        :error
    end
  end

  defp authenticate_api_key(conn) do
    configured_key = System.get_env("TIDEWAVE_API_KEY")

    if is_nil(configured_key) or configured_key == "" do
      :error
    else
      provided_key = get_api_key(conn)

      if provided_key && secure_compare(provided_key, configured_key) do
        :ok
      else
        :error
      end
    end
  end

  defp get_api_key(conn) do
    case Plug.Conn.get_req_header(conn, "x-tidewave-key") do
      [key | _] ->
        key

      [] ->
        conn = Plug.Conn.fetch_query_params(conn)
        conn.query_params["api_key"]
    end
  end

  defp authenticate_basic_auth(conn) do
    configured_user = System.get_env("TIDEWAVE_USER")
    configured_pass = System.get_env("TIDEWAVE_PASS")

    cond do
      is_nil(configured_user) or is_nil(configured_pass) ->
        :error

      true ->
        case Plug.BasicAuth.parse_basic_auth(conn) do
          {user, pass} ->
            if secure_compare(user, configured_user) and secure_compare(pass, configured_pass) do
              :ok
            else
              :error
            end

          :error ->
            :error
        end
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(_, _), do: false
end
