defmodule SensoctoWeb.CustomSignInLive do
  @moduledoc """
  Custom sign-in page that integrates the full About page content alongside the authentication form.
  Includes presence-tracked draggable balls for fun multi-user interaction.
  """
  use SensoctoWeb, :live_view
  alias AshAuthentication.Phoenix.Components
  alias SensoctoWeb.Sensocto.Presence

  @presence_topic "signin_presence"

  # Use cases organized by viewing lens (shared with AboutLive)
  @use_cases_by_lens %{
    technical: [
      {"stream", "cyan", "Movesense ECG and IMU data at 100Hz"},
      {"connect", "teal", "Nordic Thingy:52 via Web Bluetooth"},
      {"visualize", "blue", "GPS tracks from walking, cycling, or drones"},
      {"analyze", "emerald", "underwater hydrophone feeds with spectrograms"},
      {"process", "purple", "YOLOfish-style inference on live video"},
      {"capture", "amber", "9-axis IMU quaternions for motion analysis"},
      {"sync", "cyan", "distributed datasets via P2P CRDT networks"},
      {"export", "teal", "time-series data in scientific formats"},
      {"trigger", "violet", "actuators from sensor threshold rules"},
      {"monitor", "blue", "temperature, humidity, pressure, air quality"},
      {"stream", "pink", "ROV video feeds with real-time annotations"},
      {"integrate", "emerald", "Buttplug.io for haptic device control"},
      {"track", "cyan", "HRV and recovery metrics from medical wearables"},
      {"collect", "teal", "field research data stored locally on mobile"}
    ],
    empathy: [
      {"feel", "pink", "someone's nervousness before they speak"},
      {"sense", "rose", "a partner's desire without words"},
      {"know", "purple", "a friend is struggling before they ask"},
      {"share", "cyan", "your calm with an anxious loved one"},
      {"sync", "teal", "your breathing with a meditation circle"},
      {"notice", "amber", "your child's nightmare from another room"},
      {"witness", "green", "trust forming in a therapy session"},
      {"experience", "violet", "collective flow in a jam session"},
      {"feel", "blue", "the ocean's rhythm through a hydrophone"},
      {"sense", "pink", "when your partner needs to be held"},
      {"know", "emerald", "when words aren't needed anymore"},
      {"share", "cyan", "presence across distance and time"},
      {"feel", "rose", "your body's wisdom guiding decisions"},
      {"experience", "purple", "synchronized pleasure in real-time"}
    ],
    fun: [
      {"play", "yellow", "sensor-driven party games with friends"},
      {"pilot", "orange", "drones while sharing your excitement"},
      {"roll", "amber", "smart dice that glow with your heartbeat"},
      {"dance", "pink", "with haptic feedback synced to the beat"},
      {"explore", "cyan", "underwater worlds through ROV adventures"},
      {"create", "violet", "music from your collective heartbeats"},
      {"solve", "teal", "escape rooms with physiological puzzles"},
      {"jam", "rose", "together as instruments respond to your mood"},
      {"chill", "blue", "in calm-off sessions seeing who relaxes first"},
      {"breathe", "emerald", "together and watch your sync grow"},
      {"unlock", "purple", "new experiences by reaching flow states"},
      {"stream", "cyan", "your gameplay with live biometrics overlay"},
      {"vibe", "pink", "together at silent discos with shared pulse"},
      {"laugh", "yellow", "as haptic devices tickle synchronized giggles"}
    ],
    impact: [
      {"restore", "emerald", "coral reef ecosystems with AI monitoring"},
      {"enable", "violet", "independence for wheelchair users"},
      {"protect", "cyan", "marine biodiversity through acoustic detection"},
      {"support", "green", "mental health with trusted peer networks"},
      {"improve", "blue", "cystic fibrosis outcomes through gamification"},
      {"empower", "teal", "non-verbal communication via physiology"},
      {"prevent", "amber", "crises with early warning biometrics"},
      {"democratize", "purple", "research with P2P data collection"},
      {"assist", "pink", "caregivers with real-time patient monitoring"},
      {"accelerate", "cyan", "trauma healing with biofeedback"},
      {"detect", "emerald", "wandering risk via wearable location tracking"},
      {"transform", "violet", "physiotherapy into engaging games"},
      {"connect", "blue", "isolated individuals to support networks"},
      {"verify", "teal", "consent through embodied signals"}
    ],
    research: [
      {"quantify", "blue", "group synchronization in meditation studies"},
      {"measure", "cyan", "HRV responses to therapeutic interventions"},
      {"track", "teal", "marine migration patterns via bioacoustics"},
      {"analyze", "emerald", "coral health metrics across reef systems"},
      {"correlate", "purple", "physiological data with mood reports"},
      {"validate", "amber", "freediving training protocols with ECG"},
      {"study", "violet", "co-regulation dynamics in therapy dyads"},
      {"document", "pink", "species diversity with automated detection"},
      {"compare", "cyan", "recovery patterns across athlete cohorts"},
      {"observe", "teal", "circadian rhythm impacts on chronic conditions"},
      {"map", "blue", "stress patterns in distributed populations"},
      {"assess", "emerald", "intervention effectiveness with biometrics"},
      {"explore", "purple", "massive datasets like wildflow.org corals"},
      {"prototype", "amber", "assistive interfaces with sensor feedback"}
    ]
  }

  @lens_info [
    {:empathy,
     %{
       name: "Empathy",
       icon: "hero-heart",
       color: "pink",
       description: "Feelings, relationships, presence",
       featured: true
     }},
    {:fun,
     %{
       name: "Fun",
       icon: "hero-puzzle-piece",
       color: "yellow",
       description: "Games, play, entertainment",
       featured: false
     }},
    {:technical,
     %{
       name: "Technical",
       icon: "hero-cpu-chip",
       color: "cyan",
       description: "Sensors, protocols, data flows",
       featured: false
     }},
    {:impact,
     %{
       name: "Impact",
       icon: "hero-globe-alt",
       color: "emerald",
       description: "Social good, accessibility, outcomes",
       featured: false
     }},
    {:research,
     %{
       name: "Research",
       icon: "hero-beaker",
       color: "purple",
       description: "Science, analysis, discovery",
       featured: false
     }}
  ]

  @research_papers [
    %{
      title: "Interpersonal Autonomic Physiology: A Systematic Review of the Literature",
      authors: "Palumbo et al.",
      year: 2017,
      journal: "Personality and Social Psychology Review",
      doi: "10.1177/1088868316628405",
      category: :synchronization,
      description:
        "Systematic review defining interpersonal autonomic physiology and how physiological synchronization emerges during social interactions."
    },
    %{
      title: "State of the Art of Interpersonal Physiology in Psychotherapy: A Systematic Review",
      authors: "Kleinbub, R.",
      year: 2017,
      journal: "Frontiers in Psychology",
      doi: "10.3389/fpsyg.2017.02053",
      category: :therapy,
      description:
        "Reviews evidence for physiological synchrony between therapists and clients as a marker of therapeutic alliance."
    },
    %{
      title: "Social Ties and Mental Health",
      authors: "Kawachi & Berkman",
      year: 2001,
      journal: "Journal of Urban Health",
      doi: "10.1093/jurban/78.3.458",
      category: :care_networks,
      description:
        "Foundational work on how social networks influence mental health outcomes and crisis prevention."
    },
    %{
      title:
        "Partner Influence and In-Phase Versus Anti-Phase Physiological Linkage in Romantic Couples",
      authors: "Reed et al.",
      year: 2013,
      journal: "International Journal of Psychophysiology",
      doi: "10.1016/j.ijpsycho.2012.08.009",
      category: :synchronization,
      description:
        "Examines how partners' physiological systems co-regulate during emotional conversations and health discussions."
    },
    %{
      title:
        "Identifying Objective Physiological Markers Using Wearable Sensors and Mobile Phones",
      authors: "Sano et al.",
      year: 2018,
      journal: "Journal of Medical Internet Research",
      doi: "10.2196/jmir.9410",
      category: :wearables,
      description:
        "Uses wearable biosensors and machine learning to classify stress and mental health status in real-time."
    },
    %{
      title: "Biofeedback in the Treatment of Anxiety and PTSD",
      authors: "Tan et al.",
      year: 2011,
      journal: "Applied Psychophysiology and Biofeedback",
      doi: "10.1007/s10484-010-9141-x",
      category: :therapy,
      description:
        "Evidence for HRV biofeedback as an effective intervention for anxiety and trauma recovery."
    },
    %{
      title: "Peer Support in Mental Health: A Systematic Review",
      authors: "Repper & Carter",
      year: 2011,
      journal: "Journal of Mental Health",
      doi: "10.3109/09638237.2011.583947",
      category: :care_networks,
      description:
        "Systematic review of peer support effectiveness in mental health care and community interventions."
    },
    %{
      title: "Collective Effervescence and Synchrony in Ritual",
      authors: "Páez et al.",
      year: 2015,
      journal: "Frontiers in Psychology",
      doi: "10.3389/fpsyg.2015.01963",
      category: :synchronization,
      description:
        "Studies how group rituals produce physiological and emotional synchronization among participants."
    },
    %{
      title: "Autonomic Nervous System Dynamics for Mood Detection",
      authors: "Valenza et al.",
      year: 2014,
      journal: "IEEE Transactions on Affective Computing",
      doi: "10.1109/TAFFC.2014.2332167",
      category: :wearables,
      description:
        "Methods for detecting emotional states through autonomic nervous system monitoring via wearables."
    },
    %{
      title: "Technology-Mediated Compassion in Healthcare",
      authors: "Chen & Schultz",
      year: 2016,
      journal: "JMIR Mental Health",
      doi: "10.2196/mental.5316",
      category: :care_networks,
      description:
        "Explores how technology can enhance compassionate care in mental health treatment settings."
    }
  ]

  @paper_categories %{
    synchronization: %{
      name: "HRV Synchronization",
      color: "cyan",
      icon: "hero-arrows-right-left"
    },
    therapy: %{name: "Therapy & Healing", color: "green", icon: "hero-heart"},
    care_networks: %{name: "Care Networks", color: "purple", icon: "hero-users"},
    wearables: %{
      name: "Wearables & Monitoring",
      color: "blue",
      icon: "hero-device-phone-mobile"
    }
  }

  @impl true
  def mount(_params, session, socket) do
    # Check if user is already signed in as guest AND the guest still exists
    valid_guest? =
      session["is_guest"] == true and
        match?({:ok, _}, Sensocto.Accounts.GuestUserStore.get_guest(session["guest_id"]))

    if valid_guest? do
      {:ok, redirect(socket, to: ~p"/lobby")}
    else
      current_lens = :empathy
      shuffled = Enum.shuffle(@use_cases_by_lens[current_lens])

      # Subscribe to presence updates for draggable balls
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Sensocto.PubSub, @presence_topic)
      end

      socket =
        socket
        |> assign(:detail_level, :spark)
        |> assign(:show_about, true)
        |> assign(:current_lens, current_lens)
        |> assign(:lens_info, @lens_info)
        |> assign(:use_cases, shuffled)
        |> assign(:visible_count, 3)
        |> assign(:current_offset, 0)
        |> assign(:research_papers, @research_papers)
        |> assign(:paper_categories, @paper_categories)
        # Ball presence state
        |> assign(:balls, %{})
        |> assign(:own_ball_id, nil)
        # Guest remember me (LocalStorage vs in-memory)
        |> assign(:guest_remember_me, false)

      {:ok, socket, layout: {SensoctoWeb.Layouts, :auth}}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    otp_app = socket.assigns[:otp_app] || :sensocto
    {:noreply, assign(socket, :otp_app, otp_app) |> assign(:params, params)}
  end

  @impl true
  def handle_event("set_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, detail_level: String.to_existing_atom(level))}
  end

  @impl true
  def handle_event("toggle_about", _, socket) do
    {:noreply, assign(socket, show_about: !socket.assigns.show_about)}
  end

  @impl true
  def handle_event("set_lens", %{"lens" => lens}, socket) do
    lens = String.to_existing_atom(lens)
    shuffled = Enum.shuffle(@use_cases_by_lens[lens])

    socket =
      socket
      |> assign(:current_lens, lens)
      |> assign(:use_cases, shuffled)
      |> assign(:current_offset, 0)

    {:noreply, socket}
  end

  @impl true
  def handle_event("shuffle_use_cases", _params, socket) do
    use_cases = socket.assigns.use_cases
    visible_count = socket.assigns.visible_count
    current_offset = socket.assigns.current_offset
    total = length(use_cases)

    new_offset = current_offset + visible_count

    {new_cases, new_offset} =
      if new_offset >= total do
        {Enum.shuffle(use_cases), 0}
      else
        {use_cases, new_offset}
      end

    {:noreply, assign(socket, use_cases: new_cases, current_offset: new_offset)}
  end

  @impl true
  def handle_event("set_visible_count", %{"count" => count}, socket) do
    count = String.to_integer(count)
    {:noreply, assign(socket, visible_count: count, current_offset: 0)}
  end

  @impl true
  def handle_event("toggle_guest_remember", _params, socket) do
    {:noreply, assign(socket, :guest_remember_me, !socket.assigns.guest_remember_me)}
  end

  @impl true
  def handle_event(
        "restore_guest_credentials",
        %{"guest_id" => guest_id, "guest_token" => token},
        socket
      ) do
    # Try to automatically sign in with stored credentials
    case Sensocto.Accounts.GuestUserStore.get_guest(guest_id) do
      {:ok, guest} ->
        if guest.token == token do
          # Valid stored credentials, auto sign-in
          {:noreply, redirect(socket, to: "/auth/guest/#{guest_id}/#{token}")}
        else
          # Token mismatch, credentials invalid
          {:noreply, socket}
        end

      {:error, :not_found} ->
        # Guest not found in memory, credentials expired
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("join_as_guest", _params, socket) do
    case Sensocto.Accounts.GuestUserStore.create_guest() do
      {:ok, guest} ->
        # If remember_me is enabled, push event to store in localStorage via JS hook
        socket =
          if socket.assigns.guest_remember_me do
            push_event(socket, "store-guest-credentials", %{
              guest_id: guest.id,
              token: guest.token
            })
          else
            socket
          end

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

  defp visible_use_cases(use_cases, offset, count) do
    use_cases
    |> Enum.drop(offset)
    |> Enum.take(count)
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

    <%!-- Guest Credentials Hook Container --%>
    <div id="guest-credentials-hook" phx-hook="GuestCredentials" class="hidden"></div>

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
                title={"Browse without an account - data stored in #{if @guest_remember_me, do: "LocalStorage (persistent)", else: "memory only"}"}
              >
                <.icon name="hero-user" class="h-5 w-5 text-gray-400 group-hover:text-white" />
                <div class="text-left">
                  <div class="font-medium text-white group-hover:text-gray-200">
                    Continue as Guest
                  </div>
                  <div class="text-xs text-gray-400 group-hover:text-gray-300">
                    No account needed •
                    <%= if @guest_remember_me do %>
                      LocalStorage (persistent across sessions)
                    <% else %>
                      In-memory session only
                    <% end %>
                  </div>
                </div>
              </button>
              <label class="flex items-center gap-2 mt-3 cursor-pointer select-none">
                <input
                  type="checkbox"
                  id="guest-remember-me"
                  phx-click="toggle_guest_remember"
                  checked={@guest_remember_me}
                  class="w-4 h-4 text-blue-600 bg-gray-700 border-gray-600 rounded focus:ring-blue-500 focus:ring-2 cursor-pointer"
                />
                <span class="text-sm text-gray-300">Remember me (store in LocalStorage)</span>
              </label>
            </div>
          </div>
        </div>
      </div>

      <%!-- Full About Content (below login) --%>
      <div class={"overflow-y-auto " <> if @show_about, do: "block", else: "hidden"}>
        <%!-- Hero Section --%>
        <div class="relative overflow-hidden">
          <div
            class="absolute inset-0 bg-gradient-to-r from-blue-900/20 via-cyan-900/10 to-purple-900/20 animate-pulse"
            style="animation-duration: 4s;"
          >
          </div>

          <div class="relative max-w-4xl mx-auto px-4 py-12 sm:py-16 text-center">
            <h1 class="text-4xl sm:text-5xl font-bold bg-gradient-to-r from-cyan-400 via-blue-400 to-purple-400 bg-clip-text text-transparent mb-4">
              SensOcto
            </h1>
            <p class="text-xl text-gray-400 mb-8">
              Feel someone's presence. Not their performance.
            </p>

            <%!-- Detail Level Switcher --%>
            <div class="flex justify-center gap-2 mb-12">
              <button
                phx-click="set_level"
                phx-value-level="spark"
                class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                  if @detail_level == :spark do
                    "bg-cyan-500 text-white shadow-lg shadow-cyan-500/30"
                  else
                    "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                  end}
              >
                The Spark
              </button>
              <button
                phx-click="set_level"
                phx-value-level="story"
                class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                  if @detail_level == :story do
                    "bg-blue-500 text-white shadow-lg shadow-blue-500/30"
                  else
                    "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                  end}
              >
                The Story
              </button>
              <button
                phx-click="set_level"
                phx-value-level="deep"
                class={"px-4 py-2 rounded-full text-sm font-medium transition-all duration-300 " <>
                  if @detail_level == :deep do
                    "bg-purple-500 text-white shadow-lg shadow-purple-500/30"
                  else
                    "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                  end}
              >
                The Deep Dive
              </button>
            </div>
          </div>
        </div>

        <%!-- Content Sections --%>
        <div class="max-w-4xl mx-auto px-4 pb-24">
          <%!-- The Spark: Core Philosophy (Always Visible) --%>
          <div class="mb-12 text-center">
            <div class="inline-block px-3 py-1 bg-cyan-500/20 text-cyan-400 rounded-full text-xs font-medium mb-6">
              THE SPARK
            </div>

            <p class="text-2xl sm:text-3xl text-white leading-relaxed max-w-3xl mx-auto mb-8">
              Technology promised connection and delivered <span class="text-gray-500">performance</span>.
              We scroll, we perform, we feel more alone.
            </p>

            <%!-- Lens Switcher --%>
            <div class="flex justify-center items-center gap-2 mb-6 flex-wrap">
              <%= for {lens_key, info} <- @lens_info do %>
                <button
                  phx-click="set_lens"
                  phx-value-lens={lens_key}
                  class={"flex items-center transition-all duration-300 rounded-full font-medium " <>
                    if info.featured do
                      "gap-2 px-4 py-2 text-sm "
                    else
                      "gap-1.5 px-3 py-1.5 text-xs "
                    end <>
                    if @current_lens == lens_key do
                      "bg-#{info.color}-500/20 text-#{info.color}-400 ring-1 ring-#{info.color}-500/50"
                    else
                      "bg-gray-800/50 text-gray-500 hover:text-gray-300 hover:bg-gray-700/50"
                    end}
                  title={info.description}
                >
                  <.icon
                    name={info.icon}
                    class={if info.featured, do: "h-4 w-4", else: "h-3.5 w-3.5"}
                  />
                  <span>{info.name}</span>
                </button>
              <% end %>
            </div>

            <%!-- Clickable Use Cases Carousel --%>
            <div
              class="text-xl text-gray-400 max-w-2xl mx-auto mb-6 cursor-pointer hover:text-gray-300 transition-colors group"
              phx-click="shuffle_use_cases"
              title="Click for more examples"
            >
              <p class="leading-relaxed">
                What if you could
                <%= for {{verb, color, rest}, index} <- Enum.with_index(visible_use_cases(@use_cases, @current_offset, @visible_count)) do %>
                  <span class={"text-#{color}-400 font-medium"}>{verb}</span>
                  {rest}{if index < @visible_count - 1, do: "? ", else: "?"}
                <% end %>
              </p>
              <div class="flex items-center justify-center gap-2 mt-3 text-sm text-gray-500 group-hover:text-gray-400 transition-colors">
                <.icon name="hero-arrow-path" class="h-4 w-4" />
                <span>Click for more examples</span>
              </div>
            </div>

            <%!-- Slider for visible count --%>
            <form phx-change="set_visible_count" class="flex items-center justify-center gap-4 mb-8">
              <label class="text-sm text-gray-500">Show</label>
              <input
                type="range"
                min="1"
                max="6"
                value={@visible_count}
                name="count"
                class="w-32 h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-cyan-500"
              />
              <span class="text-sm text-cyan-400 w-6 text-center">{@visible_count}</span>
            </form>

            <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 max-w-2xl mx-auto">
              <p class="text-lg text-gray-300 italic">
                "Connection becomes tangible when you can feel someone's presence—their heartbeat, their calm, their stress—in real-time."
              </p>
            </div>
          </div>

          <%!-- The Story: Human Use Cases --%>
          <div class={"transition-all duration-500 overflow-hidden " <> if @detail_level in [:story, :deep], do: "opacity-100 max-h-[4000px]", else: "opacity-0 max-h-0"}>
            <div class="border-t border-gray-800 pt-12 mb-12">
              <div class="inline-block px-3 py-1 bg-blue-500/20 text-blue-400 rounded-full text-xs font-medium mb-6">
                THE STORY
              </div>

              <h2 class="text-2xl font-semibold text-white mb-8 text-center">
                Built for humans who want to <span class="text-blue-400">truly</span> connect
              </h2>

              <div class="grid gap-6 mb-10">
                <%!-- Therapy & Healing --%>
                <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-green-500/30 transition-colors">
                  <div class="flex items-start gap-4">
                    <div class="p-3 bg-green-500/20 rounded-lg shrink-0">
                      <.icon name="hero-heart" class="h-6 w-6 text-green-400" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-white mb-2">Therapy & Healing</h3>
                      <p class="text-gray-400 mb-3">
                        Therapists see nervous system dysregulation in real-time. HRV, breathing patterns, heart rate—visible during sessions. Trust forms faster when bodies sync. Healing accelerates with biofeedback.
                      </p>
                      <p class="text-green-400 text-sm">
                        "See the nervous system respond before words form."
                      </p>
                    </div>
                  </div>
                </div>

                <%!-- Disability & Care --%>
                <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-blue-500/30 transition-colors">
                  <div class="flex items-start gap-4">
                    <div class="p-3 bg-blue-500/20 rounded-lg shrink-0">
                      <.icon name="hero-hand-raised" class="h-6 w-6 text-blue-400" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-white mb-2">
                        Disability Care & Non-Verbal Communication
                      </h3>
                      <p class="text-gray-400 mb-3">
                        For those who cannot speak their needs—non-verbal individuals, wheelchair users, those with chronic conditions—physiological signals become their voice. Caregivers sense when someone needs help before they ask.
                      </p>
                      <p class="text-blue-400 text-sm">
                        "Dignity and agency restored through embodied communication."
                      </p>
                    </div>
                  </div>
                </div>

                <%!-- Mental Health Networks --%>
                <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-purple-500/30 transition-colors">
                  <div class="flex items-start gap-4">
                    <div class="p-3 bg-purple-500/20 rounded-lg shrink-0">
                      <.icon name="hero-users" class="h-6 w-6 text-purple-400" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-white mb-2">
                        Mental Health & Trusted Networks
                      </h3>
                      <p class="text-gray-400 mb-3">
                        Peer support networks are reactive—friends don't know someone's in crisis until it's too late. With shared physiology, trusted contacts see rising stress patterns and can reach out proactively.
                      </p>
                      <p class="text-purple-400 text-sm">
                        "Prevention over crisis. Community as safety net."
                      </p>
                    </div>
                  </div>
                </div>

                <%!-- Intimacy & Consent --%>
                <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-pink-500/30 transition-colors">
                  <div class="flex items-start gap-4">
                    <div class="p-3 bg-pink-500/20 rounded-lg shrink-0">
                      <.icon name="hero-sparkles" class="h-6 w-6 text-pink-400" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-white mb-2">
                        Intimacy & Embodied Consent
                      </h3>
                      <p class="text-gray-400 mb-3">
                        Real arousal, real consent, real connection. Partners see each other's actual physiological state—no guessing, no performance. Marginalized communities finally served by technology that respects their needs.
                      </p>
                      <p class="text-pink-400 text-sm">
                        "Consent infrastructure for bodies, not just words."
                      </p>
                    </div>
                  </div>
                </div>

                <%!-- Groups & Collective Presence --%>
                <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-cyan-500/30 transition-colors">
                  <div class="flex items-start gap-4">
                    <div class="p-3 bg-cyan-500/20 rounded-lg shrink-0">
                      <.icon name="hero-user-group" class="h-6 w-6 text-cyan-400" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-white mb-2">
                        Groups & Collective Presence
                      </h3>
                      <p class="text-gray-400 mb-3">
                        Teams feel collective calm or tension. Meditation groups verify synchronization. Performers read live audience engagement. Rituals become measurable. Groups self-regulate as organisms.
                      </p>
                      <p class="text-cyan-400 text-sm">
                        "Emergent collective intelligence through shared physiology."
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- The Promise --%>
              <div class="bg-gradient-to-r from-cyan-900/20 via-blue-900/20 to-purple-900/20 rounded-xl p-8 border border-gray-700/50 text-center">
                <h3 class="text-xl font-semibold text-white mb-4">The Promise</h3>
                <p class="text-lg text-gray-300 max-w-2xl mx-auto">
                  Connection measured in <span class="text-red-400">heartbeats</span>, not dopamine hits.
                  Technology that <span class="text-cyan-400">amplifies empathy</span>
                  instead of exploiting attention.
                  No harvesting. No surveillance. No algorithms deciding who sees what.
                </p>
              </div>

              <%!-- Research Papers Section (visible when research lens is active) --%>
              <div :if={@current_lens == :research} class="mt-10">
                <h3 class="text-xl font-semibold text-white mb-6">
                  <.icon
                    name="hero-academic-cap"
                    class="h-6 w-6 inline-block mr-2 text-purple-400"
                  /> Research Foundations
                </h3>
                <p class="text-gray-400 mb-6">
                  Our approach is grounded in peer-reviewed research on physiological synchronization, care networks, and wearable technology for mental health.
                </p>

                <%!-- Category filters --%>
                <div class="flex flex-wrap gap-2 mb-6">
                  <%= for {_key, cat} <- @paper_categories do %>
                    <span class={"inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-#{cat.color}-500/20 text-#{cat.color}-400"}>
                      <.icon name={cat.icon} class="h-3.5 w-3.5" />
                      {cat.name}
                    </span>
                  <% end %>
                </div>

                <%!-- Papers list --%>
                <div class="space-y-4">
                  <%= for paper <- @research_papers do %>
                    <% cat = @paper_categories[paper.category] %>
                    <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50 hover:border-purple-500/30 transition-colors">
                      <div class="flex items-start gap-3">
                        <div class={"p-2 rounded-lg shrink-0 bg-#{cat.color}-500/20"}>
                          <.icon name={cat.icon} class={"h-4 w-4 text-#{cat.color}-400"} />
                        </div>
                        <div class="flex-1 min-w-0">
                          <h4 class="text-white font-medium text-sm leading-tight mb-1">
                            {paper.title}
                          </h4>
                          <p class="text-gray-500 text-xs mb-2">
                            {paper.authors} ({paper.year}) ·
                            <span class="text-gray-600">{paper.journal}</span>
                          </p>
                          <p class="text-gray-400 text-sm">
                            {paper.description}
                          </p>
                          <a
                            href={"https://doi.org/#{paper.doi}"}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="inline-flex items-center gap-1 mt-2 text-xs text-purple-400 hover:text-purple-300 transition-colors"
                          >
                            <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
                            DOI: {paper.doi}
                          </a>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%!-- The Deep Dive: Architecture as Values --%>
          <div class={"transition-all duration-500 overflow-hidden " <> if @detail_level == :deep, do: "opacity-100 max-h-[3000px]", else: "opacity-0 max-h-0"}>
            <div class="border-t border-gray-800 pt-12">
              <div class="inline-block px-3 py-1 bg-purple-500/20 text-purple-400 rounded-full text-xs font-medium mb-6">
                THE DEEP DIVE
              </div>

              <h2 class="text-2xl font-semibold text-white mb-4 text-center">
                Every technical decision is a <span class="text-purple-400">moral statement</span>
              </h2>

              <p class="text-gray-400 text-center mb-8 max-w-2xl mx-auto">
                Architecture shapes incentives. We built Sensocto so that privacy and human dignity are structural guarantees, not policy promises.
              </p>

              <%!-- P2P as Foundation --%>
              <div class="mb-8">
                <h3 class="text-xl font-semibold text-white mb-4">Why Peer-to-Peer?</h3>
                <div class="grid sm:grid-cols-2 gap-4">
                  <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                    <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                    <div class="text-gray-400 text-sm">Server costs create monetization pressure</div>
                    <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                    <div class="text-gray-300 text-sm">
                      Near-zero marginal cost. No need to harvest data.
                    </div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                    <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                    <div class="text-gray-400 text-sm">Data harvesting for ad targeting</div>
                    <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                    <div class="text-gray-300 text-sm">
                      Data stays on your devices. Privacy by structure.
                    </div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                    <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                    <div class="text-gray-400 text-sm">Deplatforming and censorship risk</div>
                    <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                    <div class="text-gray-300 text-sm">
                      No central authority. Communities cannot be silenced.
                    </div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-4 border border-gray-700/50">
                    <div class="text-red-400 text-sm font-medium mb-2">Centralized Problem</div>
                    <div class="text-gray-400 text-sm">Surveillance by design</div>
                    <div class="mt-2 text-green-400 text-sm font-medium">P2P Solution</div>
                    <div class="text-gray-300 text-sm">
                      End-to-end encryption native. Intimate data protected.
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Biomimetic Intelligence --%>
              <div class="mb-8">
                <h3 class="text-xl font-semibold text-white mb-4">Biomimetic Intelligence</h3>
                <p class="text-gray-400 mb-4">
                  Beneath the surface, Sensocto operates like a living organism—adapting, learning, self-regulating.
                </p>
                <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3 text-sm">
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-yellow-400 font-medium">Novelty Detection</div>
                    <div class="text-gray-500">Alertness to anomalous data</div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-blue-400 font-medium">Predictive Load Balancing</div>
                    <div class="text-gray-500">Anticipates demand spikes</div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-green-400 font-medium">Homeostatic Tuning</div>
                    <div class="text-gray-500">Self-adapting thresholds</div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-purple-400 font-medium">Attention-Aware Batching</div>
                    <div class="text-gray-500">Respects user focus</div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-cyan-400 font-medium">Circadian Scheduling</div>
                    <div class="text-gray-500">Daily pattern learning</div>
                  </div>
                  <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                    <div class="text-pink-400 font-medium">Resource Arbitration</div>
                    <div class="text-gray-500">Competitive allocation</div>
                  </div>
                </div>
              </div>

              <%!-- Tech Stack --%>
              <div class="mb-8">
                <h3 class="text-xl font-semibold text-white mb-4">Built With</h3>
                <div class="flex flex-wrap gap-2">
                  <span class="px-3 py-1 bg-purple-900/30 text-purple-300 rounded-full text-sm">
                    Elixir/OTP
                  </span>
                  <span class="px-3 py-1 bg-orange-900/30 text-orange-300 rounded-full text-sm">
                    Phoenix LiveView
                  </span>
                  <span class="px-3 py-1 bg-blue-900/30 text-blue-300 rounded-full text-sm">
                    Ash Framework
                  </span>
                  <span class="px-3 py-1 bg-cyan-900/30 text-cyan-300 rounded-full text-sm">
                    Iroh P2P
                  </span>
                  <span class="px-3 py-1 bg-green-900/30 text-green-300 rounded-full text-sm">
                    WebRTC
                  </span>
                  <span class="px-3 py-1 bg-pink-900/30 text-pink-300 rounded-full text-sm">
                    CRDT Sync
                  </span>
                </div>
              </div>

              <%!-- Open Source Note --%>
              <div class="text-center text-gray-500 text-sm">
                <p>
                  Built with <span class="text-red-400">♥</span>
                  for humans who believe technology should serve connection, not extraction.
                </p>
              </div>
            </div>
          </div>
        </div>
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
