defmodule SensoctoWeb.CustomSignInLive do
  @moduledoc """
  Custom sign-in page that integrates the full About page content alongside the authentication form.
  Includes presence-tracked draggable balls for fun multi-user interaction.
  Uses the shared AboutContentComponent for consistent content.
  """
  use SensoctoWeb, :live_view
  alias AshAuthentication.Phoenix.Components
  alias SensoctoWeb.Sensocto.Presence

  @presence_topic "signin_presence"

  @impl true
  def mount(_params, session, socket) do
    # Check if user is already signed in as guest AND the guest still exists
    valid_guest? =
      session["is_guest"] == true and
        match?({:ok, _}, Sensocto.Accounts.GuestUserStore.get_guest(session["guest_id"]))

    if valid_guest? do
      {:ok, redirect(socket, to: ~p"/lobby")}
    else
      # Subscribe to presence updates for draggable balls
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Sensocto.PubSub, @presence_topic)
      end

      socket =
        socket
        |> assign(:show_about, true)
        # Ball presence state
        |> assign(:balls, %{})
        |> assign(:own_ball_id, nil)

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
        # Redirect to a route that will handle guest session creation
        {:noreply, redirect(socket, to: "/auth/guest/#{guest.id}/#{guest.token}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create guest session: #{inspect(reason)}")}
    end
  end

  # Ball presence event handlers
  @impl true
  def handle_event("ball_join", %{"session_id" => session_id}, socket) do
    user = socket.assigns[:current_user]
    ball_id = if user, do: "user:#{user.id}", else: "anon:#{session_id}"
    color = generate_color_from_id(ball_id)

    # Calculate initial Y position based on existing balls (spaced vertically on left)
    existing_count = map_size(Presence.list(@presence_topic))
    initial_y = 10.0 + existing_count * 8.0

    # Track presence with initial position (left border, spaced vertically)
    Presence.track(self(), @presence_topic, ball_id, %{
      x: 3.0,
      y: min(initial_y, 90.0),
      color: color,
      user_type: if(user, do: :authenticated, else: :anonymous)
    })

    # Send current state to client
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
    # Broadcast vibration event to all connected clients
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

  # Handle vibration broadcast from any dragging ball
  @impl true
  def handle_info({:vibrate, _ball_id}, socket) do
    {:noreply, push_event(socket, "vibrate", %{})}
  end

  # Handle presence diffs (joins, leaves, updates)
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    balls = socket.assigns.balls

    # Remove users who left
    balls =
      Enum.reduce(diff.leaves, balls, fn {key, _}, acc ->
        Map.delete(acc, key)
      end)

    # Add/update users who joined or moved
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

  # Helper: Generate consistent HSL color from ID
  defp generate_color_from_id(id) do
    hash = :erlang.phash2(id)
    # Golden ratio distribution for pleasing hue spread
    hue = rem(hash * 137, 360)
    saturation = 70 + rem(hash, 20)
    lightness = 50 + rem(div(hash, 360), 15)
    "hsl(#{hue}, #{saturation}%, #{lightness}%)"
  end

  # Helper: Transform presence map to ball map
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
    <%!-- Draggable Balls Container - positioned absolutely over the page --%>
    <div
      id="draggable-balls-container"
      phx-hook="DraggableBallsHook"
      class="fixed inset-0 pointer-events-none z-40"
      style="overflow: hidden;"
    >
      <%!-- Balls rendered by JS hook --%>
    </div>

    <div class="min-h-screen bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800 flex flex-col">
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
    </style>
    """
  end
end
