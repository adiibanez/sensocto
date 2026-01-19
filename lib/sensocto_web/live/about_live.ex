defmodule SensoctoWeb.AboutLive do
  @moduledoc """
  About page with 3 levels of detail about Sensocto's vision, use cases, and technology.
  """
  use SensoctoWeb, :live_view

  # Use cases organized by viewing lens
  # Each lens offers a different perspective on platform capabilities

  @use_cases_by_lens %{
    # TECHNICAL LENS - Focus on sensors, protocols, data flows
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
      {"collect", "teal", "field research data stored locally on mobile"},
    ],

    # EMPATHY LENS - Emotional, relational, experiential
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
      {"experience", "purple", "synchronized pleasure in real-time"},
    ],

    # FUN LENS - Games, play, entertainment, social experiences
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
      {"laugh", "yellow", "as haptic devices tickle synchronized giggles"},
    ],

    # IMPACT LENS - Social good, accessibility, healthcare outcomes
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
      {"verify", "teal", "consent through embodied signals"},
    ],

    # RESEARCH LENS - Scientific applications, data, analysis
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
      {"prototype", "amber", "assistive interfaces with sensor feedback"},
    ]
  }

  # Ordered list - empathy first and featured (larger button)
  @lens_info [
    {:empathy, %{
      name: "Empathy",
      icon: "hero-heart",
      color: "pink",
      description: "Feelings, relationships, presence",
      featured: true
    }},
    {:fun, %{
      name: "Fun",
      icon: "hero-puzzle-piece",
      color: "yellow",
      description: "Games, play, entertainment",
      featured: false
    }},
    {:technical, %{
      name: "Technical",
      icon: "hero-cpu-chip",
      color: "cyan",
      description: "Sensors, protocols, data flows",
      featured: false
    }},
    {:impact, %{
      name: "Impact",
      icon: "hero-globe-alt",
      color: "emerald",
      description: "Social good, accessibility, outcomes",
      featured: false
    }},
    {:research, %{
      name: "Research",
      icon: "hero-beaker",
      color: "purple",
      description: "Science, analysis, discovery",
      featured: false
    }}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # Start with empathy lens and shuffle its use cases
    current_lens = :empathy
    shuffled = Enum.shuffle(@use_cases_by_lens[current_lens])

    socket =
      socket
      |> assign(:detail_level, :spark)
      |> assign(:page_title, "About")
      |> assign(:current_lens, current_lens)
      |> assign(:lens_info, @lens_info)
      |> assign(:use_cases, shuffled)
      |> assign(:visible_count, 3)
      |> assign(:current_offset, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_level", %{"level" => level}, socket) do
    {:noreply, assign(socket, detail_level: String.to_existing_atom(level))}
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
    # Move to next batch or reshuffle if at the end
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

  # Helper to get visible use cases from the current offset
  defp visible_use_cases(use_cases, offset, count) do
    use_cases
    |> Enum.drop(offset)
    |> Enum.take(count)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800">
      <!-- Hero Section -->
      <div class="relative overflow-hidden">
        <div
          class="absolute inset-0 bg-gradient-to-r from-blue-900/20 via-cyan-900/10 to-purple-900/20 animate-pulse"
          style="animation-duration: 4s;"
        >
        </div>

        <div class="relative max-w-4xl mx-auto px-4 py-12 sm:py-16 text-center">
          <!-- Animated Logo -->
          <div class="mb-8 relative inline-block">
            <div
              class="absolute -inset-4 bg-cyan-500/20 rounded-full blur-xl animate-pulse"
              style="animation-duration: 3s;"
            >
            </div>
            <svg
              class="relative h-24 w-24 sm:h-32 sm:w-32 mx-auto text-cyan-400 animate-float"
              viewBox="0 0 100 100"
              fill="currentColor"
            >
              <!-- Octopus head -->
              <ellipse cx="50" cy="35" rx="25" ry="20" class="text-cyan-500" fill="currentColor" />
              <!-- Eyes -->
              <circle cx="42" cy="32" r="4" class="text-white" fill="currentColor" />
              <circle cx="58" cy="32" r="4" class="text-white" fill="currentColor" />
              <circle cx="43" cy="33" r="2" class="text-gray-900" fill="currentColor" />
              <circle cx="59" cy="33" r="2" class="text-gray-900" fill="currentColor" />
              <!-- Tentacles representing connection -->
              <path
                d="M25 45 Q15 55 10 70 Q8 80 15 85"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M30 50 Q22 62 18 78 Q16 88 22 92"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M38 52 Q32 68 30 82 Q29 92 35 95"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M50 54 Q50 72 50 88 Q50 95 50 98"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M62 52 Q68 68 70 82 Q71 92 65 95"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M70 50 Q78 62 82 78 Q84 88 78 92"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M75 45 Q85 55 90 70 Q92 80 85 85"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <path
                d="M78 40 Q88 48 95 60 Q98 70 92 78"
                stroke="currentColor"
                stroke-width="4"
                fill="none"
                stroke-linecap="round"
                class="text-cyan-400"
              />
              <!-- Heartbeat dots on tentacles -->
              <circle
                cx="15"
                cy="85"
                r="3"
                class="text-red-400 animate-pulse"
                fill="currentColor"
              />
              <circle
                cx="22"
                cy="92"
                r="3"
                class="text-pink-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 0.2s;"
              />
              <circle
                cx="35"
                cy="95"
                r="3"
                class="text-purple-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 0.4s;"
              />
              <circle
                cx="50"
                cy="98"
                r="3"
                class="text-blue-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 0.6s;"
              />
              <circle
                cx="65"
                cy="95"
                r="3"
                class="text-cyan-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 0.8s;"
              />
              <circle
                cx="78"
                cy="92"
                r="3"
                class="text-teal-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 1s;"
              />
              <circle
                cx="85"
                cy="85"
                r="3"
                class="text-green-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 1.2s;"
              />
              <circle
                cx="92"
                cy="78"
                r="3"
                class="text-yellow-400 animate-pulse"
                fill="currentColor"
                style="animation-delay: 1.4s;"
              />
            </svg>
          </div>

          <h1 class="text-4xl sm:text-5xl font-bold bg-gradient-to-r from-cyan-400 via-blue-400 to-purple-400 bg-clip-text text-transparent mb-4">
            SensOcto
          </h1>
          <p class="text-xl text-gray-400 mb-8">
            Feel someone's presence. Not their performance.
          </p>
          
    <!-- Detail Level Switcher -->
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
      
    <!-- Content Sections -->
      <div class="max-w-4xl mx-auto px-4 pb-24">
        <!-- The Spark: Core Philosophy (Always Visible) -->
        <div class="mb-12 text-center">
          <div class="inline-block px-3 py-1 bg-cyan-500/20 text-cyan-400 rounded-full text-xs font-medium mb-6">
            THE SPARK
          </div>

          <p class="text-2xl sm:text-3xl text-white leading-relaxed max-w-3xl mx-auto mb-8">
            Technology promised connection and delivered <span class="text-gray-500">performance</span>.
            We scroll, we perform, we feel more alone.
          </p>

          <!-- Lens Switcher -->
          <div class="flex justify-center items-center gap-2 mb-6">
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
                <.icon name={info.icon} class={if info.featured, do: "h-4 w-4", else: "h-3.5 w-3.5"} />
                <span><%= info.name %></span>
              </button>
            <% end %>
          </div>

          <!-- Clickable Use Cases Carousel -->
          <div
            class="text-xl text-gray-400 max-w-2xl mx-auto mb-6 cursor-pointer hover:text-gray-300 transition-colors group"
            phx-click="shuffle_use_cases"
            title="Click for more examples"
          >
            <p class="leading-relaxed">
              What if you could
              <%= for {{verb, color, rest}, index} <- Enum.with_index(visible_use_cases(@use_cases, @current_offset, @visible_count)) do %>
                <span class={"text-#{color}-400 font-medium"}><%= verb %></span>
                <%= rest %><%= if index < @visible_count - 1, do: "? ", else: "?" %>
              <% end %>
            </p>
            <div class="flex items-center justify-center gap-2 mt-3 text-sm text-gray-500 group-hover:text-gray-400 transition-colors">
              <.icon name="hero-arrow-path" class="h-4 w-4" />
              <span>Click for more examples</span>
            </div>
          </div>

          <!-- Slider for visible count -->
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
            <span class="text-sm text-cyan-400 w-6 text-center"><%= @visible_count %></span>
          </form>

          <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 max-w-2xl mx-auto">
            <p class="text-lg text-gray-300 italic">
              "Connection becomes tangible when you can feel someone's presence—their heartbeat, their calm, their stress—in real-time."
            </p>
          </div>
        </div>
        
    <!-- The Story: Human Use Cases -->
        <div class={"transition-all duration-500 overflow-hidden " <> if @detail_level in [:story, :deep], do: "opacity-100 max-h-[4000px]", else: "opacity-0 max-h-0"}>
          <div class="border-t border-gray-800 pt-12 mb-12">
            <div class="inline-block px-3 py-1 bg-blue-500/20 text-blue-400 rounded-full text-xs font-medium mb-6">
              THE STORY
            </div>

            <h2 class="text-2xl font-semibold text-white mb-8 text-center">
              Built for humans who want to <span class="text-blue-400">truly</span> connect
            </h2>

            <div class="grid gap-6 mb-10">
              <!-- Therapy & Healing -->
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
              
    <!-- Disability & Care -->
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
              
    <!-- Mental Health Networks -->
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
              
    <!-- Intimacy & Consent -->
              <div class="bg-gray-800/50 rounded-xl p-6 border border-gray-700/50 hover:border-pink-500/30 transition-colors">
                <div class="flex items-start gap-4">
                  <div class="p-3 bg-pink-500/20 rounded-lg shrink-0">
                    <.icon name="hero-sparkles" class="h-6 w-6 text-pink-400" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-white mb-2">Intimacy & Embodied Consent</h3>
                    <p class="text-gray-400 mb-3">
                      Real arousal, real consent, real connection. Partners see each other's actual physiological state—no guessing, no performance. Marginalized communities finally served by technology that respects their needs.
                    </p>
                    <p class="text-pink-400 text-sm">
                      "Consent infrastructure for bodies, not just words."
                    </p>
                  </div>
                </div>
              </div>
              
    <!-- Groups & Collective Presence -->
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
            
    <!-- The Promise -->
            <div class="bg-gradient-to-r from-cyan-900/20 via-blue-900/20 to-purple-900/20 rounded-xl p-8 border border-gray-700/50 text-center">
              <h3 class="text-xl font-semibold text-white mb-4">The Promise</h3>
              <p class="text-lg text-gray-300 max-w-2xl mx-auto">
                Connection measured in <span class="text-red-400">heartbeats</span>, not dopamine hits.
                Technology that <span class="text-cyan-400">amplifies empathy</span>
                instead of exploiting attention.
                No harvesting. No surveillance. No algorithms deciding who sees what.
              </p>
            </div>
          </div>
        </div>
        
    <!-- The Deep Dive: Architecture as Values -->
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
            
    <!-- P2P as Foundation -->
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
            
    <!-- Biomimetic Intelligence -->
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
            
    <!-- Tech Stack -->
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
            
    <!-- Open Source Note -->
            <div class="text-center text-gray-500 text-sm">
              <p>
                Built with <span class="text-red-400">♥</span>
                for humans who believe technology should serve connection, not extraction.
              </p>
            </div>
          </div>
        </div>
        
    <!-- Footer CTA -->
        <div class="mt-12 text-center">
          <.link
            navigate={~p"/sign-in"}
            class="inline-flex items-center gap-2 px-6 py-3 bg-cyan-600 hover:bg-cyan-500 text-white font-medium rounded-lg transition-colors"
          >
            <.icon name="hero-play" class="h-5 w-5" /> Get Started
          </.link>
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
