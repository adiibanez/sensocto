defmodule SensoctoWeb.CustomSignInLive do
  @moduledoc """
  Custom sign-in page that integrates the About page content alongside the authentication form.
  """
  use SensoctoWeb, :live_view
  alias AshAuthentication.Phoenix.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, detail_level: :spark, show_about: true),
     layout: {SensoctoWeb.Layouts, :auth}}
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
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800 flex flex-col lg:flex-row">
      <%!-- Left Side: About Content (collapsible on mobile) --%>
      <div class={"lg:w-1/2 lg:min-h-screen overflow-y-auto " <> if @show_about, do: "block", else: "hidden lg:block"}>
        <div class="relative overflow-hidden">
          <div
            class="absolute inset-0 bg-gradient-to-r from-blue-900/20 via-cyan-900/10 to-purple-900/20 animate-pulse"
            style="animation-duration: 4s;"
          >
          </div>

          <div class="relative max-w-xl mx-auto px-4 py-8 lg:py-12 text-center">
            <%!-- Animated Logo --%>
            <div class="mb-6 relative inline-block">
              <div
                class="absolute -inset-4 bg-cyan-500/20 rounded-full blur-xl animate-pulse"
                style="animation-duration: 3s;"
              >
              </div>
              <svg
                class="relative h-20 w-20 lg:h-24 lg:w-24 mx-auto text-cyan-400 animate-float"
                viewBox="0 0 100 100"
                fill="currentColor"
              >
                <%!-- Octopus head --%>
                <ellipse cx="50" cy="35" rx="25" ry="20" class="text-cyan-500" fill="currentColor" />
                <%!-- Eyes --%>
                <circle cx="42" cy="32" r="4" class="text-white" fill="currentColor" />
                <circle cx="58" cy="32" r="4" class="text-white" fill="currentColor" />
                <circle cx="43" cy="33" r="2" class="text-gray-900" fill="currentColor" />
                <circle cx="59" cy="33" r="2" class="text-gray-900" fill="currentColor" />
                <%!-- Tentacles --%>
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
                <%!-- Heartbeat dots --%>
                <circle cx="15" cy="85" r="3" class="text-red-400 animate-pulse" fill="currentColor" />
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

            <h1 class="text-3xl lg:text-4xl font-bold bg-gradient-to-r from-cyan-400 via-blue-400 to-purple-400 bg-clip-text text-transparent mb-3">
              SensOcto
            </h1>
            <p class="text-lg text-gray-400 mb-6">
              Feel someone's presence. Not their performance.
            </p>

            <%!-- Detail Level Switcher --%>
            <div class="flex justify-center gap-2 mb-8">
              <button
                phx-click="set_level"
                phx-value-level="spark"
                class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all duration-300 " <>
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
                class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all duration-300 " <>
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
                class={"px-3 py-1.5 rounded-full text-xs font-medium transition-all duration-300 " <>
                  if @detail_level == :deep do
                    "bg-purple-500 text-white shadow-lg shadow-purple-500/30"
                  else
                    "bg-gray-800 text-gray-400 hover:text-white hover:bg-gray-700"
                  end}
              >
                Deep Dive
              </button>
            </div>
          </div>
        </div>

        <%!-- About Content --%>
        <div class="max-w-xl mx-auto px-4 pb-8">
          <%!-- The Spark --%>
          <div class="mb-8 text-center">
            <p class="text-xl text-white leading-relaxed mb-4">
              Technology promised connection and delivered <span class="text-gray-500">performance</span>.
              We scroll, we perform, we feel more alone.
            </p>
            <p class="text-gray-400 mb-4">
              What if you could <span class="text-cyan-400">feel</span>
              someone's nervousness before a presentation? <span class="text-pink-400">Sense</span>
              a partner's arousal without words?
            </p>
          </div>

          <%!-- The Story --%>
          <div class={"transition-all duration-500 overflow-hidden " <> if @detail_level in [:story, :deep], do: "opacity-100 max-h-[2000px]", else: "opacity-0 max-h-0"}>
            <div class="border-t border-gray-800 pt-6 mb-6">
              <h2 class="text-lg font-semibold text-white mb-4 text-center">
                Built for humans who want to <span class="text-blue-400">truly</span> connect
              </h2>
              <div class="grid gap-3 text-sm">
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="flex items-center gap-2 mb-1">
                    <.icon name="hero-heart" class="h-4 w-4 text-green-400" />
                    <span class="text-white font-medium">Therapy & Healing</span>
                  </div>
                  <p class="text-gray-400 text-xs">
                    See nervous system responses in real-time during sessions.
                  </p>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="flex items-center gap-2 mb-1">
                    <.icon name="hero-users" class="h-4 w-4 text-purple-400" />
                    <span class="text-white font-medium">Mental Health Networks</span>
                  </div>
                  <p class="text-gray-400 text-xs">
                    Trusted contacts see rising stress and can reach out proactively.
                  </p>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-3 border border-gray-700/50">
                  <div class="flex items-center gap-2 mb-1">
                    <.icon name="hero-sparkles" class="h-4 w-4 text-pink-400" />
                    <span class="text-white font-medium">Intimacy & Consent</span>
                  </div>
                  <p class="text-gray-400 text-xs">
                    Real connection through shared physiological awareness.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <%!-- Deep Dive --%>
          <div class={"transition-all duration-500 overflow-hidden " <> if @detail_level == :deep, do: "opacity-100 max-h-[1500px]", else: "opacity-0 max-h-0"}>
            <div class="border-t border-gray-800 pt-6">
              <h3 class="text-lg font-semibold text-white mb-3 text-center">
                Why Peer-to-Peer?
              </h3>
              <div class="grid grid-cols-2 gap-2 text-xs mb-4">
                <div class="bg-gray-800/50 rounded-lg p-2 border border-gray-700/50">
                  <div class="text-green-400 font-medium">Privacy by Structure</div>
                  <div class="text-gray-500">Data stays on your devices</div>
                </div>
                <div class="bg-gray-800/50 rounded-lg p-2 border border-gray-700/50">
                  <div class="text-green-400 font-medium">No Harvesting</div>
                  <div class="text-gray-500">Near-zero marginal cost</div>
                </div>
              </div>
              <div class="flex flex-wrap gap-1 justify-center">
                <span class="px-2 py-0.5 bg-purple-900/30 text-purple-300 rounded-full text-xs">
                  Elixir/OTP
                </span>
                <span class="px-2 py-0.5 bg-orange-900/30 text-orange-300 rounded-full text-xs">
                  Phoenix
                </span>
                <span class="px-2 py-0.5 bg-cyan-900/30 text-cyan-300 rounded-full text-xs">
                  Iroh P2P
                </span>
                <span class="px-2 py-0.5 bg-green-900/30 text-green-300 rounded-full text-xs">
                  WebRTC
                </span>
              </div>
            </div>
          </div>

          <%!-- Show more details or link to full page --%>
          <div class="mt-6 text-center space-y-2">
            <%= if @detail_level != :deep do %>
              <button
                phx-click="set_level"
                phx-value-level="deep"
                class="text-cyan-400 hover:text-cyan-300 text-sm underline"
              >
                Read more →
              </button>
            <% else %>
              <.link
                href={~p"/about"}
                class="text-cyan-400 hover:text-cyan-300 text-sm underline"
              >
                View full about page (new tab) ↗
              </.link>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Right Side: Sign In Form --%>
      <div class="lg:w-1/2 flex items-center justify-center p-4 lg:p-8 bg-gray-900/50">
        <div class="w-full max-w-md">
          <%!-- Mobile toggle for about section --%>
          <button
            phx-click="toggle_about"
            class="lg:hidden w-full mb-4 px-4 py-2 text-sm text-gray-400 hover:text-white bg-gray-800/50 rounded-lg border border-gray-700"
          >
            {if @show_about, do: "Hide About", else: "What is SensOcto?"}
          </button>

          <div class="bg-gray-800/50 rounded-xl p-6 lg:p-8 border border-gray-700/50">
            <h2 class="text-2xl font-bold text-white text-center mb-6">Welcome Back</h2>

            <.live_component
              module={Components.SignIn}
              id="sign-in-component"
              otp_app={@otp_app}
              auth_routes_prefix="/auth"
              overrides={[SensoctoWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]}
            />
          </div>

          <p class="text-center text-gray-500 text-sm mt-6">
            By signing in, you agree to our terms of service and privacy policy.
          </p>
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
