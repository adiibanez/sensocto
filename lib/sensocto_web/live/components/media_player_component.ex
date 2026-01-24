defmodule SensoctoWeb.Live.Components.MediaPlayerComponent do
  @moduledoc """
  LiveComponent for synchronized YouTube playback.
  Handles player controls, playlist management, and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component
  require Logger

  alias Sensocto.Media
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Media.MediaPlayerSupervisor
  alias Sensocto.Accounts.UserPreferences

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:player_state, :stopped)
     |> assign(:position_seconds, 0.0)
     |> assign(:current_position, 0.0)
     |> assign(:current_item, nil)
     |> assign(:playlist_items, [])
     |> assign(:controller_user_id, nil)
     |> assign(:controller_user_name, nil)
     |> assign(:show_playlist, true)
     |> assign(:add_video_url, "")
     |> assign(:add_video_error, nil)
     |> assign(:collapsed, false)
     |> assign(:pending_request_user_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Check if this is the first update (no room_id set yet)
    is_first_update = is_nil(socket.assigns[:room_id])

    # Get room_id - either explicit or :lobby
    room_id =
      assigns[:room_id] || socket.assigns[:room_id] ||
        if assigns[:is_lobby], do: :lobby, else: nil

    # Track old state/position before updating
    old_state = socket.assigns[:player_state]
    old_position = socket.assigns[:position_seconds]

    # Get initial_collapsed prop (used as fallback when no saved preference)
    initial_collapsed = assigns[:initial_collapsed] || socket.assigns[:initial_collapsed] || false

    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:is_lobby, assigns[:is_lobby] || socket.assigns[:is_lobby] || false)
      |> assign(:current_user, assigns[:current_user] || socket.assigns[:current_user])
      |> assign(:can_manage, assigns[:can_manage] || socket.assigns[:can_manage] || false)
      |> assign(:initial_collapsed, initial_collapsed)

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
      |> maybe_assign(assigns, :pending_request_user_id)

    # On first update, load initial state from server and user preferences
    socket =
      if is_first_update and room_id do
        socket = ensure_player_started(socket, room_id)

        # Load saved collapsed state from user preferences (fallback to initial_collapsed prop)
        if user = socket.assigns[:current_user] do
          room_key = if socket.assigns.is_lobby, do: "lobby", else: room_id
          default_collapsed = socket.assigns[:initial_collapsed] || false

          saved_collapsed =
            UserPreferences.get_ui_state(
              user.id,
              "media_player_collapsed_#{room_key}",
              default_collapsed
            )

          assign(socket, :collapsed, saved_collapsed)
        else
          # No user - use initial_collapsed prop
          assign(socket, :collapsed, socket.assigns[:initial_collapsed] || false)
        end
      else
        socket
      end

    # Push sync event to JS hook when state or position changes significantly
    # This is critical for multi-tab synchronization
    new_state = socket.assigns[:player_state]
    new_position = socket.assigns[:position_seconds]

    socket =
      if !is_first_update and
           (new_state != old_state or abs((new_position || 0) - (old_position || 0)) > 0.5) do
        push_event(socket, "media_sync", %{
          state: new_state,
          position_seconds: new_position
        })
      else
        socket
      end

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
    new_collapsed = !socket.assigns.collapsed

    # Persist collapsed state to database if user is logged in
    if user = socket.assigns[:current_user] do
      room_key = if socket.assigns.is_lobby, do: "lobby", else: socket.assigns.room_id
      UserPreferences.set_ui_state(user.id, "media_player_collapsed_#{room_key}", new_collapsed)
    end

    {:noreply, assign(socket, :collapsed, new_collapsed)}
  end

  @impl true
  def handle_event("toggle_playlist", _, socket) do
    {:noreply, assign(socket, :show_playlist, !socket.assigns.show_playlist)}
  end

  @impl true
  def handle_event("play", _, socket) do
    socket = maybe_auto_claim_control(socket)
    user_id = get_user_id(socket)
    MediaPlayerServer.play(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("pause", _, socket) do
    socket = maybe_auto_claim_control(socket)
    user_id = get_user_id(socket)
    MediaPlayerServer.pause(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("client_seek", %{"position" => position}, socket) do
    # User seeked in YouTube player - auto-claim control if no one has it
    socket = maybe_auto_claim_control(socket)
    user_id = get_user_id(socket)

    if can_control?(socket.assigns.controller_user_id, socket.assigns.current_user) do
      MediaPlayerServer.seek(socket.assigns.room_id, position, user_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("next", _, socket) do
    socket = maybe_auto_claim_control(socket)
    user_id = get_user_id(socket)
    MediaPlayerServer.next(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("previous", _, socket) do
    socket = maybe_auto_claim_control(socket)
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
  def handle_event("reorder_playlist", %{"item_ids" => item_ids}, socket) do
    playlist_id = get_playlist_id(socket)

    if playlist_id do
      Media.reorder_playlist(playlist_id, item_ids)
    end

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
  def handle_event("request_control", _, socket) do
    user = socket.assigns.current_user
    controller_user_id = socket.assigns.controller_user_id
    room_id = socket.assigns.room_id

    if user && controller_user_id && to_string(user.id) != to_string(controller_user_id) do
      requester_name = to_string(user.email || "Someone")

      # Use server-managed request with 30-second timeout
      case MediaPlayerServer.request_control(room_id, user.id, requester_name) do
        {:ok, :control_granted} ->
          {:noreply,
           socket
           |> assign(:pending_request_user_id, nil)
           |> Phoenix.LiveView.put_flash(:info, "You now have control")}

        {:ok, :request_pending} ->
          {:noreply,
           socket
           |> assign(:pending_request_user_id, user.id)}

        {:ok, :already_controller} ->
          {:noreply, socket}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_request", _, socket) do
    user = socket.assigns.current_user
    room_id = socket.assigns.room_id

    if user && socket.assigns.pending_request_user_id &&
         to_string(socket.assigns.pending_request_user_id) == to_string(user.id) do
      # Cancel via server
      MediaPlayerServer.cancel_request(room_id, user.id)
      {:noreply, assign(socket, :pending_request_user_id, nil)}
    else
      {:noreply, socket}
    end
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

  @impl true
  def handle_event("position_update", %{"position" => position}, socket) do
    # Update current position for progress bar display
    {:noreply, assign(socket, :current_position, position)}
  end

  @impl true
  def handle_event("seek_to_position", %{"position" => position_str}, socket) do
    # Controller clicked on progress bar to seek
    user_id = get_user_id(socket)

    if can_control?(socket.assigns.controller_user_id, socket.assigns.current_user) do
      position = String.to_float(position_str)
      MediaPlayerServer.seek(socket.assigns.room_id, position, user_id)
      # Push event to JS hook to seek immediately
      socket = push_event(socket, "seek_to", %{position: position})
      {:noreply, assign(socket, :current_position, position)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("request_media_sync", _params, socket) do
    # JS hook requests current state - fetch from server and push to hook
    case MediaPlayerServer.get_state(socket.assigns.room_id) do
      {:ok, state} ->
        Logger.debug(
          "MediaPlayerComponent pushing media_sync: #{state.state} pos=#{state.position_seconds}"
        )

        socket =
          push_event(socket, "media_sync", %{
            state: state.state,
            position_seconds: state.position_seconds
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp get_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end

  # Auto-claim control if no one has it and user interacts with player
  defp maybe_auto_claim_control(socket) do
    controller_id = socket.assigns[:controller_user_id]
    current_user = socket.assigns[:current_user]

    if is_nil(controller_id) && current_user do
      user_name =
        Map.get(current_user, :email) || Map.get(current_user, :display_name) ||
          Map.get(current_user, :name) || "Unknown"

      MediaPlayerServer.take_control(socket.assigns.room_id, current_user.id, user_name)
      assign(socket, :controller_user_id, current_user.id)
    else
      socket
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
      phx-target={@myself}
      data-room-id={@room_id}
      data-player-state={@player_state}
      data-position={@position_seconds}
      data-current-video-id={@current_item && @current_item.youtube_video_id}
      class="bg-gray-800 rounded-lg overflow-hidden"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <svg class="w-4 h-4 text-red-500 flex-shrink-0" fill="currentColor" viewBox="0 0 24 24">
            <path d="M19.615 3.184c-3.604-.246-11.631-.245-15.23 0-3.897.266-4.356 2.62-4.385 8.816.029 6.185.484 8.549 4.385 8.816 3.6.245 11.626.246 15.23 0 3.897-.266 4.356-2.62 4.385-8.816-.029-6.185-.484-8.549-4.385-8.816zm-10.615 12.816v-8l8 3.993-8 4.007z" />
          </svg>
          <%= if @collapsed && @current_item do %>
            <%!-- Collapsed: show thumbnail and title --%>
            <img
              src={@current_item.thumbnail_url || "https://via.placeholder.com/40x24?text=Video"}
              alt=""
              class="w-10 h-6 object-cover rounded flex-shrink-0"
            />
            <span class="text-sm text-white truncate" title={@current_item.title}>
              {@current_item.title || "Unknown"}
            </span>
            <%= if @player_state == :playing do %>
              <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse flex-shrink-0"></span>
            <% end %>
          <% else %>
            <%!-- Expanded: show label and playing indicator --%>
            <span class="text-sm text-gray-300">
              Collab Media Playback
            </span>
            <%= if @player_state == :playing do %>
              <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
            <% end %>
          <% end %>
        </div>
        <div class="flex items-center gap-1 flex-shrink-0">
          <%!-- Copy link button (only show when there's a video) --%>
          <%= if @current_item && @current_item.youtube_video_id do %>
            <button
              id={"copy-link-#{@room_id}"}
              phx-hook="CopyToClipboard"
              data-copy-text={"https://youtube.com/watch?v=#{@current_item.youtube_video_id}"}
              class="p-1 rounded hover:bg-gray-700 transition-colors text-gray-400 hover:text-white group"
              title="Copy YouTube link"
            >
              <svg
                class="w-4 h-4 group-[.copied]:hidden"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"
                />
              </svg>
              <svg
                class="w-4 h-4 hidden group-[.copied]:block text-green-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </button>
          <% end %>
          <button
            phx-click="toggle_collapsed"
            phx-target={@myself}
            class="p-1 rounded hover:bg-gray-700 transition-colors text-gray-400 hover:text-white"
          >
            <svg
              class={"w-4 h-4 transition-transform #{if @collapsed, do: "rotate-180"}"}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </button>
        </div>
      </div>

      <%= unless @collapsed do %>
        <%!-- YouTube Player Container --%>
        <div class="relative aspect-video bg-black">
          <%!-- phx-update="ignore" on outer container to prevent LiveView from touching the iframe --%>
          <div
            id={"youtube-player-container-#{@room_id}"}
            phx-update="ignore"
            class="w-full h-full"
          >
            <div
              id={"youtube-player-wrapper-#{@room_id}"}
              class="w-full h-full"
              data-video-id={@current_item && @current_item.youtube_video_id}
              data-autoplay={if @player_state == :playing, do: "1", else: "0"}
              data-start={round(@position_seconds || 0)}
            >
              <div
                id={"youtube-player-#{@room_id}"}
                class="w-full h-full"
              >
              </div>
            </div>
          </div>
          <%!-- Overlay when no video --%>
          <%= unless @current_item do %>
            <div class="absolute inset-0 flex flex-col items-center justify-center text-gray-500 bg-black z-10">
              <svg class="w-12 h-12 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <p class="text-sm">Add a video to get started</p>
            </div>
          <% end %>
        </div>

        <%!-- Controls --%>
        <div class="p-3 border-t border-gray-700">
          <%!-- Now Playing Info with Duration --%>
          <%= if @current_item do %>
            <div class="mb-3">
              <p class="text-sm text-white font-medium truncate" title={@current_item.title}>
                {@current_item.title || "Unknown Title"}
              </p>

              <%!-- Time Display (no seek bar) --%>
              <% current_pos = @current_position || @position_seconds || 0 %>
              <% duration = @current_item.duration_seconds %>
              <p class="text-xs text-gray-400 mt-1">
                {format_duration(round(current_pos))}{if duration && duration > 0,
                  do: " / #{format_duration(duration)}",
                  else: ""}
              </p>
            </div>
          <% end %>

          <%!-- Controller Info & Take Control --%>
          <div class="mb-3 flex items-center justify-between">
            <%= if @controller_user_id do %>
              <div class="flex items-center gap-2 text-sm">
                <span class="w-2 h-2 bg-green-400 rounded-full"></span>
                <span class="text-gray-300">
                  Controlled by
                  <span class="text-white font-medium">{@controller_user_name || "Someone"}</span>
                </span>
              </div>
              <%= if @current_user && @current_user.id == @controller_user_id do %>
                <button
                  phx-click="release_control"
                  phx-target={@myself}
                  class="px-3 py-1 text-xs bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
                >
                  Release
                </button>
              <% else %>
                <%= if @current_user do %>
                  <%= if @pending_request_user_id && to_string(@pending_request_user_id) == to_string(@current_user.id) do %>
                    <%!-- Show pending request with countdown --%>
                    <div
                      id={"media-request-countdown-#{@room_id}"}
                      phx-hook="CountdownTimer"
                      data-seconds="30"
                      class="flex items-center gap-2"
                    >
                      <span class="px-2 py-1 text-xs bg-amber-700 text-amber-200 rounded flex items-center gap-1">
                        <svg class="w-3 h-3 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        <span class="countdown-display">30</span>s
                      </span>
                      <button
                        phx-click="cancel_request"
                        phx-target={@myself}
                        class="px-2 py-1 text-xs bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
                        title="Cancel request"
                      >
                        Cancel
                      </button>
                    </div>
                  <% else %>
                    <button
                      phx-click="request_control"
                      phx-target={@myself}
                      class="px-3 py-1 text-xs bg-amber-600 hover:bg-amber-500 text-white rounded transition-colors"
                    >
                      Request
                    </button>
                  <% end %>
                <% end %>
              <% end %>
            <% else %>
              <div class="text-sm text-gray-400">No one has control</div>
              <%= if @current_user do %>
                <button
                  phx-click="take_control"
                  phx-target={@myself}
                  class="px-3 py-1 text-xs bg-blue-600 hover:bg-blue-500 text-white rounded transition-colors"
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
              <p class="text-red-400 text-xs mt-1">{@add_video_error}</p>
            <% end %>
          </form>

          <%!-- Playlist Toggle --%>
          <button
            phx-click="toggle_playlist"
            phx-target={@myself}
            class="w-full flex items-center justify-between text-sm text-gray-400 hover:text-white py-2"
          >
            <span>Playlist ({length(@playlist_items)})</span>
            <svg
              class={"w-4 h-4 transition-transform #{if @show_playlist, do: "rotate-180"}"}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </button>

          <%!-- Playlist Items --%>
          <%= if @show_playlist do %>
            <div
              id={"playlist-items-#{@room_id}"}
              phx-hook="SortablePlaylist"
              phx-target={@myself}
              class="max-h-60 overflow-y-auto space-y-1"
            >
              <%= if Enum.empty?(@playlist_items) do %>
                <p class="text-gray-500 text-sm text-center py-4">No videos in playlist</p>
              <% else %>
                <%= for item <- @playlist_items do %>
                  <% is_current = @current_item && @current_item.id == item.id %>
                  <% is_playing = is_current && @player_state == :playing %>
                  <div
                    data-item-id={item.id}
                    class={"flex items-center gap-2 p-2 rounded group transition-all #{if is_current, do: "bg-gray-700/50 border-l-4 border-gray-400", else: "hover:bg-gray-700"}"}
                  >
                    <%!-- Now Playing Indicator or Drag Handle --%>
                    <%= if is_current do %>
                      <div class="p-1 text-gray-300 flex-shrink-0">
                        <%= if is_playing do %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                          </svg>
                        <% else %>
                          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M8 5v14l11-7z" />
                          </svg>
                        <% end %>
                      </div>
                    <% else %>
                      <div class="drag-handle cursor-grab active:cursor-grabbing p-1 text-gray-500 hover:text-gray-300 flex-shrink-0">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M8 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm8-12a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0z" />
                        </svg>
                      </div>
                    <% end %>
                    <div class="relative flex-shrink-0">
                      <img
                        src={item.thumbnail_url || "https://via.placeholder.com/120x68?text=Video"}
                        alt=""
                        class={"w-16 h-9 object-cover rounded cursor-pointer #{if is_current, do: "ring-2 ring-gray-400"}"}
                        phx-click="play_item"
                        phx-value-item-id={item.id}
                        phx-target={@myself}
                      />
                      <%= if is_playing do %>
                        <div class="absolute inset-0 bg-black/40 rounded flex items-center justify-center">
                          <div class="flex gap-0.5">
                            <div
                              class="w-1 h-3 bg-gray-300 rounded-full animate-bounce"
                              style="animation-delay: 0ms"
                            >
                            </div>
                            <div
                              class="w-1 h-3 bg-gray-300 rounded-full animate-bounce"
                              style="animation-delay: 150ms"
                            >
                            </div>
                            <div
                              class="w-1 h-3 bg-gray-300 rounded-full animate-bounce"
                              style="animation-delay: 300ms"
                            >
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                    <div
                      class="flex-1 min-w-0 cursor-pointer"
                      phx-click="play_item"
                      phx-value-item-id={item.id}
                      phx-target={@myself}
                    >
                      <p class={"text-sm truncate #{if is_current, do: "text-gray-100 font-medium", else: "text-white"}"}>
                        {item.title || "Unknown"}
                      </p>
                      <p class={"text-xs #{if is_current, do: "text-gray-400", else: "text-gray-400"}"}>
                        {if item.duration_seconds,
                          do: format_duration(item.duration_seconds),
                          else: ""}
                        <%= if is_current do %>
                          <span class="ml-1">- {if is_playing, do: "Playing", else: "Paused"}</span>
                        <% end %>
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
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
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

  # Check if user can control playback
  # Anyone can control if no controller is set, otherwise only the controller
  defp can_control?(nil, _current_user), do: true
  defp can_control?(_controller_id, nil), do: false
  defp can_control?(controller_id, %{id: user_id}), do: controller_id == user_id
end
