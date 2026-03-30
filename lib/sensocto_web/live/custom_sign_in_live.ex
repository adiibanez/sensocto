defmodule SensoctoWeb.CustomSignInLive do
  @moduledoc """
  Custom sign-in page that integrates the full About page content alongside the authentication form.
  Includes presence-tracked draggable balls for fun multi-user interaction.
  Uses the shared AboutContentComponent for consistent content.
  Background visualizes the N most active sensors in real-time with selectable themes.
  """
  use SensoctoWeb, :live_view
  alias AshAuthentication.Phoenix.Components
  alias SensoctoWeb.Sensocto.Presence
  alias SensoctoWeb.LiveHelpers.SensorBackground

  @presence_topic "signin_presence"
  @valid_themes ~w(off constellation waveform aurora particles)
  @cycle_themes ~w(constellation waveform aurora particles)
  @cycle_interval_ms 30_000
  @supported_locales ~w(en de gsw fr es pt_BR zh ja ar)
  @locale_labels [
    {"EN", "en"},
    {"DE", "de"},
    {"CH", "gsw"},
    {"FR", "fr"},
    {"ES", "es"},
    {"PT", "pt_BR"},
    {"中文", "zh"},
    {"日本", "ja"},
    {"عربي", "ar"}
  ]

  @impl true
  def mount(_params, session, socket) do
    # Check if user is already signed in as guest AND the guest still exists
    valid_guest? =
      session["is_guest"] == true and
        match?({:ok, _}, Sensocto.Accounts.GuestUserStore.get_guest(session["guest_id"]))

    if valid_guest? do
      {:ok, redirect(socket, to: ~p"/lobby")}
    else
      if connected?(socket) do
        # Presence for draggable balls
        Phoenix.PubSub.subscribe(Sensocto.PubSub, @presence_topic)

        # Sensor data for background visualization
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensors:global")

        send(self(), :init_sensor_bg)
      end

      # Set locale from session (Locale plug already parsed cookie/header/query)
      locale = session["locale"] || "en"
      Gettext.put_locale(SensoctoWeb.Gettext, locale)

      socket =
        socket
        |> assign(:page_title, "Sign In")
        |> assign(:show_about, true)
        |> assign(:locale, locale)
        |> assign(:locales, @locale_labels)
        # Ball presence state
        |> assign(:balls, %{})
        |> assign(:own_ball_id, nil)
        # Sensor background state
        |> assign(:sensor_activity, %{})
        |> assign(:sensor_bg_count, 8)
        |> assign(:sensor_bg_theme, "aurora")
        |> assign(:sensor_bg_cycling, false)

      {:ok, socket, layout: {SensoctoWeb.Layouts, :auth}}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    otp_app = socket.assigns[:otp_app] || :sensocto
    {:noreply, assign(socket, :otp_app, otp_app) |> assign(:params, params)}
  end

  @impl true
  def handle_event("toggle_about", _, socket) do
    {:noreply, assign(socket, show_about: !socket.assigns.show_about)}
  end

  @impl true
  def handle_event("join_as_guest", _params, socket) do
    case Sensocto.Accounts.GuestUserStore.create_guest() do
      {:ok, guest} ->
        {:noreply, redirect(socket, to: "/auth/guest/#{guest.id}/#{guest.token}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create guest session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("set_bg_count", %{"count" => count}, socket) do
    n = count |> String.to_integer() |> max(1) |> min(100)
    {:noreply, assign(socket, sensor_bg_count: n)}
  end

  @impl true
  def handle_event("set_bg_theme", %{"theme" => theme}, socket) when theme in @valid_themes do
    {:noreply,
     socket
     |> assign(:sensor_bg_theme, theme)
     |> assign(:sensor_bg_cycling, false)
     |> push_event("sensor_bg_theme_change", %{theme: theme})}
  end

  def handle_event("set_bg_theme", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_bg_cycle", _params, socket) do
    if socket.assigns.sensor_bg_cycling do
      {:noreply, assign(socket, :sensor_bg_cycling, false)}
    else
      Process.send_after(self(), :cycle_bg_theme, @cycle_interval_ms)
      {:noreply, assign(socket, :sensor_bg_cycling, true)}
    end
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    if locale in @supported_locales do
      {:noreply, redirect(socket, to: "/sign-in?locale=#{locale}")}
    else
      {:noreply, socket}
    end
  end

  # Ball presence event handlers
  @impl true
  def handle_event("ball_join", %{"session_id" => session_id}, socket) do
    user = socket.assigns[:current_user]
    ball_id = if user, do: "user:#{user.id}", else: "anon:#{session_id}"
    color = generate_color_from_id(ball_id)

    existing_count = map_size(Presence.list(@presence_topic))
    initial_y = 10.0 + existing_count * 8.0

    Presence.track(self(), @presence_topic, ball_id, %{
      x: 3.0,
      y: min(initial_y, 90.0),
      color: color,
      user_type: if(user, do: :authenticated, else: :anonymous)
    })

    presences = Presence.list(@presence_topic)
    balls = transform_presences_to_balls(presences)

    {:noreply,
     socket
     |> assign(:own_ball_id, ball_id)
     |> assign(:balls, balls)
     |> push_event("ball_sync", %{balls: balls, own_id: ball_id})}
  end

  @impl true
  def handle_event("ball_drag_start", _params, socket) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      @presence_topic,
      {:vibrate, socket.assigns.own_ball_id}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("ball_move", %{"x" => x, "y" => y}, socket) do
    ball_id = socket.assigns.own_ball_id

    if ball_id do
      Presence.update(self(), @presence_topic, ball_id, fn meta ->
        Map.merge(meta, %{x: x, y: y})
      end)
    end

    {:noreply, socket}
  end

  # --- Sensor background handle_info ---

  @impl true
  def handle_info(:init_sensor_bg, socket) do
    activity = SensorBackground.init_activity()
    SensorBackground.start_bg_tick()
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:measurement, %{sensor_id: sid}}, socket) do
    activity = SensorBackground.handle_measurement(socket.assigns.sensor_activity, sid)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:measurements_batch, {sid, measurements}}, socket) do
    activity =
      SensorBackground.handle_measurements_batch(
        socket.assigns.sensor_activity,
        sid,
        length(measurements)
      )

    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:sensor_online, sensor_id, _config}, socket) do
    activity = SensorBackground.handle_sensor_online(socket.assigns.sensor_activity, sensor_id)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:sensor_offline, sensor_id}, socket) do
    activity = SensorBackground.handle_sensor_offline(socket.assigns.sensor_activity, sensor_id)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info(:bg_tick, socket) do
    {sensors, decayed} =
      SensorBackground.compute_tick(
        socket.assigns.sensor_activity,
        socket.assigns.sensor_bg_count
      )

    SensorBackground.start_bg_tick()

    {:noreply,
     socket
     |> assign(:sensor_activity, decayed)
     |> push_event("sensor_bg_update", %{sensors: sensors})}
  end

  # --- Existing handle_info clauses ---

  @impl true
  def handle_info({:put_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  def handle_info({:vibrate, _ball_id}, socket) do
    {:noreply, push_event(socket, "vibrate", %{})}
  end

  @impl true
  def handle_info(:cycle_bg_theme, socket) do
    if socket.assigns.sensor_bg_cycling do
      current = socket.assigns.sensor_bg_theme
      idx = Enum.find_index(@cycle_themes, &(&1 == current)) || -1
      next = Enum.at(@cycle_themes, rem(idx + 1, length(@cycle_themes)))

      Process.send_after(self(), :cycle_bg_theme, @cycle_interval_ms)

      {:noreply,
       socket
       |> assign(:sensor_bg_theme, next)
       |> push_event("sensor_bg_theme_change", %{theme: next})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    balls = socket.assigns.balls

    balls =
      Enum.reduce(diff.leaves, balls, fn {key, _}, acc ->
        Map.delete(acc, key)
      end)

    balls =
      Enum.reduce(diff.joins, balls, fn {key, %{metas: [meta | _]}}, acc ->
        Map.put(acc, key, %{
          id: key,
          x: meta.x,
          y: meta.y,
          color: meta.color,
          user_type: meta.user_type
        })
      end)

    {:noreply,
     socket
     |> assign(:balls, balls)
     |> push_event("ball_update", %{balls: balls})}
  end

  defp generate_color_from_id(id) do
    hash = :erlang.phash2(id)
    hue = rem(hash * 137, 360)
    saturation = 70 + rem(hash, 20)
    lightness = 50 + rem(div(hash, 360), 15)
    "hsl(#{hue}, #{saturation}%, #{lightness}%)"
  end

  @doc false
  def auth_translate(msgid, bindings \\ []) do
    Gettext.dgettext(SensoctoWeb.Gettext, "default", msgid, Map.new(bindings))
  end

  defp transform_presences_to_balls(presences) do
    Enum.into(presences, %{}, fn {key, %{metas: [meta | _]}} ->
      {key,
       %{
         id: key,
         x: meta.x,
         y: meta.y,
         color: meta.color,
         user_type: meta.user_type
       }}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Sensor Background Visualization - behind everything --%>
    <div
      id="sensor-background"
      phx-hook="SensorBackgroundHook"
      class="fixed inset-0 z-0"
      phx-update="ignore"
    >
      <canvas class="w-full h-full"></canvas>
    </div>

    <%!-- Draggable Balls Container - positioned absolutely over the page --%>
    <div
      id="draggable-balls-container"
      phx-hook="DraggableBallsHook"
      class="fixed inset-0 pointer-events-none z-40"
      style="overflow: hidden;"
    >
    </div>

    <%!-- Background Controls — slide-out drawer from left edge --%>
    <div
      id="bg-controls-drawer"
      class="bg-controls-drawer fixed top-1/2 z-30 flex items-stretch"
    >
      <%!-- Panel --%>
      <div class="bg-gray-900/70 backdrop-blur-sm rounded-r-lg p-2 border border-l-0 border-gray-700/50 text-xs text-gray-400 space-y-2 shrink-0">
        <div class="flex items-center gap-1.5">
          <form phx-change="set_bg_count" class="flex items-center gap-1.5 flex-1">
            <input
              type="range"
              min="1"
              max="100"
              value={@sensor_bg_count}
              name="count"
              class="w-20 h-1 accent-cyan-500 cursor-pointer"
            />
            <span class="w-4 text-[10px] text-center text-gray-500">{@sensor_bg_count}</span>
          </form>
        </div>
        <div class="flex gap-0.5">
          <button
            :for={
              {label, theme, tip} <- [
                {"—", "off", gettext("No visualization")},
                {"✦", "constellation", gettext("Constellation")},
                {"≈", "waveform", gettext("Waveform")},
                {"◐", "aurora", gettext("Aurora")},
                {"⁘", "particles", gettext("Particles")}
              ]
            }
            phx-click="set_bg_theme"
            phx-value-theme={theme}
            data-tip={tip}
            class={"bg-tip relative w-6 h-6 rounded flex items-center justify-center text-[11px] transition-colors " <>
              if(@sensor_bg_theme == theme,
                do: (if theme == "off", do: "bg-gray-600 text-white", else: "bg-cyan-600 text-white"),
                else: "bg-gray-700/50 hover:bg-gray-600/50 text-gray-400")}
          >
            {label}
          </button>
          <button
            phx-click="toggle_bg_cycle"
            data-tip={gettext("Auto-cycle")}
            class={"bg-tip relative w-6 h-6 rounded flex items-center justify-center text-[11px] transition-colors " <>
              if(@sensor_bg_cycling,
                do: "bg-cyan-600 text-white",
                else: "bg-gray-700/50 hover:bg-gray-600/50 text-gray-400")}
          >
            ↻
          </button>
        </div>
      </div>
      <%!-- Tab handle --%>
      <div class="bg-gray-900/60 backdrop-blur-sm rounded-r px-1 py-2 border border-l-0 border-gray-700/40 cursor-pointer shrink-0 flex items-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-3 w-3 text-gray-500"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M10.5 6h9.75M10.5 6a1.5 1.5 0 1 1-3 0m3 0a1.5 1.5 0 1 0-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m-9.75 0h9.75"
          />
        </svg>
      </div>
    </div>

    <div class="relative z-10 min-h-screen flex flex-col">
      <%!-- Sign In Form (always on top) --%>
      <div class="flex items-center justify-center p-4 lg:p-8">
        <div class="w-full max-w-md">
          <%!-- Mobile toggle for about section --%>
          <button
            phx-click="toggle_about"
            class="lg:hidden w-full mb-4 px-4 py-2 text-sm text-gray-400 hover:text-white bg-gray-800/50 rounded-lg border border-gray-700"
          >
            {if @show_about, do: gettext("Hide About"), else: gettext("What is SensOcto?")}
          </button>

          <div
            id="sign-in-form"
            class="bg-gray-800/50 rounded-xl p-6 lg:p-8 border border-gray-700/50"
          >
            <h2 class="text-2xl font-bold text-white text-center mb-6">{gettext("Welcome")}</h2>

            <.live_component
              module={Components.SignIn}
              id="sign-in-component"
              otp_app={@otp_app}
              auth_routes_prefix="/auth"
              overrides={[SensoctoWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]}
              gettext_fn={{SensoctoWeb.CustomSignInLive, :auth_translate}}
            />

            <%!-- Guest Sign In Section --%>
            <div class="mt-6 p-4 bg-gray-700/30 rounded-lg border border-gray-600/50">
              <button
                phx-click="join_as_guest"
                class="w-full flex items-center justify-center gap-2 group"
                title={gettext("Browse without an account - session only")}
              >
                <.icon name="hero-user" class="h-5 w-5 text-gray-400 group-hover:text-white" />
                <div class="text-left">
                  <div class="font-medium text-white group-hover:text-gray-200">
                    {gettext("Continue as Guest")}
                  </div>
                  <div class="text-xs text-gray-400 group-hover:text-gray-300">
                    {gettext("No account needed")} • {gettext("Session only")}
                  </div>
                </div>
              </button>
            </div>

            <%!-- Language Toggle + Theme Toggle --%>
            <div class="mt-4 flex flex-wrap items-center justify-center gap-1">
              <button
                :for={{label, code} <- @locales}
                phx-click="change_locale"
                phx-value-locale={code}
                class={"px-2 py-1 rounded text-xs transition-colors " <>
                  if(@locale == code,
                    do: "bg-cyan-600/80 text-white",
                    else: "text-gray-500 hover:text-gray-300 hover:bg-gray-700/50")}
              >
                {label}
              </button>
              <span class="text-gray-600 mx-1">|</span>
              <button
                id="sign-in-theme-toggle"
                phx-hook="ThemeToggle"
                class="px-2 py-1 rounded text-xs text-gray-500 hover:text-gray-300 hover:bg-gray-700/50 transition-colors"
                title={gettext("Toggle theme")}
              >
                <svg
                  id="sign-in-theme-icon-sun"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="w-4 h-4 inline"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z"
                  />
                </svg>
                <svg
                  id="sign-in-theme-icon-moon"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="w-4 h-4 inline hidden"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Full About Content (below login) - using shared component --%>
      <div class={"overflow-y-auto " <> if @show_about, do: "block", else: "hidden"}>
        <.live_component
          module={SensoctoWeb.Components.AboutContentComponent}
          id="about-content"
          cta_scroll={true}
          cta_scroll_target="#sign-in-form"
          cta_label={gettext("Get Started")}
          transparent_bg={@sensor_bg_theme != "off"}
        />
      </div>
    </div>

    <style>
      @keyframes float {
        0%, 100% { transform: translateY(0px); }
        50% { transform: translateY(-10px); }
      }
      .animate-float {
        animation: float 3s ease-in-out infinite;
      }
      .bg-controls-drawer {
        left: 0;
        transform: translateY(-50%) translateX(calc(-100% + 21px));
        transition: transform 0.3s ease-out;
      }
      .bg-controls-drawer:hover {
        transform: translateY(-50%) translateX(0);
      }
      .bg-tip::after {
        content: attr(data-tip);
        position: absolute;
        bottom: calc(100% + 6px);
        left: 50%;
        transform: translateX(-50%) scale(0.9);
        padding: 2px 6px;
        background: rgba(0,0,0,0.85);
        color: #d1d5db;
        font-size: 9px;
        white-space: nowrap;
        border-radius: 4px;
        pointer-events: none;
        opacity: 0;
        transition: opacity 0.15s, transform 0.15s;
      }
      .bg-tip:hover::after {
        opacity: 1;
        transform: translateX(-50%) scale(1);
      }
    </style>

    <script>
      document.addEventListener("js:scroll-focus", (e) => {
        const target = document.querySelector(e.detail.target);
        if (!target) return;
        target.scrollIntoView({ behavior: "smooth", block: "center" });
        setTimeout(() => {
          const input = target.querySelector("input:not([type=hidden])");
          if (input) input.focus();
        }, 500);
      });
    </script>
    """
  end
end
