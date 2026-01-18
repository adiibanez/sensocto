defmodule SensoctoWeb.Router do
  use SensoctoWeb, :router
  import Phoenix.LiveDashboard.Router
  import AshAdmin.Router
  use AshAuthentication.Phoenix.Router
  alias SensoctoWeb.LiveUserAuth

  pipeline :browser do
    plug :accepts, [
      "html",
      "swiftui"
    ]

    plug :fetch_session
    plug :fetch_live_flash

    plug :put_root_layout,
      html: {SensoctoWeb.Layouts, :root},
      swiftui: {SensoctoWeb.Layouts.SwiftUI, :root}

    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session

    plug SensoctoWeb.Plugs.RequestLogger
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  # admin_browser_pipeline(:browser)

  pipeline :admins_only do
    plug :admin_basic_auth
  end

  scope "/", SensoctoWeb do
    pipe_through [:browser]

    live "/realitykit", RealitykitLive

    post "/lvn-auth", LvnController, :authenticate
    get "/lvn-auth", LvnController, :authenticate
    live "/lvn-signin", Live.LvnSigninLive, :index
    live "/iroh-gossip", Live.IrohGossipLive, :index

    # live "/users/:id", UserLive.Show, :show
    # live "/users/:id/show/edit", UserLive.Show, :edit

    # live "/sensors", SensorLive.Index, :index
    # live "/sensors/:id/edit", SensorLive.Index, :edit
    # live "/sensors/:id", SensorLive.Index, :show

    auth_routes(Controllers.AuthController, Sensocto.Accounts.User, path: "/auth")
    sign_out_route(Controllers.AuthController)

    # Prebuilt LiveViews for signing in, registration, resetting, etc.
    # Leave out `register_path` and `reset_path` if you don't want to support
    # user registration and/or password resets respectively.

    # live "/register", AuthIndex, :register
    # live "/sign-in", AuthIndex, :sign_in

    ash_authentication_live_session :authentication_required,
      on_mount: [
        {LiveUserAuth, :live_user_required},
        {SensoctoWeb.Live.Hooks.TrackVisitedPath, :default}
      ] do
      live "/playground", Live.PlaygroundLive, :index
      live "/lvn", Live.LvnEntryLive, :index
      live "/", IndexLive, :index
      live "/lobby", LobbyLive, :sensors
      live "/lobby/heartrate", LobbyLive, :heartrate
      live "/lobby/imu", LobbyLive, :imu
      live "/lobby/location", LobbyLive, :location
      live "/lobby/ecg", LobbyLive, :ecg
      live "/lobby/battery", LobbyLive, :battery
      live "/lobby/users", LobbyLive, :users
      live "/sense", SenseLive, :index
      live "/sensors", SensorLive.Index, :index
      live "/sensors/:id", SensorLive.Show, :show
      live "/sensors/:id/edit", SensorLive.Show, :edit

      live "/about", AboutLive, :index

      # Rooms
      live "/rooms", RoomListLive, :index
      live "/rooms/new", RoomListLive, :new
      live "/rooms/:id", RoomShowLive, :show
      live "/rooms/:id/settings", RoomShowLive, :settings

      # Simulator
      live "/simulator", SimulatorLive, :index
    end

    # Room join can be accessed without authentication (shows preview)
    # but requires auth to actually join
    ash_authentication_live_session :authentication_optional,
      on_mount: {LiveUserAuth, :live_user_optional} do
      live "/rooms/join/:code", RoomJoinLive, :join
    end

    sign_in_route(
      overrides: [SensoctoWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default],
      register_path: "/register",
      reset_path: "/reset",
      auth_routes_prefix: "/auth"
    )

    reset_route(auth_routes_prefix: "/auth")

    # Magic link confirmation page (for require_interaction? true)
    magic_sign_in_route(
      Sensocto.Accounts.User,
      :magic_link,
      auth_routes_prefix: "/auth",
      live_view: SensoctoWeb.MagicSignInLive,
      overrides: [SensoctoWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  scope "/admin", SensoctoWeb do
    pipe_through [:browser, :admins_only]

    live_dashboard "/dashboard",
      metrics: SensoctoWeb.Telemetry,
      additional_pages: [
        # broadway: BroadwayDashboard,
        sensors: Sensocto.LiveDashboard.SensorsPage
      ]
  end

  scope "/admin" do
    pipe_through [:browser, :admins_only]

    ash_admin "/ash-admin"
  end

  # Other scopes may use custom stacks.
  # scope "/api", SensoctoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  # if Application.compile_env(:sensocto, :dev_routes) do
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).

  scope "/dev" do
    pipe_through :browser
    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end

  # end

  defp admin_basic_auth(conn, _opts) do
    username = System.fetch_env!("AUTH_USERNAME")
    # fly secrets set AUTH_PASSWORD=nimda_1234
    password = System.fetch_env!("AUTH_PASSWORD")
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
