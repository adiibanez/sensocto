defmodule SensoctoWeb.Live.Components.MediaPlayerComponent do
  @moduledoc """
  LiveComponent for synchronized YouTube playback.
  Handles player controls, playlist management, and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component

  alias Sensocto.Media
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Media.MediaPlayerSupervisor

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:player_state, :stopped)
     |> assign(:position_seconds, 0.0)
     |> assign(:current_item, nil)
     |> assign(:playlist_items, [])
     |> assign(:controller_user_id, nil)
     |> assign(:controller_user_name, nil)
     |> assign(:show_playlist, true)
     |> assign(:add_video_url, "")
     |> assign(:add_video_error, nil)
     |> assign(:collapsed, false)}
  end

  @impl true
  def update(assigns, socket) do
    # Check if this is the first update (no room_id set yet)
    is_first_update = is_nil(socket.assigns[:room_id])

    # Get room_id - either explicit or :lobby
    room_id = assigns[:room_id] || socket.assigns[:room_id] || (if assigns[:is_lobby], do: :lobby, else: nil)

    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:is_lobby, assigns[:is_lobby] || socket.assigns[:is_lobby] || false)
      |> assign(:current_user, assigns[:current_user] || socket.assigns[:current_user])
      |> assign(:can_manage, assigns[:can_manage] || socket.assigns[:can_manage] || false)

    # Handle incremental updates from send_update (PubSub events)
    # These override the current state with the new values
    socket =
      socket
      |> maybe_assign(assigns, :player_state)
      |> maybe_assign(assigns, :position_seconds)
      |> maybe_assign(assigns, :current_item)
      |> maybe_assign(assigns, :playlist_items)
      |> maybe_assign(assigns, :controller_user_id)
      |> maybe_assign(assigns, :controller_user_name)

    # On first update, load initial state from server
    socket =
      if is_first_update and room_id do
        ensure_player_started(socket, room_id)
      else
        socket
      end

    # Note: push_event calls are handled by the parent LiveView's handle_info
    # because push_event in LiveComponent's update/2 doesn't reach the JS hook properly

    {:ok, socket}
  end

  defp maybe_assign(socket, assigns, key) do
    if Map.has_key?(assigns, key) do
      assign(socket, key, assigns[key])
    else
      socket
    end
  end

  defp ensure_player_started(socket, room_id) do
    opts = if room_id == :lobby, do: [is_lobby: true], else: []

    case MediaPlayerSupervisor.get_or_start_player(room_id, opts) do
      {:ok, _pid} ->
        case MediaPlayerServer.get_state(room_id) do
          {:ok, state} ->
            socket
            |> assign(:player_state, state.state)
            |> assign(:position_seconds, state.position_seconds)
            |> assign(:current_item, state.current_item)
            |> assign(:playlist_items, state.playlist_items)
            |> assign(:controller_user_id, state.controller_user_id)
            |> assign(:controller_user_name, state.controller_user_name)

          {:error, _} ->
            socket
        end

      {:error, _} ->
        socket
    end
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_collapsed", _, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  @impl true
  def handle_event("toggle_playlist", _, socket) do
    {:noreply, assign(socket, :show_playlist, !socket.assigns.show_playlist)}
  end

  @impl true
  def handle_event("play", _, socket) do
    user_id = get_user_id(socket)
    MediaPlayerServer.play(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("pause", _, socket) do
    user_id = get_user_id(socket)
    MediaPlayerServer.pause(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("seek", %{"position" => position}, socket) do
    user_id = get_user_id(socket)
    position = String.to_float(position)
    MediaPlayerServer.seek(socket.assigns.room_id, position, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("next", _, socket) do
    user_id = get_user_id(socket)
    MediaPlayerServer.next(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("previous", _, socket) do
    user_id = get_user_id(socket)
    MediaPlayerServer.previous(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("play_item", %{"item-id" => item_id}, socket) do
    user_id = get_user_id(socket)
    MediaPlayerServer.play_item(socket.assigns.room_id, item_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_item", %{"item-id" => item_id}, socket) do
    Media.remove_from_playlist(item_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("take_control", _, socket) do
    user = socket.assigns.current_user
    user_name = user.email || user.name || "Unknown"
    MediaPlayerServer.take_control(socket.assigns.room_id, user.id, user_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("release_control", _, socket) do
    user = socket.assigns.current_user
    MediaPlayerServer.release_control(socket.assigns.room_id, user.id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_add_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :add_video_url, url)}
  end

  @impl true
  def handle_event("add_video", %{"url" => url}, socket) do
    # Get or create playlist based on context
    playlist = get_or_create_playlist(socket)

    if playlist do
      user_id = socket.assigns.current_user && socket.assigns.current_user.id

      case Media.add_to_playlist(playlist.id, url, user_id) do
        {:ok, _item} ->
          {:noreply,
           socket
           |> assign(:add_video_url, "")
           |> assign(:add_video_error, nil)}

        {:error, :invalid_youtube_url} ->
          {:noreply, assign(socket, :add_video_error, "Invalid YouTube URL")}

        {:error, :video_not_found} ->
          {:noreply, assign(socket, :add_video_error, "Video not found")}

        {:error, _} ->
          # Try minimal add as fallback
          case Media.add_to_playlist_minimal(playlist.id, url, user_id) do
            {:ok, _item} ->
              {:noreply,
               socket
               |> assign(:add_video_url, "")
               |> assign(:add_video_error, nil)}

            {:error, _} ->
              {:noreply, assign(socket, :add_video_error, "Failed to add video")}
          end
      end
    else
      {:noreply, assign(socket, :add_video_error, "Playlist not found")}
    end
  end

  @impl true
  def handle_event("video_ended", _, socket) do
    MediaPlayerServer.video_ended(socket.assigns.room_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("report_duration", %{"duration" => duration}, socket) do
    MediaPlayerServer.update_duration(socket.assigns.room_id, round(duration))
    {:noreply, socket}
  end

  defp get_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end

  defp can_control?(assigns) do
    # Anyone can control if there's no controller assigned
    # Otherwise, only the current controller can control
    case assigns do
      %{controller_user_id: nil} -> true
      %{controller_user_id: controller_id, current_user: %{id: user_id}} -> controller_id == user_id
      _ -> false
    end
  end

  defp get_playlist_id(socket) do
    case socket.assigns do
      %{current_item: %{playlist_id: id}} when not is_nil(id) -> id
      %{playlist_items: [%{playlist_id: id} | _]} -> id
      _ -> nil
    end
  end

  defp get_or_create_playlist(socket) do
    # First try to get from current state
    case get_playlist_id(socket) do
      nil ->
        # No existing playlist, create one based on context
        if socket.assigns.is_lobby do
          case Media.get_or_create_lobby_playlist() do
            {:ok, playlist} -> playlist
            _ -> nil
          end
        else
          room_id = socket.assigns.room_id
          if room_id && room_id != :lobby do
            case Media.get_or_create_room_playlist(room_id) do
              {:ok, playlist} -> playlist
              _ -> nil
            end
          else
            nil
          end
        end

      playlist_id ->
        Media.get_playlist(playlist_id)
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"media-player-#{@room_id}"}
      phx-hook="MediaPlayerHook"
      data-room-id={@room_id}
      data-player-state={@player_state}
      data-position={@position_seconds}
      class="bg-gray-800 rounded-lg overflow-hidden"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
        <div class="flex items-center gap-2">
          <svg class="w-4 h-4 text-red-500" fill="currentColor" viewBox="0 0 24 24">
            <path d="M19.615 3.184c-3.604-.246-11.631-.245-15.23 0-3.897.266-4.356 2.62-4.385 8.816.029 6.185.484 8.549 4.385 8.816 3.6.245 11.626.246 15.23 0 3.897-.266 4.356-2.62 4.385-8.816-.029-6.185-.484-8.549-4.385-8.816zm-10.615 12.816v-8l8 3.993-8 4.007z"/>
          </svg>
          <span class="text-sm text-gray-300">
            <%= if @is_lobby, do: "Lobby Music", else: "Room Music" %>
          </span>
          <%= if @player_state == :playing do %>
            <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
          <% end %>
        </div>
        <button
          phx-click="toggle_collapsed"
          phx-target={@myself}
          class="p-1 rounded hover:bg-gray-700 transition-colors text-gray-400 hover:text-white"
        >
          <svg class={"w-4 h-4 transition-transform #{if @collapsed, do: "rotate-180"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      <%= unless @collapsed do %>
        <%!-- YouTube Player Container --%>
        <div class="relative aspect-video bg-black">
          <%= if @current_item do %>
            <div
              id={"youtube-player-#{@room_id}"}
              data-video-id={@current_item.youtube_video_id}
              data-autoplay={if @player_state == :playing, do: "1", else: "0"}
              data-start={round(@position_seconds)}
              class="w-full h-full"
            >
            </div>
          <% else %>
            <div class="absolute inset-0 flex flex-col items-center justify-center text-gray-500">
              <svg class="w-12 h-12 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <p class="text-sm">Add a video to get started</p>
            </div>
          <% end %>
        </div>

        <%!-- Controls --%>
        <div class="p-3 border-t border-gray-700">
          <%!-- Now Playing Info --%>
          <%= if @current_item do %>
            <div class="mb-3">
              <p class="text-sm text-white font-medium truncate" title={@current_item.title}>
                <%= @current_item.title || "Unknown Title" %>
              </p>
              <p class="text-xs text-gray-400">
                <%= if @current_item.duration_seconds do %>
                  <%= format_duration(@current_item.duration_seconds) %>
                <% end %>
              </p>
            </div>
          <% end %>

          <%!-- Playback Controls --%>
          <% user_can_control = can_control?(assigns) %>
          <div class="flex items-center justify-center gap-4 mb-3">
            <button
              phx-click="previous"
              phx-target={@myself}
              disabled={not user_can_control}
              class={"p-2 rounded-full transition-colors #{if user_can_control, do: "hover:bg-gray-700 text-gray-400 hover:text-white cursor-pointer", else: "text-gray-600 cursor-not-allowed"}"}
              title={if user_can_control, do: "Previous", else: "Only controller can use controls"}
            >
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/>
              </svg>
            </button>

            <%= if @player_state == :playing do %>
              <button
                phx-click="pause"
                phx-target={@myself}
                disabled={not user_can_control}
                class={"p-3 rounded-full transition-colors #{if user_can_control, do: "bg-white hover:bg-gray-200 text-gray-900 cursor-pointer", else: "bg-gray-600 text-gray-400 cursor-not-allowed"}"}
                title={if user_can_control, do: "Pause", else: "Only controller can use controls"}
              >
                <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z"/>
                </svg>
              </button>
            <% else %>
              <button
                phx-click="play"
                phx-target={@myself}
                disabled={not user_can_control}
                class={"p-3 rounded-full transition-colors #{if user_can_control, do: "bg-white hover:bg-gray-200 text-gray-900 cursor-pointer", else: "bg-gray-600 text-gray-400 cursor-not-allowed"}"}
                title={if user_can_control, do: "Play", else: "Only controller can use controls"}
              >
                <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z"/>
                </svg>
              </button>
            <% end %>

            <button
              phx-click="next"
              phx-target={@myself}
              disabled={not user_can_control}
              class={"p-2 rounded-full transition-colors #{if user_can_control, do: "hover:bg-gray-700 text-gray-400 hover:text-white cursor-pointer", else: "text-gray-600 cursor-not-allowed"}"}
              title={if user_can_control, do: "Next", else: "Only controller can use controls"}
            >
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/>
              </svg>
            </button>
          </div>

          <%!-- Controller Info --%>
          <div class="flex items-center justify-between text-xs text-gray-400 mb-3">
            <%= if @controller_user_name do %>
              <span>Controlled by: <%= @controller_user_name %></span>
              <%= if @current_user && @controller_user_id == @current_user.id do %>
                <button
                  phx-click="release_control"
                  phx-target={@myself}
                  class="text-blue-400 hover:text-blue-300"
                >
                  Release
                </button>
              <% end %>
            <% else %>
              <span>No controller</span>
              <%= if @current_user do %>
                <button
                  phx-click="take_control"
                  phx-target={@myself}
                  class="text-blue-400 hover:text-blue-300"
                >
                  Take Control
                </button>
              <% end %>
            <% end %>
          </div>

          <%!-- Add Video Input --%>
          <form phx-submit="add_video" phx-target={@myself} class="mb-3">
            <div class="flex gap-2">
              <input
                type="text"
                name="url"
                value={@add_video_url}
                phx-change="update_add_url"
                phx-target={@myself}
                placeholder="Paste YouTube URL..."
                class="flex-1 bg-gray-700 border border-gray-600 text-white text-sm rounded px-3 py-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <button
                type="submit"
                class="px-4 py-2 bg-red-600 hover:bg-red-500 text-white text-sm rounded transition-colors"
              >
                Add
              </button>
            </div>
            <%= if @add_video_error do %>
              <p class="text-red-400 text-xs mt-1"><%= @add_video_error %></p>
            <% end %>
          </form>

          <%!-- Playlist Toggle --%>
          <button
            phx-click="toggle_playlist"
            phx-target={@myself}
            class="w-full flex items-center justify-between text-sm text-gray-400 hover:text-white py-2"
          >
            <span>Playlist (<%= length(@playlist_items) %>)</span>
            <svg class={"w-4 h-4 transition-transform #{if @show_playlist, do: "rotate-180"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          <%!-- Playlist Items --%>
          <%= if @show_playlist do %>
            <div class="max-h-60 overflow-y-auto space-y-1">
              <%= if Enum.empty?(@playlist_items) do %>
                <p class="text-gray-500 text-sm text-center py-4">No videos in playlist</p>
              <% else %>
                <%= for item <- @playlist_items do %>
                  <div
                    class={"flex items-center gap-2 p-2 rounded group #{if @current_item && @current_item.id == item.id, do: "bg-gray-700 border-l-2 border-red-500", else: ""} #{if user_can_control, do: "hover:bg-gray-700 cursor-pointer", else: "cursor-default"}"}
                    phx-click={if user_can_control, do: "play_item"}
                    phx-value-item-id={item.id}
                    phx-target={@myself}
                  >
                    <img
                      src={item.thumbnail_url || "https://via.placeholder.com/120x68?text=Video"}
                      alt=""
                      class="w-16 h-9 object-cover rounded flex-shrink-0"
                    />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm text-white truncate"><%= item.title || "Unknown" %></p>
                      <p class="text-xs text-gray-400">
                        <%= if item.duration_seconds, do: format_duration(item.duration_seconds), else: "" %>
                      </p>
                    </div>
                    <button
                      phx-click="remove_item"
                      phx-value-item-id={item.id}
                      phx-target={@myself}
                      class="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-gray-600 text-gray-400 hover:text-red-400 transition-all"
                      title="Remove"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_duration(nil), do: ""

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_duration(_), do: ""
end
