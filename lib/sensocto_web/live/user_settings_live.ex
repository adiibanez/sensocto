defmodule SensoctoWeb.UserSettingsLive do
  @moduledoc """
  LiveView for user settings and account management.

  Provides access to:
  - Profile information
  - Language preferences
  - Mobile device linking (QR code)
  - Account settings
  """
  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Accounts.UserPreferences

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  # Token valid for 5 minutes (short-lived for security)
  @token_lifetime_seconds 5 * 60

  # Available locales with native language names
  @locales [
    {"English", "en"},
    {"Deutsch", "de"},
    {"Schwiizerdütsch", "gsw"},
    {"Français", "fr"},
    {"Español", "es"},
    {"Português (Brasil)", "pt_BR"},
    {"中文", "zh"},
    {"日本語", "ja"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Generate the auth token and deep link for mobile linking
    {token, expires_at} = generate_mobile_token(user)
    deep_link = build_deep_link(token)
    qr_svg = generate_qr_code(deep_link)

    # Calculate time remaining
    time_remaining = DateTime.diff(expires_at, DateTime.utc_now())

    # Get current locale from socket or user preferences
    current_locale =
      socket.assigns[:locale] ||
        UserPreferences.get_ui_state(user.id, "locale", "en")

    # Schedule token refresh countdown
    if connected?(socket) do
      :timer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:token, token)
      |> assign(:deep_link, deep_link)
      |> assign(:qr_svg, qr_svg)
      |> assign(:expires_at, expires_at)
      |> assign(:time_remaining, time_remaining)
      |> assign(:copied, false)
      |> assign(:show_qr, false)
      |> assign(:current_locale, current_locale)
      |> assign(:locales, @locales)

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    time_remaining = DateTime.diff(socket.assigns.expires_at, DateTime.utc_now())

    socket =
      if time_remaining <= 0 do
        # Regenerate token
        user = socket.assigns.current_user
        {token, expires_at} = generate_mobile_token(user)
        deep_link = build_deep_link(token)
        qr_svg = generate_qr_code(deep_link)

        socket
        |> assign(:token, token)
        |> assign(:deep_link, deep_link)
        |> assign(:qr_svg, qr_svg)
        |> assign(:expires_at, expires_at)
        |> assign(:time_remaining, @token_lifetime_seconds)
      else
        assign(socket, :time_remaining, time_remaining)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    user = socket.assigns.current_user
    {token, expires_at} = generate_mobile_token(user)
    deep_link = build_deep_link(token)
    qr_svg = generate_qr_code(deep_link)

    socket =
      socket
      |> assign(:token, token)
      |> assign(:deep_link, deep_link)
      |> assign(:qr_svg, qr_svg)
      |> assign(:expires_at, expires_at)
      |> assign(:time_remaining, @token_lifetime_seconds)
      |> assign(:copied, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_link", _params, socket) do
    {:noreply, assign(socket, :copied, true)}
  end

  @impl true
  def handle_event("toggle_qr", _params, socket) do
    {:noreply, assign(socket, :show_qr, !socket.assigns.show_qr)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    user = socket.assigns.current_user

    # Save preference to database (no-op for guest users)
    UserPreferences.set_ui_state(user.id, "locale", locale)

    # Redirect with locale query param so the Locale plug updates session/cookie
    {:noreply, redirect(socket, to: "/settings?locale=#{locale}")}
  end

  defp generate_mobile_token(%{is_guest: true} = user) do
    # Guest users can't use AshAuthentication JWT - use fallback token
    expires_at = DateTime.add(DateTime.utc_now(), @token_lifetime_seconds, :second)
    generate_fallback_token(user, expires_at)
  end

  defp generate_mobile_token(user) do
    expires_at = DateTime.add(DateTime.utc_now(), @token_lifetime_seconds, :second)

    case AshAuthentication.Jwt.token_for_user(user) do
      {:ok, token, _claims} ->
        {token, expires_at}

      {:error, reason} ->
        Logger.error("Failed to generate mobile token: #{inspect(reason)}")
        generate_fallback_token(user, expires_at)
    end
  end

  defp generate_fallback_token(user, expires_at) do
    # Handle both Ash structs (with .email) and guest maps (with .display_name)
    email_or_name =
      case user do
        %{email: email} when is_binary(email) -> email
        %{display_name: name} when is_binary(name) -> name
        _ -> "unknown"
      end

    data = %{
      user_id: user.id,
      email: email_or_name,
      exp: DateTime.to_unix(expires_at),
      iat: DateTime.to_unix(DateTime.utc_now())
    }

    token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "mobile_auth", data)
    {token, expires_at}
  end

  defp build_deep_link(token) do
    "sensocto://auth?token=#{token}"
  end

  defp generate_qr_code(content) do
    content
    |> EQRCode.encode()
    |> EQRCode.svg(width: 200)
  end

  defp format_time(seconds) when seconds <= 0, do: "0:00"

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <h1 class="text-2xl font-bold text-white mb-6">{gettext("Settings")}</h1>

      <div class="space-y-6">
        <div class="bg-gray-800 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Heroicons.icon name="user-circle" type="outline" class="h-5 w-5 text-gray-400" /> {gettext(
              "Profile"
            )}
          </h2>
          <div class="space-y-4">
            <div>
              <label class="block text-sm text-gray-400 mb-1">
                {if Map.get(@current_user, :is_guest), do: gettext("Name"), else: gettext("Email")}
              </label>
              <div class="text-white">
                {Map.get(@current_user, :email) || Map.get(@current_user, :display_name, "Guest")}
              </div>
            </div>
            <div>
              <label class="block text-sm text-gray-400 mb-1">{gettext("Account ID")}</label>
              <div class="text-gray-300 font-mono text-sm">{@current_user.id}</div>
            </div>
          </div>
        </div>

        <div class="bg-gray-800 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Heroicons.icon name="language" type="outline" class="h-5 w-5 text-gray-400" /> {gettext(
              "Language"
            )}
          </h2>
          <div class="space-y-4">
            <p class="text-gray-400 text-sm">
              {gettext("Choose your preferred language for the application interface.")}
            </p>
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <button
                :for={{name, code} <- @locales}
                phx-click="change_locale"
                phx-value-locale={code}
                class={"px-4 py-2 rounded-lg text-sm font-medium transition-colors " <>
                  if(@current_locale == code,
                    do: "bg-indigo-600 text-white",
                    else: "bg-gray-700 hover:bg-gray-600 text-gray-300"
                  )}
              >
                {name}
              </button>
            </div>
          </div>
        </div>

        <div class="bg-gray-800 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Heroicons.icon name="device-phone-mobile" type="outline" class="h-5 w-5 text-gray-400" />
            {gettext("Link Mobile Device")}
          </h2>
          <p class="text-gray-400 text-sm mb-4">
            {gettext(
              "Scan the QR code with the SensOcto mobile app to sign in on your mobile device."
            )}
          </p>

          <button
            phx-click="toggle_qr"
            class="flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-colors mb-4"
          >
            <Heroicons.icon
              name={if @show_qr, do: "chevron-up", else: "qr-code"}
              type="outline"
              class="h-5 w-5"
            />
            {if @show_qr, do: gettext("Hide QR Code"), else: gettext("Show QR Code")}
          </button>

          <div :if={@show_qr} class="space-y-4">
            <div class="flex flex-col sm:flex-row gap-6 items-start">
              <div class="bg-white p-3 rounded-lg">
                {Phoenix.HTML.raw(@qr_svg)}
              </div>

              <div class="flex-1 space-y-4">
                <div class="flex items-center gap-2 text-gray-400 text-sm">
                  <Heroicons.icon name="clock" type="outline" class="h-4 w-4" />
                  <span>
                    {gettext("Expires in")}
                    <span class="font-mono font-bold text-white">{format_time(@time_remaining)}</span>
                  </span>
                </div>

                <button
                  phx-click="regenerate"
                  class="text-sm text-indigo-400 hover:text-indigo-300 underline"
                >
                  {gettext("Generate new code")}
                </button>

                <div>
                  <label class="block text-sm text-gray-400 mb-2">
                    {gettext("Or copy the link:")}
                  </label>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      value={@deep_link}
                      readonly
                      class="flex-1 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-gray-300 font-mono truncate"
                      id="deep-link-input"
                    />
                    <button
                      phx-click="copy_link"
                      phx-hook="CopyToClipboard"
                      data-copy-target="deep-link-input"
                      id="copy-btn"
                      class={"px-4 py-2 rounded-lg text-sm font-medium transition-colors " <>
                        if(@copied, do: "bg-green-600 text-white", else: "bg-gray-700 hover:bg-gray-600 text-white")}
                    >
                      {if @copied, do: gettext("Copied!"), else: gettext("Copy")}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div class="bg-gray-900 rounded-lg p-4 text-sm text-gray-400">
              <h4 class="font-semibold text-gray-300 mb-2">{gettext("How to link your device:")}</h4>
              <ol class="space-y-1 list-decimal list-inside">
                <li>{gettext("Open the SensOcto mobile app")}</li>
                <li>{gettext("Go to Settings and tap \"Scan QR Code\"")}</li>
                <li>{gettext("Point your camera at the QR code above")}</li>
                <li>{gettext("You'll be automatically signed in")}</li>
              </ol>
            </div>
          </div>
        </div>

        <div class="bg-gray-800 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Heroicons.icon name="cog-6-tooth" type="outline" class="h-5 w-5 text-gray-400" /> {gettext(
              "Account"
            )}
          </h2>
          <div class="space-y-4">
            <a
              href="/sign-out"
              class="inline-flex items-center gap-2 px-4 py-2 bg-red-600/20 hover:bg-red-600/30 text-red-400 rounded-lg transition-colors"
            >
              <Heroicons.icon name="arrow-right-on-rectangle" type="outline" class="h-5 w-5" />
              {gettext("Sign Out")}
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
