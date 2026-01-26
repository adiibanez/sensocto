defmodule SensoctoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sensocto

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  #
  # L-006 Security Fix: Reduced max_age from 365_378_432_000 (~11,580 years) to 30 days.
  # Long-lived session cookies increase the window for session hijacking attacks.
  # 30 days (2,592,000 seconds) balances security with user convenience.
  @session_options [
    store: :cookie,
    path: "/",
    key: "_sensocto_key",
    signing_salt: "4mNzZysc",
    same_site: "Lax",
    max_age: 2_592_000,
    http_only: true
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  socket "/socket", SensoctoWeb.UserSocket,
    websocket: true,
    longpoll: false

  # Bridge socket for iroh-bridge sidecar
  socket "/bridge", SensoctoWeb.BridgeSocket,
    websocket: true,
    longpoll: false

  # socket "/live", SensoctoWeb.UserSocket,
  #   websocket: [connect_info: [session: @session_options]],
  #   longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :sensocto,
    gzip: Mix.env() == :prod,
    only: SensoctoWeb.static_paths()

  # Tidewave AI debugging
  # In dev: enabled by default (no auth required for localhost)
  # In prod: requires ENABLE_TIDEWAVE=true and TIDEWAVE_USER/TIDEWAVE_PASS
  if Code.ensure_loaded?(Tidewave) do
    if Mix.env() == :prod do
      # Production: use authenticated wrapper with Basic Auth
      # Runtime check happens inside the plug
      plug SensoctoWeb.Plugs.AuthenticatedTidewave,
        allow_remote_access: true,
        allowed_origins: ["https://sensocto.fly.dev", "https://*.sensocto.fly.dev"]
    else
      # Development: no auth required (localhost only by default)
      plug Tidewave
    end
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    # LVN_ACTIVATION plug LiveViewNative.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :sensocto
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # Security headers
  plug :put_secure_browser_headers, %{
    "x-frame-options" => "SAMEORIGIN",
    "x-content-type-options" => "nosniff",
    "x-xss-protection" => "1; mode=block",
    "referrer-policy" => "strict-origin-when-cross-origin"
  }

  plug Plug.Session, @session_options
  plug SensoctoWeb.Router

  defp put_secure_browser_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      Plug.Conn.put_resp_header(conn, key, value)
    end)
  end
end
