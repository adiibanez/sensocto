defmodule SensoctoWeb.Live.Calls.MiniCallIndicatorComponent do
  @moduledoc """
  Floating mini call indicator that persists across lobby/room modes.
  Shows call status, participant count, and quick controls without requiring
  the user to switch to the call tab.

  States:
  - Minimized: small pill showing participant count and speaking indicator
  - Expanded: mini video grid with controls
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:expanded, false)
     |> assign(:audio_enabled, true)
     |> assign(:video_enabled, true)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:in_call, assigns[:in_call] || false)
      |> assign(:participants, assigns[:participants] || %{})
      |> assign(:user, assigns.user)
      |> assign(:speaking, assigns[:speaking] || false)
      |> assign_new(:expanded, fn -> false end)
      |> assign_new(:audio_enabled, fn -> true end)
      |> assign_new(:video_enabled, fn -> true end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_expand", _, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  @impl true
  def handle_event("collapse", _, socket) do
    {:noreply, assign(socket, :expanded, false)}
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
      id="mini-call-indicator"
      class="fixed bottom-[200px] md:bottom-24 right-4 z-50"
      phx-hook="MiniCallIndicator"
    >
      <%= if @expanded do %>
        <.expanded_view
          participants={@participants}
          user={@user}
          audio_enabled={@audio_enabled}
          video_enabled={@video_enabled}
          speaking={@speaking}
          target={@myself}
        />
      <% else %>
        <.minimized_pill
          participants={@participants}
          speaking={@speaking}
          target={@myself}
        />
      <% end %>
    </div>
    """
  end

  defp minimized_pill(assigns) do
    participant_count = map_size(assigns.participants) + 1

    assigns = assign(assigns, :participant_count, participant_count)

    ~H"""
    <button
      phx-click="toggle_expand"
      phx-target={@target}
      class={"flex items-center gap-2 px-3 py-2 rounded-full shadow-lg transition-all hover:scale-105 " <>
        if(@speaking, do: "bg-green-600 ring-2 ring-green-400", else: "bg-gray-800 border border-gray-700")}
    >
      <%!-- Call icon --%>
      <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>

      <%!-- Participant count --%>
      <span class="text-white text-sm font-medium">
        {@participant_count}
      </span>

      <%!-- Speaking indicator --%>
      <%= if @speaking do %>
        <span class="flex h-3 w-3">
          <span class="animate-ping absolute inline-flex h-3 w-3 rounded-full bg-green-400 opacity-75">
          </span>
          <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
        </span>
      <% end %>

      <%!-- Expand icon --%>
      <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M5 15l7-7 7 7"
        />
      </svg>
    </button>
    """
  end

  defp expanded_view(assigns) do
    participant_count = map_size(assigns.participants) + 1
    assigns = assign(assigns, :participant_count, participant_count)

    ~H"""
    <div class="bg-gray-800 rounded-lg shadow-xl border border-gray-700 w-72 overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
        <div class="flex items-center gap-2">
          <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
          <span class="text-sm text-green-400">In Call</span>
          <span class="text-xs text-gray-500">({@participant_count})</span>
        </div>
        <button
          phx-click="collapse"
          phx-target={@target}
          class="p-1 hover:bg-gray-700 rounded"
        >
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 9l-7 7-7-7"
            />
          </svg>
        </button>
      </div>

      <%!-- Mini video grid (shows up to 4 participants) --%>
      <div class="p-2">
        <div class="grid grid-cols-2 gap-1">
          <%!-- Local video tile --%>
          <div
            id="mini-local-video"
            class="relative bg-gray-900 rounded aspect-video overflow-hidden"
          >
            <video autoplay playsinline muted class="w-full h-full object-cover"></video>
            <div class="absolute bottom-1 left-1 text-xs text-white bg-black/50 px-1 rounded">
              You
            </div>
            <%= if !@video_enabled do %>
              <div class="absolute inset-0 flex items-center justify-center bg-gray-800">
                <div class="w-8 h-8 rounded-full bg-gray-700 flex items-center justify-center">
                  <span class="text-sm text-gray-400">
                    {(Map.get(@user, :email) || Map.get(@user, :display_name) || "G")
                    |> to_string()
                    |> String.first()
                    |> String.upcase()}
                  </span>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Remote participants (up to 3) --%>
          <%= for {{peer_id, participant}, idx} <- Enum.with_index(Enum.take(@participants, 3)) do %>
            <div
              id={"mini-participant-#{peer_id}"}
              class={"relative bg-gray-900 rounded aspect-video overflow-hidden " <>
                if(idx >= 3, do: "hidden", else: "")}
            >
              <video autoplay playsinline class="w-full h-full object-cover"></video>
              <div class="absolute bottom-1 left-1 text-xs text-white bg-black/50 px-1 rounded truncate max-w-[90%]">
                {get_participant_name(participant)}
              </div>
            </div>
          <% end %>

          <%!-- Overflow indicator --%>
          <%= if map_size(@participants) > 3 do %>
            <div class="relative bg-gray-900 rounded aspect-video overflow-hidden flex items-center justify-center">
              <span class="text-gray-400 text-sm">+{map_size(@participants) - 3}</span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Controls --%>
      <div class="px-3 py-2 bg-gray-900/50 border-t border-gray-700">
        <div class="flex items-center justify-center gap-2">
          <button
            phx-click="toggle_audio"
            phx-target={@target}
            class={"p-2 rounded-full transition-colors " <>
              if(@audio_enabled, do: "bg-gray-700 hover:bg-gray-600", else: "bg-red-600 hover:bg-red-500")}
            title={if @audio_enabled, do: "Mute", else: "Unmute"}
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
            title={if @video_enabled, do: "Camera off", else: "Camera on"}
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
    </div>
    """
  end

  defp get_participant_name(nil), do: "Participant"

  defp get_participant_name(participant) do
    case participant do
      %{user_info: %{name: name}} when is_binary(name) -> name
      %{metadata: %{displayName: name}} when is_binary(name) -> name
      %{user_id: user_id} -> "User #{String.slice(user_id, 0..4)}"
      _ -> "Participant"
    end
  end
end
