defmodule SensoctoWeb.Live.Calls.CallContainerComponent do
  @moduledoc """
  LiveView component for video call UI.
  Handles call controls and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:in_call, false)
     |> assign(:audio_enabled, true)
     |> assign(:video_enabled, true)
     |> assign(:participants, %{})
     |> assign(:connection_state, "disconnected")
     |> assign(:call_state, "idle")
     |> assign(:call_error, nil)
     |> assign(:reconnect_info, nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:room, assigns.room)
      |> assign(:user, assigns.user)
      # in_call and participants come from parent - always update them
      |> assign(:in_call, assigns[:in_call] || false)
      |> assign(:participants, assigns[:participants] || %{})
      # external_hook: true means the CallHook is mounted separately (persistent)
      # This allows the component to render just the UI without managing the hook
      |> assign(:external_hook, assigns[:external_hook] || false)
      # These are component-internal state - use assign_new to preserve
      |> assign_new(:audio_enabled, fn -> true end)
      |> assign_new(:video_enabled, fn -> true end)
      |> assign_new(:connection_state, fn -> "disconnected" end)
      |> assign_new(:call_state, fn -> "idle" end)
      |> assign_new(:call_error, fn -> nil end)
      |> assign_new(:reconnect_info, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def handle_event("join_call", %{"mode" => mode}, socket) do
    video_enabled = mode == "video"
    send(self(), {:push_event, "join_call", %{mode: mode}})
    {:noreply, assign(socket, :video_enabled, video_enabled)}
  end

  @impl true
  def handle_event("join_call", _, socket) do
    send(self(), {:push_event, "join_call", %{mode: "video"}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("leave_call", _, socket) do
    send(self(), {:push_event, "leave_call", %{}})
    {:noreply, assign(socket, :in_call, false)}
  end

  @impl true
  def handle_event("toggle_audio", _, socket) do
    new_state = !socket.assigns.audio_enabled
    send(self(), {:push_event, "toggle_audio", %{enabled: new_state}})
    {:noreply, assign(socket, :audio_enabled, new_state)}
  end

  @impl true
  def handle_event("toggle_video", _, socket) do
    new_state = !socket.assigns.video_enabled
    send(self(), {:push_event, "toggle_video", %{enabled: new_state}})
    {:noreply, assign(socket, :video_enabled, new_state)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="call-container"
      phx-hook={if @external_hook, do: nil, else: "CallHook"}
      data-room-id={@room.id}
      data-user-id={@user.id}
      data-user-name={@user.email |> to_string()}
    >
      <%= if @in_call do %>
        <%!-- In-call panel --%>
        <div class="bg-gray-800 rounded-lg overflow-hidden">
          <%!-- Header --%>
          <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
            <div class="flex items-center gap-2">
              <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
              <span class="text-sm text-green-400">In Call</span>
            </div>
          </div>

          <%!-- Video grid --%>
          <div class="p-2">
            <.video_grid
              participants={@participants}
              user={@user}
              audio_enabled={@audio_enabled}
              video_enabled={@video_enabled}
            />
          </div>

          <%!-- Controls --%>
          <.call_controls
            in_call={@in_call}
            audio_enabled={@audio_enabled}
            video_enabled={@video_enabled}
            target={@myself}
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp video_grid(assigns) do
    ~H"""
    <div class="h-full grid gap-2 auto-rows-fr" style={grid_style(map_size(@participants) + 1)}>
      <.video_tile
        id="local-video"
        is_local={true}
        user={@user}
        audio_enabled={@audio_enabled}
        video_enabled={@video_enabled}
      />

      <%= for {peer_id, participant} <- @participants do %>
        <.video_tile
          id={"participant-#{peer_id}"}
          is_local={false}
          peer_id={peer_id}
          participant={participant}
        />
      <% end %>
    </div>
    """
  end

  defp video_tile(assigns) do
    assigns =
      assigns
      |> assign_new(:peer_id, fn -> nil end)
      |> assign_new(:participant, fn -> nil end)
      |> assign_new(:audio_enabled, fn -> true end)
      |> assign_new(:video_enabled, fn -> true end)
      |> assign_new(:tier, fn -> get_participant_tier(assigns[:participant]) end)
      |> assign_new(:speaking, fn -> get_participant_speaking(assigns[:participant]) end)

    ~H"""
    <div
      id={@id}
      phx-hook="VideoTileHook"
      data-peer-id={@peer_id}
      data-is-local={to_string(@is_local)}
      class={"relative bg-gray-900 rounded-lg overflow-hidden aspect-video " <>
        if(@speaking, do: "ring-2 ring-green-400", else: "")}
    >
      <video
        autoplay
        playsinline
        muted={@is_local}
        class="w-full h-full object-cover"
      >
      </video>

      <%!-- Tier indicator badge --%>
      <div class="absolute top-2 right-2">
        <.tier_badge tier={@tier} />
      </div>

      <%!-- Speaking indicator (pulsing border effect handled by class above) --%>
      <%= if @speaking do %>
        <div class="absolute top-2 left-2">
          <span class="flex h-3 w-3">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
          </span>
        </div>
      <% end %>

      <div class="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/70 to-transparent">
        <div class="flex items-center justify-between">
          <span class="text-white text-sm font-medium truncate">
            <%= if @is_local do %>
              You
            <% else %>
              {get_participant_name(@participant)}
            <% end %>
          </span>

          <div class="flex items-center gap-2">
            <%= if !@audio_enabled do %>
              <span class="p-1 bg-red-500 rounded-full">
                <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"
                  />
                </svg>
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @is_local && !@video_enabled do %>
        <div class="absolute inset-0 flex items-center justify-center bg-gray-800">
          <div class="w-20 h-20 rounded-full bg-gray-700 flex items-center justify-center">
            <span class="text-2xl text-gray-400">
              {@user.email |> to_string() |> String.first() |> String.upcase()}
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp tier_badge(assigns) do
    ~H"""
    <%= case @tier do %>
      <% :active -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-green-500/80 text-white"
          title="Active speaker - HD video"
        >
          HD
        </span>
      <% :recent -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-blue-500/80 text-white"
          title="Recently active - SD video"
        >
          SD
        </span>
      <% :viewer -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-gray-500/80 text-white"
          title="Viewer mode - snapshots"
        >
          📷
        </span>
      <% :idle -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-gray-700/80 text-gray-300"
          title="Idle - no video"
        >
          💤
        </span>
      <% _ -> %>
        <span></span>
    <% end %>
    """
  end

  defp call_controls(assigns) do
    ~H"""
    <div class="px-3 py-2 bg-gray-900/50 border-t border-gray-700">
      <div class="flex items-center justify-center gap-2">
        <button
          phx-click="toggle_audio"
          phx-target={@target}
          class={"p-2 rounded-full transition-colors " <>
            if(@audio_enabled, do: "bg-gray-700 hover:bg-gray-600", else: "bg-red-600 hover:bg-red-500")}
          title={if @audio_enabled, do: "Mute microphone", else: "Unmute microphone"}
        >
          <%= if @audio_enabled do %>
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
              />
            </svg>
          <% else %>
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"
              />
            </svg>
          <% end %>
        </button>

        <button
          phx-click="toggle_video"
          phx-target={@target}
          class={"p-2 rounded-full transition-colors " <>
            if(@video_enabled, do: "bg-gray-700 hover:bg-gray-600", else: "bg-red-600 hover:bg-red-500")}
          title={if @video_enabled, do: "Turn off camera", else: "Turn on camera"}
        >
          <%= if @video_enabled do %>
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
              />
            </svg>
          <% else %>
            <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
              />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 3l18 18" />
            </svg>
          <% end %>
        </button>

        <button
          phx-click="leave_call"
          phx-target={@target}
          class="px-3 py-1.5 rounded-full bg-red-600 hover:bg-red-500 transition-colors text-white text-xs font-medium"
        >
          Leave
        </button>
      </div>
    </div>
    """
  end

  defp grid_style(count) when count <= 1, do: "grid-template-columns: 1fr;"
  defp grid_style(count) when count <= 2, do: "grid-template-columns: repeat(2, 1fr);"
  defp grid_style(count) when count <= 4, do: "grid-template-columns: repeat(2, 1fr);"
  defp grid_style(count) when count <= 6, do: "grid-template-columns: repeat(3, 1fr);"
  defp grid_style(count) when count <= 9, do: "grid-template-columns: repeat(3, 1fr);"
  defp grid_style(count) when count <= 12, do: "grid-template-columns: repeat(4, 1fr);"
  defp grid_style(_count), do: "grid-template-columns: repeat(5, 1fr);"

  defp get_participant_name(nil), do: "Participant"

  defp get_participant_name(participant) do
    case participant do
      %{user_info: %{name: name}} when is_binary(name) -> name
      %{metadata: %{displayName: name}} when is_binary(name) -> name
      %{user_id: user_id} -> "User #{String.slice(user_id, 0..7)}"
      _ -> "Participant"
    end
  end

  defp get_participant_tier(nil), do: :viewer

  defp get_participant_tier(participant) do
    case participant do
      %{tier: tier} when tier in [:active, :recent, :viewer, :idle] -> tier
      _ -> :viewer
    end
  end

  defp get_participant_speaking(nil), do: false

  defp get_participant_speaking(participant) do
    case participant do
      %{speaking: speaking} when is_boolean(speaking) -> speaking
      _ -> false
    end
  end
end
