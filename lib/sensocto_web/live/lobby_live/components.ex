defmodule SensoctoWeb.LobbyLive.Components do
  @moduledoc """
  Function components extracted from lobby_live.html.heex for diff isolation.
  Each component wraps a self-contained UI section so LiveView skips diffing
  subtrees whose assigns haven't changed.
  """
  use Phoenix.Component
  use SensoctoWeb, :verified_routes

  attr :in_call, :boolean, required: true
  attr :call_participants, :map, required: true
  attr :audio_enabled, :boolean, required: true
  attr :video_enabled, :boolean, required: true
  attr :call_expanded, :boolean, required: true
  attr :current_user, :any, required: true

  def call_controls(assigns) do
    ~H"""
    <div class="mb-4 p-3 bg-gray-800/50 rounded-lg border border-gray-700">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <Heroicons.icon name="phone" type="solid" class="h-5 w-5 text-gray-300" />
          <span class="text-sm text-gray-300 font-medium">Voice/Video Call</span>
        </div>

        <%= if @in_call do %>
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-2 text-sm text-green-400">
              <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
              <span>Connected</span>
              <span class="text-gray-500">
                ({map_size(@call_participants) + 1} in call)
              </span>
            </div>

            <div class="flex items-center gap-1">
              <button
                phx-click="toggle_call_audio"
                class={"p-2 rounded-lg transition-colors " <> if(@audio_enabled, do: "bg-gray-700 hover:bg-gray-600 text-gray-300", else: "bg-red-600 hover:bg-red-500 text-white")}
                title={if @audio_enabled, do: "Mute microphone", else: "Unmute microphone"}
              >
                <Heroicons.icon
                  name={if @audio_enabled, do: "microphone", else: "microphone"}
                  type="solid"
                  class="h-4 w-4"
                />
              </button>
              <button
                phx-click="toggle_call_video"
                class={"p-2 rounded-lg transition-colors " <> if(@video_enabled, do: "bg-gray-700 hover:bg-gray-600 text-gray-300", else: "bg-red-600 hover:bg-red-500 text-white")}
                title={if @video_enabled, do: "Turn off camera", else: "Turn on camera"}
              >
                <Heroicons.icon name="video-camera" type="solid" class="h-4 w-4" />
              </button>
            </div>

            <button
              phx-click="toggle_call_expanded"
              class={"p-2 rounded-lg transition-colors " <> if(@call_expanded, do: "bg-green-600 text-white", else: "bg-gray-700 hover:bg-gray-600 text-gray-300")}
              title={if @call_expanded, do: "Hide participants", else: "Show participants"}
            >
              <Heroicons.icon
                name={if @call_expanded, do: "chevron-up", else: "chevron-down"}
                type="solid"
                class="h-4 w-4"
              />
            </button>

            <button
              phx-click="leave_call"
              class="px-3 py-1.5 rounded-lg text-sm font-medium bg-red-600 hover:bg-red-500 text-white transition-colors"
            >
              Leave
            </button>
          </div>
        <% else %>
          <div class="flex items-center gap-2">
            <span class="text-sm text-gray-500">Not connected</span>
            <button
              phx-click="quick_join_call"
              phx-value-mode="video"
              class="px-3 py-1.5 rounded-l-lg text-sm font-medium transition-all flex items-center gap-2 bg-green-600 hover:bg-green-500 text-white"
              title="Join with video"
            >
              <Heroicons.icon name="video-camera" type="solid" class="h-4 w-4" /> Join
            </button>
            <button
              phx-click="quick_join_call"
              phx-value-mode="audio"
              class="px-2 py-1.5 rounded-r-lg text-sm font-medium transition-all flex items-center bg-green-700 hover:bg-green-600 text-white border-l border-green-800"
              title="Join with voice only"
            >
              <Heroicons.icon name="microphone" type="solid" class="h-4 w-4" />
            </button>
          </div>
        <% end %>
      </div>

      <div :if={@in_call && @call_expanded} class="mt-4 pt-4 border-t border-gray-700">
        <.live_component
          module={SensoctoWeb.Live.Calls.CallContainerComponent}
          id="lobby-call-container"
          room={%{id: :lobby, name: "Lobby", calls_enabled: true}}
          user={@current_user}
          in_call={@in_call}
          participants={@call_participants}
          external_hook={true}
        />
      </div>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :public_rooms, :list, required: true
  attr :join_code, :string, required: true

  def join_room_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-click="close_join_modal"
    >
      <div
        class="bg-gray-800 rounded-lg p-6 w-full max-w-md max-h-[80vh] overflow-y-auto"
        phx-click={%Phoenix.LiveView.JS{}}
      >
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Join a Room</h2>
          <button phx-click="close_join_modal" class="text-gray-300 hover:text-white">
            <Heroicons.icon name="x-mark" type="outline" class="h-6 w-6" />
          </button>
        </div>

        <div class="mb-6">
          <label for="join_code" class="block text-sm font-medium text-gray-300 mb-2">
            Enter Room Code
          </label>
          <form phx-submit="join_room_by_code" class="flex gap-2">
            <input
              type="text"
              name="join_code"
              id="join_code"
              value={@join_code}
              phx-change="update_join_code"
              placeholder="ABCD1234"
              aria-describedby="join_code_help"
              class="flex-1 bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white uppercase tracking-wider font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
              maxlength="12"
              autocomplete="off"
            />
            <button
              type="submit"
              class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
            >
              Join
            </button>
          </form>
          <p id="join_code_help" class="text-xs text-gray-500 mt-1">
            Enter the room's join code to connect with your sensors
          </p>
        </div>

        <%= if @public_rooms != [] do %>
          <div class="border-t border-gray-700 pt-4">
            <h3 class="text-sm font-medium text-gray-300 mb-3">Or join a public room</h3>
            <div class="space-y-2 max-h-60 overflow-y-auto">
              <%= for room <- @public_rooms do %>
                <div class="flex items-center justify-between p-3 bg-gray-700 rounded-lg hover:bg-gray-600 transition-colors">
                  <div class="flex-1 min-w-0">
                    <p class="font-medium text-white truncate">{room.name}</p>
                    <p :if={room.description} class="text-xs text-gray-300 truncate">
                      {room.description}
                    </p>
                  </div>
                  <button
                    phx-click="join_room"
                    phx-value-room_id={room.id}
                    class="ml-3 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium py-1.5 px-3 rounded transition-colors flex-shrink-0"
                  >
                    Join
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="mt-6 pt-4 border-t border-gray-700">
          <.link
            navigate={~p"/rooms/new"}
            class="block w-full text-center bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
          >
            Create New Room
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :modal, :map, required: true

  def control_request_modal(assigns) do
    ~H"""
    <div
      :if={@modal}
      id="lobby-control-request-modal"
      phx-hook="NotificationSound"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm"
    >
      <div class="bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden border border-gray-700">
        <div class="bg-gradient-to-r from-cyan-600 to-blue-600 px-6 py-4">
          <div class="flex items-center gap-3">
            <div class="p-2 bg-white/20 rounded-full">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                />
              </svg>
            </div>
            <h2 class="text-xl font-bold text-white">Control Request</h2>
          </div>
        </div>

        <div class="p-6">
          <div class="flex items-center gap-4 mb-6">
            <div class="w-14 h-14 bg-gray-700 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                />
              </svg>
            </div>
            <div>
              <p class="text-lg font-semibold text-white">{@modal.requester_name}</p>
              <p class="text-sm text-gray-300">wants to control the 3D viewer</p>
            </div>
          </div>

          <p class="text-gray-300 text-sm mb-4">
            Transferring control will allow them to navigate the 3D scene while you follow their view.
          </p>

          <div
            id="object3d-control-countdown"
            phx-hook="CountdownTimer"
            role="timer"
            aria-live="polite"
            aria-atomic="true"
            data-seconds="30"
            class="mb-6 p-3 bg-amber-900/30 border border-amber-600/50 rounded-lg"
          >
            <p class="text-amber-200 text-sm flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              Control will auto-transfer in <span class="font-bold countdown-display">30</span>s
            </p>
          </div>

          <div class="flex gap-3">
            <button
              phx-click="dismiss_control_request"
              class="flex-1 px-4 py-3 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors"
            >
              Keep Control
            </button>
            <button
              phx-click="release_control_from_modal"
              class="flex-1 px-4 py-3 bg-cyan-600 hover:bg-cyan-500 text-white font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                />
              </svg>
              Transfer Control
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :modal, :map, required: true

  def media_control_request_modal(assigns) do
    ~H"""
    <div
      :if={@modal}
      id="lobby-media-control-request-modal"
      phx-hook="NotificationSound"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm"
    >
      <div class="bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden border border-gray-700">
        <div class="bg-gradient-to-r from-red-600 to-orange-600 px-6 py-4">
          <div class="flex items-center gap-3">
            <div class="p-2 bg-white/20 rounded-full">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <h2 class="text-xl font-bold text-white">Media Control Request</h2>
          </div>
        </div>

        <div class="p-6">
          <div class="flex items-center gap-4 mb-6">
            <div class="w-14 h-14 bg-gray-700 rounded-full flex items-center justify-center">
              <svg class="w-8 h-8 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                />
              </svg>
            </div>
            <div>
              <p class="text-lg font-semibold text-white">{@modal.requester_name}</p>
              <p class="text-sm text-gray-300">wants to control the media player</p>
            </div>
          </div>

          <p class="text-gray-300 text-sm mb-4">
            Transferring control will allow them to play, pause, and navigate the media playlist.
          </p>

          <div
            id="media-control-countdown"
            phx-hook="CountdownTimer"
            role="timer"
            aria-live="polite"
            aria-atomic="true"
            data-seconds="30"
            class="mb-6 p-3 bg-amber-900/30 border border-amber-600/50 rounded-lg"
          >
            <p class="text-amber-200 text-sm flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              Control will auto-transfer in <span class="font-bold countdown-display">30</span>s
            </p>
          </div>

          <div class="flex gap-3">
            <button
              phx-click="dismiss_media_control_request"
              class="flex-1 px-4 py-3 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors"
            >
              Keep Control
            </button>
            <button
              phx-click="release_media_control_from_modal"
              class="flex-1 px-4 py-3 bg-red-600 hover:bg-red-500 text-white font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                />
              </svg>
              Transfer Control
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
