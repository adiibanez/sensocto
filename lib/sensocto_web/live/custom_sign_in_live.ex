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

  @presence_topic "signin_presence"
  @bg_tick_interval 800
  @valid_themes ~w(constellation waveform aurora particles)

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

      socket =
        socket
        |> assign(:page_title, "Sign In")
        |> assign(:show_about, true)
        # Ball presence state
        |> assign(:balls, %{})
        |> assign(:own_ball_id, nil)
        # Sensor background state
        |> assign(:sensor_activity, %{})
        |> assign(:sensor_bg_count, 8)
        |> assign(:sensor_bg_theme, "aurora")

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
     |> push_event("sensor_bg_theme_change", %{theme: theme})}
  end

  def handle_event("set_bg_theme", _params, socket), do: {:noreply, socket}

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
    sensor_ids = Sensocto.SensorsDynamicSupervisor.get_device_names()

    activity =
      Map.new(sensor_ids, fn id ->
        {id, %{name: id, hit_count: 0, last_ts: System.monotonic_time(:millisecond)}}
      end)

    Process.send_after(self(), :bg_tick, @bg_tick_interval)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  # Single measurement from attention topics
  @impl true
  def handle_info({:measurement, %{sensor_id: sid}}, socket) do
    activity = socket.assigns.sensor_activity

    activity =
      Map.update(
        activity,
        sid,
        %{name: sid, hit_count: 1, last_ts: System.monotonic_time(:millisecond)},
        fn entry ->
          %{entry | hit_count: entry.hit_count + 1, last_ts: System.monotonic_time(:millisecond)}
        end
      )

    {:noreply, assign(socket, sensor_activity: activity)}
  end

  # Batch measurements from attention topics
  @impl true
  def handle_info({:measurements_batch, {sid, measurements}}, socket) do
    activity = socket.assigns.sensor_activity
    count = length(measurements)

    activity =
      Map.update(
        activity,
        sid,
        %{name: sid, hit_count: count, last_ts: System.monotonic_time(:millisecond)},
        fn entry ->
          %{
            entry
            | hit_count: entry.hit_count + count,
              last_ts: System.monotonic_time(:millisecond)
          }
        end
      )

    {:noreply, assign(socket, sensor_activity: activity)}
  end

  # Sensor online/offline
  @impl true
  def handle_info({:sensor_online, sensor_id, _config}, socket) do
    activity =
      Map.put_new(socket.assigns.sensor_activity, sensor_id, %{
        name: sensor_id,
        hit_count: 0,
        last_ts: System.monotonic_time(:millisecond)
      })

    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:sensor_offline, sensor_id}, socket) do
    {:noreply,
     assign(socket, sensor_activity: Map.delete(socket.assigns.sensor_activity, sensor_id))}
  end

  # Throttled push of top-N sensors to the client
  @impl true
  def handle_info(:bg_tick, socket) do
    activity = socket.assigns.sensor_activity
    n = socket.assigns.sensor_bg_count

    top_n =
      activity
      |> Enum.sort_by(fn {_, v} -> v.hit_count end, :desc)
      |> Enum.take(n)

    max_activity =
      case top_n do
        [] -> 1
        list -> max(1, list |> Enum.map(fn {_, v} -> v.hit_count end) |> Enum.max())
      end

    sensors =
      Enum.map(top_n, fn {id, v} ->
        %{id: id, name: v.name, intensity: v.hit_count / max_activity}
      end)

    # Decay hit_counts by 50% for temporal smoothing
    decayed =
      Map.new(activity, fn {id, v} ->
        {id, %{v | hit_count: div(v.hit_count, 2)}}
      end)

    Process.send_after(self(), :bg_tick, @bg_tick_interval)

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

    <%!-- Background Controls — slide-out drawer from left edge, centered vertically --%>
    <div
      id="bg-controls-drawer"
      class="bg-controls-drawer fixed top-1/2 z-30 flex items-center"
    >
      <%!-- Panel --%>
      <div class="bg-gray-900/60 backdrop-blur-sm rounded-r-lg p-3 border border-l-0 border-gray-700/50 text-xs text-gray-400 space-y-2 w-[220px] shrink-0">
        <div class="flex items-center gap-2">
          <span class="whitespace-nowrap text-gray-500">Sensors</span>
          <form phx-change="set_bg_count" class="flex items-center gap-2 flex-1">
            <input
              type="range"
              min="1"
              max="100"
              value={@sensor_bg_count}
              name="count"
              class="w-full h-1 accent-cyan-500 cursor-pointer"
            />
            <span class="w-5 text-center text-gray-300">{@sensor_bg_count}</span>
          </form>
        </div>
        <div class="flex gap-1">
          <button
            :for={theme <- ~w(constellation waveform aurora particles)}
            phx-click="set_bg_theme"
            phx-value-theme={theme}
            class={"px-2 py-1 rounded text-[10px] capitalize transition-colors " <>
              if(@sensor_bg_theme == theme,
                do: "bg-cyan-600 text-white",
                else: "bg-gray-700/50 hover:bg-gray-600/50 text-gray-300")}
          >
            {theme}
          </button>
        </div>
      </div>
      <%!-- Tab handle --%>
      <div class="bg-gray-900/50 backdrop-blur-sm rounded-r-lg px-2 py-3 border border-l-0 border-gray-700/40 cursor-pointer shrink-0">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-4 w-4 text-gray-400"
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
      <div class="flex items-center justify-center p-4 lg:p-8 bg-gray-900/50">
        <div class="w-full max-w-md">
          <%!-- Mobile toggle for about section --%>
          <button
            phx-click="toggle_about"
            class="lg:hidden w-full mb-4 px-4 py-2 text-sm text-gray-400 hover:text-white bg-gray-800/50 rounded-lg border border-gray-700"
          >
            {if @show_about, do: "Hide About", else: "What is SensOcto?"}
          </button>

          <div class="bg-gray-800/50 rounded-xl p-6 lg:p-8 border border-gray-700/50">
            <h2 class="text-2xl font-bold text-white text-center mb-6">Welcome</h2>

            <.live_component
              module={Components.SignIn}
              id="sign-in-component"
              otp_app={@otp_app}
              auth_routes_prefix="/auth"
              overrides={[SensoctoWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]}
            />

            <%!-- Guest Sign In Section --%>
            <div class="mt-6 p-4 bg-gray-700/30 rounded-lg border border-gray-600/50">
              <button
                phx-click="join_as_guest"
                class="w-full flex items-center justify-center gap-2 group"
                title="Browse without an account - session only"
              >
                <.icon name="hero-user" class="h-5 w-5 text-gray-400 group-hover:text-white" />
                <div class="text-left">
                  <div class="font-medium text-white group-hover:text-gray-200">
                    Continue as Guest
                  </div>
                  <div class="text-xs text-gray-400 group-hover:text-gray-300">
                    No account needed • Session only
                  </div>
                </div>
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
          show_cta={false}
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
        transform: translateY(-50%) translateX(calc(-100% + 34px));
        transition: transform 0.3s ease-out;
      }
      .bg-controls-drawer:hover {
        transform: translateY(-50%) translateX(0);
      }
    </style>
    """
  end
end
