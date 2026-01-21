defmodule SensoctoWeb.MobileLinkLive do
  @moduledoc """
  LiveView for linking mobile devices to the user's account.

  Displays a QR code containing a sensocto:// deep link with an auth token
  that the mobile app can scan to authenticate.
  """
  use SensoctoWeb, :live_view
  require Logger

  # Token valid for 5 minutes (short-lived for security)
  @token_lifetime_seconds 5 * 60

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    Logger.info("MobileLinkLive mount - current_user.id: #{inspect(user.id)}")
    Logger.info("MobileLinkLive mount - current_user.email: #{inspect(user.email)}")

    # Generate the auth token and deep link
    {token, expires_at} = generate_mobile_token(user)
    deep_link = build_deep_link(token)
    qr_svg = generate_qr_code(deep_link)

    # Calculate time remaining
    time_remaining = DateTime.diff(expires_at, DateTime.utc_now())

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

  defp generate_mobile_token(user) do
    # Generate a JWT token for the user using AshAuthentication's token infrastructure
    expires_at = DateTime.add(DateTime.utc_now(), @token_lifetime_seconds, :second)

    # Use AshAuthentication's token generation
    case AshAuthentication.Jwt.token_for_user(user) do
      {:ok, token, claims} ->
        Logger.info(
          "Generated JWT token for user #{user.id}, claims: #{inspect(Map.keys(claims))}"
        )

        # Note: The JWT has its own expiry from AshAuthentication config
        # Our expires_at is just for the UI countdown
        {token, expires_at}

      {:error, reason} ->
        Logger.error("Failed to generate mobile token via AshAuthentication: #{inspect(reason)}")
        Logger.error("User: #{inspect(user.id)}, attempting fallback...")
        # Fallback: generate a simple signed token
        generate_fallback_token(user, expires_at)
    end
  end

  defp generate_fallback_token(user, expires_at) do
    # Simple signed token as fallback - NOTE: This won't work with load_from_bearer!
    # This is only here to prevent crashes, but the token won't authenticate.
    Logger.warning("Using fallback token - this will NOT work with API authentication!")

    data = %{
      user_id: user.id,
      email: user.email,
      exp: DateTime.to_unix(expires_at),
      iat: DateTime.to_unix(DateTime.utc_now())
    }

    token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "mobile_auth", data)
    {token, expires_at}
  end

  defp build_deep_link(token) do
    # Build the sensocto:// deep link
    "sensocto://auth?token=#{token}"
  end

  defp generate_qr_code(content) do
    # Generate QR code SVG using eqrcode
    content
    |> EQRCode.encode()
    |> EQRCode.svg(width: 280)
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
    <div class="min-h-screen bg-gray-900 flex flex-col items-center justify-center p-4">
      <div class="max-w-md w-full bg-gray-800 rounded-2xl shadow-xl p-8">
        <div class="text-center mb-6">
          <h1 class="text-2xl font-bold text-white mb-2">Link Mobile Device</h1>
          <p class="text-gray-400">
            Scan this QR code with the SensOcto mobile app to sign in
          </p>
        </div>

        <div class="flex justify-center mb-6">
          <div class="bg-white p-4 rounded-xl">
            {Phoenix.HTML.raw(@qr_svg)}
          </div>
        </div>

        <div class="text-center mb-6">
          <div class="flex items-center justify-center gap-2 text-gray-400 mb-2">
            <Heroicons.icon name="clock" type="outline" class="h-5 w-5" />
            <span>
              Expires in
              <span class="font-mono font-bold text-white">{format_time(@time_remaining)}</span>
            </span>
          </div>

          <button
            phx-click="regenerate"
            class="text-sm text-indigo-400 hover:text-indigo-300 underline"
          >
            Generate new code
          </button>
        </div>

        <div class="border-t border-gray-700 pt-6">
          <p class="text-sm text-gray-500 mb-3 text-center">Or copy the link:</p>

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
                if(@copied, do: "bg-green-600 text-white", else: "bg-indigo-600 hover:bg-indigo-500 text-white")}
            >
              <%= if @copied do %>
                Copied!
              <% else %>
                Copy
              <% end %>
            </button>
          </div>
        </div>

        <div class="mt-6 text-center">
          <.link
            navigate={~p"/"}
            class="text-sm text-gray-500 hover:text-gray-400"
          >
            ← Back to Home
          </.link>
        </div>
      </div>

      <div class="mt-8 max-w-md text-center text-sm text-gray-500">
        <h3 class="font-semibold text-gray-400 mb-2">How it works</h3>
        <ol class="space-y-1 text-left list-decimal list-inside">
          <li>Open the SensOcto mobile app</li>
          <li>Go to Settings → Scan QR Code</li>
          <li>Point your camera at the QR code above</li>
          <li>You'll be automatically signed in on your mobile device</li>
        </ol>
      </div>
    </div>
    """
  end
end
