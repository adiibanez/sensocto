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
     |> assign(:show_call_panel, false)}
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
      # These are component-internal state - use assign_new to preserve
      |> assign_new(:show_call_panel, fn -> false end)
      |> assign_new(:audio_enabled, fn -> true end)
      |> assign_new(:video_enabled, fn -> true end)
      |> assign_new(:connection_state, fn -> "disconnected" end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_call_panel", _, socket) do
    {:noreply, assign(socket, :show_call_panel, !socket.assigns.show_call_panel)}
  end

  @impl true
  def handle_event("join_call", _, socket) do
    send(self(), {:push_event, "join_call", %{}})
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
      phx-hook="CallHook"
      data-room-id={@room.id}
      data-user-id={@user.id}
      data-user-name={@user.email}
      class="relative"
    >
      <%= if @show_call_panel do %>
        <%!-- Leave space at bottom for footer (pb-32) and top for header --%>
        <div class="fixed inset-x-0 top-16 bottom-32 z-40 bg-black/95 flex flex-col rounded-b-lg mx-2">
          <%!-- Video area - takes 60% when in call to leave room for sensor data --%>
          <div class={if @in_call, do: "h-[60%] p-3 overflow-hidden", else: "flex-1 p-4 overflow-hidden"}>
            <%= if @in_call do %>
              <.video_grid
                participants={@participants}
                user={@user}
                audio_enabled={@audio_enabled}
                video_enabled={@video_enabled}
              />
            <% else %>
              <.call_preview user={@user} />
            <% end %>
          </div>

          <%!-- Sensor data area - only visible when in call --%>
          <%= if @in_call do %>
            <div class="h-[25%] px-3 pb-2 overflow-y-auto">
              <div class="bg-gray-800/50 rounded-lg p-2 h-full">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-xs text-gray-400 font-medium">Sensor Data</span>
                  <span class="text-xs text-gray-500">Minimized view</span>
                </div>
                <div class="text-gray-500 text-sm text-center py-4">
                  Sensor data will appear here
                </div>
              </div>
            </div>
          <% end %>

          <.call_controls
            in_call={@in_call}
            audio_enabled={@audio_enabled}
            video_enabled={@video_enabled}
            target={@myself}
          />
        </div>
      <% end %>

      <button
        phx-click="toggle_call_panel"
        phx-target={@myself}
        class={"fixed bottom-36 right-4 z-30 p-4 rounded-full shadow-lg transition-colors " <>
          if(@in_call, do: "bg-green-600 hover:bg-green-700", else: "bg-blue-600 hover:bg-blue-700")}
      >
        <%= if @in_call do %>
          <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
          </svg>
        <% else %>
          <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
          </svg>
        <% end %>
        <%= if @in_call do %>
          <span class="absolute top-0 right-0 block h-3 w-3 rounded-full bg-green-400 ring-2 ring-white"></span>
        <% end %>
      </button>
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

    ~H"""
    <div
      id={@id}
      phx-hook="VideoTileHook"
      data-peer-id={@peer_id}
      data-is-local={to_string(@is_local)}
      class="relative bg-gray-900 rounded-lg overflow-hidden aspect-video"
    >
      <video
        autoplay
        playsinline
        muted={@is_local}
        class="w-full h-full object-cover"
      >
      </video>

      <div class="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-black/70 to-transparent">
        <div class="flex items-center justify-between">
          <span class="text-white text-sm font-medium truncate">
            <%= if @is_local do %>
              You
            <% else %>
              <%= get_participant_name(@participant) %>
            <% end %>
          </span>

          <div class="flex items-center gap-2">
            <%= if !@audio_enabled do %>
              <span class="p-1 bg-red-500 rounded-full">
                <svg class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
                </svg>
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @is_local && !@video_enabled do %>
        <div class="absolute inset-0 flex items-center justify-center bg-gray-800">
          <div class="w-20 h-20 rounded-full bg-gray-700 flex items-center justify-center">
            <span class="text-2xl text-gray-400"><%= String.first(@user.email) |> String.upcase() %></span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp call_preview(assigns) do
    ~H"""
    <div class="h-full flex items-center justify-center">
      <div class="text-center">
        <div class="w-48 h-48 mx-auto mb-6 rounded-lg overflow-hidden bg-gray-800">
          <video
            id="local-video-preview"
            autoplay
            playsinline
            muted
            class="w-full h-full object-cover"
          >
          </video>
        </div>

        <h3 class="text-xl font-semibold text-white mb-2">Ready to join?</h3>
        <p class="text-gray-400 mb-6">Preview your camera and microphone before joining the call.</p>
      </div>
    </div>
    """
  end

  defp call_controls(assigns) do
    ~H"""
    <div class="flex-none p-4 bg-gray-900">
      <div class="flex items-center justify-center gap-4">
        <%= if @in_call do %>
          <button
            phx-click="toggle_audio"
            phx-target={@target}
            class={"p-4 rounded-full transition-colors " <>
              if(@audio_enabled, do: "bg-gray-700 hover:bg-gray-600", else: "bg-red-600 hover:bg-red-500")}
          >
            <%= if @audio_enabled do %>
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              </svg>
            <% else %>
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
              </svg>
            <% end %>
          </button>

          <button
            phx-click="toggle_video"
            phx-target={@target}
            class={"p-4 rounded-full transition-colors " <>
              if(@video_enabled, do: "bg-gray-700 hover:bg-gray-600", else: "bg-red-600 hover:bg-red-500")}
          >
            <%= if @video_enabled do %>
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            <% else %>
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 3l18 18" />
              </svg>
            <% end %>
          </button>

          <button
            phx-click="leave_call"
            phx-target={@target}
            class="p-4 rounded-full bg-red-600 hover:bg-red-500 transition-colors"
          >
            <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 8l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2M5 3a2 2 0 00-2 2v1c0 8.284 6.716 15 15 15h1a2 2 0 002-2v-3.28a1 1 0 00-.684-.948l-4.493-1.498a1 1 0 00-1.21.502l-1.13 2.257a11.042 11.042 0 01-5.516-5.517l2.257-1.128a1 1 0 00.502-1.21L9.228 3.683A1 1 0 008.279 3H5z" />
            </svg>
          </button>
        <% else %>
          <button
            phx-click="join_call"
            phx-target={@target}
            class="px-8 py-4 rounded-full bg-green-600 hover:bg-green-500 transition-colors text-white font-semibold flex items-center gap-2"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            Join Call
          </button>
        <% end %>

        <button
          phx-click="toggle_call_panel"
          phx-target={@target}
          class="p-4 rounded-full bg-gray-700 hover:bg-gray-600 transition-colors"
        >
          <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
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
end
