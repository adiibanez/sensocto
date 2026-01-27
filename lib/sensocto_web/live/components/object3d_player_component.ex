defmodule SensoctoWeb.Live.Components.Object3DPlayerComponent do
  @moduledoc """
  LiveComponent for synchronized 3D object viewing with Gaussian splats.
  Handles viewer controls, playlist management, and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component
  require Logger

  alias Sensocto.Object3D
  alias Sensocto.Object3D.Object3DPlayerServer
  alias Sensocto.Object3D.Object3DPlayerSupervisor

  @impl true
  # Timeout for control request countdown display (should match server)
  @control_request_timeout_seconds 30

  def mount(socket) do
    {:ok,
     socket
     |> assign(:current_item, nil)
     |> assign(:playlist_items, [])
     |> assign(:controller_user_id, nil)
     |> assign(:controller_user_name, nil)
     |> assign(:pending_request_user_id, nil)
     |> assign(:pending_request_user_name, nil)
     |> assign(:pending_request_started_at, nil)
     |> assign(:camera_position, %{x: 0, y: 0, z: 5})
     |> assign(:camera_target, %{x: 0, y: 0, z: 0})
     |> assign(:show_playlist, true)
     |> assign(:add_object_url, "")
     |> assign(:add_object_error, nil)
     |> assign(:collapsed, false)
     |> assign(:loading, false)
     |> assign(:sync_mode, :synced)}
  end

  @impl true
  def update(assigns, socket) do
    is_first_update = is_nil(socket.assigns[:room_id])

    room_id =
      assigns[:room_id] || socket.assigns[:room_id] ||
        if(assigns[:is_lobby], do: :lobby, else: nil)

    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:is_lobby, assigns[:is_lobby] || socket.assigns[:is_lobby] || false)
      |> assign(:current_user, assigns[:current_user] || socket.assigns[:current_user])
      |> assign(:can_manage, assigns[:can_manage] || socket.assigns[:can_manage] || false)

    # Handle incremental updates from send_update (PubSub events)
    socket =
      socket
      |> maybe_assign(assigns, :current_item)
      |> maybe_assign(assigns, :playlist_items)
      |> maybe_assign(assigns, :controller_user_id)
      |> maybe_assign(assigns, :controller_user_name)
      |> maybe_assign(assigns, :camera_position)
      |> maybe_assign(assigns, :camera_target)
      |> maybe_assign(assigns, :sync_mode)

    # Track when a pending request starts for countdown display
    socket =
      cond do
        # New pending request - record start time
        Map.has_key?(assigns, :pending_request_user_id) && assigns[:pending_request_user_id] &&
            is_nil(socket.assigns[:pending_request_user_id]) ->
          socket
          |> assign(:pending_request_user_id, assigns[:pending_request_user_id])
          |> maybe_assign(assigns, :pending_request_user_name)
          |> assign(:pending_request_started_at, System.system_time(:second))

        # Request cleared - clear timestamp
        Map.has_key?(assigns, :pending_request_user_id) &&
            is_nil(assigns[:pending_request_user_id]) ->
          socket
          |> assign(:pending_request_user_id, nil)
          |> assign(:pending_request_user_name, nil)
          |> assign(:pending_request_started_at, nil)

        # Request user name update only
        Map.has_key?(assigns, :pending_request_user_name) ->
          maybe_assign(socket, assigns, :pending_request_user_name)

        true ->
          socket
      end

    # On first update, load initial state from server
    socket =
      if is_first_update and room_id do
        ensure_player_started(socket, room_id)
      else
        socket
      end

    # Push sync event to JS hook when item changes
    socket =
      if Map.has_key?(assigns, :current_item) and assigns[:current_item] do
        push_event(socket, "object3d_sync", %{
          current_item: assigns[:current_item],
          camera_position: socket.assigns.camera_position,
          camera_target: socket.assigns.camera_target,
          controller_user_id: socket.assigns.controller_user_id
        })
      else
        socket
      end

    # Push camera sync event when receiving synced camera from controller
    socket =
      if Map.has_key?(assigns, :synced_camera_position) and
           Map.has_key?(assigns, :synced_camera_target) do
        socket
        |> assign(:camera_position, assigns[:synced_camera_position])
        |> assign(:camera_target, assigns[:synced_camera_target])
        |> push_event("object3d_camera_sync", %{
          camera_position: assigns[:synced_camera_position],
          camera_target: assigns[:synced_camera_target]
        })
      else
        socket
      end

    # Push controller change to JS hook so it knows who can sync camera
    socket =
      if Map.has_key?(assigns, :controller_user_id) and not is_first_update do
        push_event(socket, "object3d_controller_changed", %{
          controller_user_id: assigns[:controller_user_id]
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
    require Logger
    opts = if room_id == :lobby, do: [is_lobby: true], else: []

    case Object3DPlayerSupervisor.get_or_start_player(room_id, opts) do
      {:ok, _pid} ->
        case Object3DPlayerServer.get_state(room_id) do
          {:ok, state} ->
            Logger.debug(
              "[Object3DPlayerComponent] Pushing initial sync - controller: #{inspect(state.controller_user_id)}, item: #{inspect(state.current_item && state.current_item.id)}"
            )

            socket
            |> assign(:current_item, state.current_item)
            |> assign(:playlist_items, state.playlist_items)
            |> assign(:controller_user_id, state.controller_user_id)
            |> assign(:controller_user_name, state.controller_user_name)
            |> assign(:camera_position, state.camera_position)
            |> assign(:camera_target, state.camera_target)
            |> push_event("object3d_sync", %{
              current_item: state.current_item,
              camera_position: state.camera_position,
              camera_target: state.camera_target,
              controller_user_id: state.controller_user_id
            })

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
  def handle_event("view_item", %{"item-id" => item_id}, socket) do
    user_id = get_user_id(socket)
    Object3DPlayerServer.view_item(socket.assigns.room_id, item_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("next", _, socket) do
    user_id = get_user_id(socket)
    Object3DPlayerServer.next(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("previous", _, socket) do
    user_id = get_user_id(socket)
    Object3DPlayerServer.previous(socket.assigns.room_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_item", %{"item-id" => item_id}, socket) do
    Object3D.remove_from_playlist(item_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("reorder_playlist", %{"item_ids" => item_ids}, socket) do
    playlist_id = get_playlist_id(socket)

    if playlist_id do
      Object3D.reorder_playlist(playlist_id, item_ids)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("take_control", _, socket) do
    user = socket.assigns.current_user
    user_name = Map.get(user, :email) || Map.get(user, :display_name) || "Unknown"
    Object3DPlayerServer.take_control(socket.assigns.room_id, user.id, user_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("release_control", _, socket) do
    user = socket.assigns.current_user
    Object3DPlayerServer.release_control(socket.assigns.room_id, user.id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("request_control", _, socket) do
    user = socket.assigns.current_user
    controller_user_id = socket.assigns.controller_user_id

    if user && controller_user_id && to_string(user.id) != to_string(controller_user_id) do
      requester_name = Map.get(user, :email) || Map.get(user, :display_name) || "Someone"

      case Object3DPlayerServer.request_control(socket.assigns.room_id, user.id, requester_name) do
        {:ok, :control_granted} ->
          {:noreply,
           socket
           |> Phoenix.LiveView.put_flash(:info, "You now have control")}

        {:ok, :request_pending} ->
          {:noreply,
           socket
           |> Phoenix.LiveView.put_flash(
             :info,
             "Request sent - control transfers in 30s unless #{socket.assigns.controller_user_name} keeps control"
           )}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keep_control", _, socket) do
    user = socket.assigns.current_user

    if user do
      Object3DPlayerServer.keep_control(socket.assigns.room_id, user.id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_request_modal", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_add_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :add_object_url, url)}
  end

  @impl true
  def handle_event("add_object", %{"url" => url}, socket) do
    playlist = get_or_create_playlist(socket)

    if playlist do
      user_id = socket.assigns.current_user && socket.assigns.current_user.id

      case Object3D.add_to_playlist(playlist.id, %{splat_url: url}, user_id) do
        {:ok, _item} ->
          {:noreply,
           socket
           |> assign(:add_object_url, "")
           |> assign(:add_object_error, nil)}

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          {:noreply, assign(socket, :add_object_error, "Invalid URL")}

        {:error, msg} when is_binary(msg) ->
          {:noreply, assign(socket, :add_object_error, msg)}

        {:error, _} ->
          {:noreply, assign(socket, :add_object_error, "Failed to add object")}
      end
    else
      {:noreply, assign(socket, :add_object_error, "Playlist not found")}
    end
  end

  @impl true
  def handle_event("camera_moved", %{"position" => position, "target" => target}, socket) do
    user = socket.assigns.current_user
    user_id = user && user.id
    controller_user_id = socket.assigns.controller_user_id

    # Auto-take control if no one has control and user is logged in
    socket =
      if is_nil(controller_user_id) && user do
        user_name = Map.get(user, :email) || Map.get(user, :display_name) || "Unknown"
        Object3DPlayerServer.take_control(socket.assigns.room_id, user.id, user_name)
        socket
      else
        socket
      end

    # Only sync if we're the controller (or just took control)
    if can_control?(controller_user_id, user) do
      Object3DPlayerServer.sync_camera(
        socket.assigns.room_id,
        position,
        target,
        user_id
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("viewer_ready", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("loading_started", _params, socket) do
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_event("loading_complete", _params, socket) do
    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_event("loading_error", %{"message" => _message}, socket) do
    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_event("request_object3d_sync", _params, socket) do
    case Object3DPlayerServer.get_state(socket.assigns.room_id) do
      {:ok, state} ->
        socket =
          push_event(socket, "object3d_sync", %{
            current_item: state.current_item,
            camera_position: state.camera_position,
            camera_target: state.camera_target,
            controller_user_id: state.controller_user_id
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset_camera", _params, socket) do
    {:noreply, push_event(socket, "object3d_reset_camera", %{})}
  end

  @impl true
  def handle_event("center_object", _params, socket) do
    {:noreply, push_event(socket, "object3d_center_object", %{})}
  end

  defp get_user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
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
    case get_playlist_id(socket) do
      nil ->
        if socket.assigns.is_lobby do
          case Object3D.get_or_create_lobby_playlist() do
            {:ok, playlist} -> playlist
            _ -> nil
          end
        else
          room_id = socket.assigns.room_id

          if room_id && room_id != :lobby do
            case Object3D.get_or_create_room_playlist(room_id) do
              {:ok, playlist} -> playlist
              _ -> nil
            end
          else
            nil
          end
        end

      playlist_id ->
        Object3D.get_playlist(playlist_id)
    end
  end

  # Calculate remaining seconds for control request countdown
  defp countdown_remaining_seconds(pending_request_started_at) do
    if pending_request_started_at do
      elapsed = System.system_time(:second) - pending_request_started_at
      max(0, @control_request_timeout_seconds - elapsed)
    else
      @control_request_timeout_seconds
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"object3d-player-#{@room_id}"}
      phx-hook="Object3DPlayerHook"
      phx-target={@myself}
      data-room-id={@room_id}
      data-current-user-id={@current_user && @current_user.id}
      data-splat-url={@current_item && @current_item.splat_url}
      class="bg-gray-800 rounded-lg overflow-hidden"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <Heroicons.icon
            name="cube-transparent"
            type="solid"
            class="w-4 h-4 text-cyan-500 flex-shrink-0"
          />
          <%= if @collapsed && @current_item do %>
            <span class="text-sm text-white truncate" title={@current_item.name}>
              {@current_item.name || "3D Object"}
            </span>
            <%= if @loading do %>
              <span class="w-2 h-2 bg-cyan-400 rounded-full animate-pulse flex-shrink-0"></span>
            <% end %>
          <% else %>
            <span class="text-sm text-gray-300">
              Collab 3D Object Viewer
            </span>
            <%= if @loading do %>
              <span class="w-2 h-2 bg-cyan-400 rounded-full animate-pulse"></span>
            <% end %>
          <% end %>
        </div>
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
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      <%= unless @collapsed do %>
        <%!-- 3D Viewer Container --%>
        <div class="relative aspect-video bg-black overflow-hidden">
          <div
            id={"object3d-viewer-container-#{@room_id}"}
            phx-update="ignore"
            data-object3d-viewer="true"
            class="absolute inset-0"
            style="z-index: 1;"
          >
          </div>
          <%!-- Overlay when no object - pointer-events-none so it doesn't block canvas --%>
          <%= unless @current_item do %>
            <div class="absolute inset-0 flex flex-col items-center justify-center text-gray-500 bg-black z-10 pointer-events-none">
              <Heroicons.icon name="cube-transparent" type="outline" class="w-12 h-12 mb-2" />
              <p class="text-sm">Add a 3D object to get started</p>
            </div>
          <% end %>
          <%!-- Loading overlay - pointer-events-none so it doesn't block canvas --%>
          <%= if @loading do %>
            <div class="absolute inset-0 flex items-center justify-center bg-black/50 z-20 pointer-events-none">
              <div class="flex flex-col items-center">
                <div class="w-8 h-8 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin">
                </div>
                <span class="text-sm text-white mt-2">Loading...</span>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Controls --%>
        <div class="p-3 border-t border-gray-700">
          <%!-- Camera Controls --%>
          <%= if @current_item do %>
            <div class="flex items-center justify-end gap-2 mb-3">
              <button
                phx-click="center_object"
                phx-target={@myself}
                class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-white rounded transition-colors flex items-center gap-1"
                title="Center camera on object"
              >
                <Heroicons.icon name="viewfinder-circle" type="outline" class="w-3.5 h-3.5" /> Center
              </button>
              <button
                phx-click="reset_camera"
                phx-target={@myself}
                class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-white rounded transition-colors flex items-center gap-1"
                title="Reset camera to default position"
              >
                <Heroicons.icon name="arrow-path" type="outline" class="w-3.5 h-3.5" /> Reset View
              </button>
            </div>
          <% end %>

          <%!-- Now Viewing Info --%>
          <%= if @current_item do %>
            <div class="mb-3">
              <p class="text-sm text-white font-medium truncate" title={@current_item.name}>
                {@current_item.name || "3D Object"}
              </p>
              <%= if @current_item.description do %>
                <p class="text-xs text-gray-400 mt-1 line-clamp-2">{@current_item.description}</p>
              <% end %>
              <%= if @current_item.source_url do %>
                <a
                  href={@current_item.source_url}
                  target="_blank"
                  class="text-xs text-cyan-400 hover:text-cyan-300 mt-1 inline-block"
                >
                  View source
                </a>
              <% end %>
            </div>
          <% end %>

          <%!-- Controller Info & Take Control --%>
          <div class="mb-3">
            <div class="flex items-center justify-between">
              <%= if @controller_user_id do %>
                <div class="flex items-center gap-2 text-sm">
                  <span class="w-2 h-2 bg-green-400 rounded-full"></span>
                  <span class="text-gray-300">
                    Controlled by
                    <span class="text-white font-medium">{@controller_user_name || "Someone"}</span>
                  </span>
                </div>
                <%= if @current_user && @current_user.id == @controller_user_id do %>
                  <%= if @pending_request_user_id do %>
                    <button
                      phx-click="keep_control"
                      phx-target={@myself}
                      class="px-3 py-1 text-xs bg-green-600 hover:bg-green-500 text-white rounded transition-colors animate-pulse"
                    >
                      Keep Control
                    </button>
                  <% else %>
                    <button
                      phx-click="release_control"
                      phx-target={@myself}
                      class="px-3 py-1 text-xs bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
                    >
                      Release
                    </button>
                  <% end %>
                <% else %>
                  <%= if @current_user do %>
                    <%= if @pending_request_user_id && @pending_request_user_id == @current_user.id do %>
                      <span class="px-3 py-1 text-xs bg-amber-700 text-amber-200 rounded flex items-center gap-1">
                        <span>Pending</span>
                        <span
                          id={"countdown-requester-#{@room_id}"}
                          phx-hook="CountdownTimer"
                          data-seconds={countdown_remaining_seconds(@pending_request_started_at)}
                          class="font-mono font-bold tabular-nums"
                        >
                          {countdown_remaining_seconds(@pending_request_started_at)}s
                        </span>
                      </span>
                    <% else %>
                      <button
                        phx-click="request_control"
                        phx-target={@myself}
                        class="px-3 py-1 text-xs bg-amber-600 hover:bg-amber-500 text-white rounded transition-colors flex items-center gap-1"
                        title="Send a polite request to the current controller"
                      >
                        <Heroicons.icon name="hand-raised" type="outline" class="w-3.5 h-3.5" />
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
                    class="px-3 py-1 text-xs bg-cyan-600 hover:bg-cyan-500 text-white rounded transition-colors"
                  >
                    Take Control
                  </button>
                <% end %>
              <% end %>
            </div>
            <%!-- Pending Request Alert for Controller --%>
            <%= if @pending_request_user_id && @current_user && @current_user.id == @controller_user_id do %>
              <div class="mt-2 px-3 py-2 bg-amber-900/50 border border-amber-600 rounded text-xs text-amber-200 flex items-center gap-2">
                <Heroicons.icon
                  name="hand-raised"
                  type="solid"
                  class="w-4 h-4 text-amber-400 flex-shrink-0"
                />
                <span class="flex-1">
                  <span class="font-medium">{@pending_request_user_name || "Someone"}</span>
                  is requesting control
                </span>
                <span
                  id={"countdown-controller-#{@room_id}"}
                  phx-hook="CountdownTimer"
                  data-seconds={countdown_remaining_seconds(@pending_request_started_at)}
                  class="font-mono text-amber-300 font-bold tabular-nums"
                >
                  {countdown_remaining_seconds(@pending_request_started_at)}s
                </span>
              </div>
            <% end %>
          </div>

          <%!-- Sync Mode Toggle --%>
          <%= if @current_user do %>
            <div class="mb-3 flex items-center justify-between">
              <div class="flex items-center gap-2 text-sm">
                <%= if @sync_mode == :solo do %>
                  <span class="w-2 h-2 bg-slate-400 rounded-full"></span>
                  <span class="text-slate-400">Exploring Solo</span>
                <% else %>
                  <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                  <span class="text-gray-300">Synced with group</span>
                <% end %>
              </div>
              <button
                phx-click="toggle_sync_mode"
                class={"px-3 py-1 text-xs rounded transition-colors " <>
                  if @sync_mode == :solo,
                    do: "bg-green-600 hover:bg-green-500 text-white",
                    else: "bg-slate-600 hover:bg-slate-500 text-white"}
                title={if @sync_mode == :solo, do: "Join group sync", else: "Explore independently"}
              >
                {if @sync_mode == :solo, do: "Join Sync", else: "Go Solo"}
              </button>
            </div>
          <% end %>

          <%!-- Add Object Input --%>
          <form phx-submit="add_object" phx-target={@myself} class="mb-3">
            <label for="add-object-url" class="sr-only">3D object URL</label>
            <div class="flex gap-2">
              <input
                type="text"
                name="url"
                id="add-object-url"
                value={@add_object_url}
                phx-change="update_add_url"
                phx-target={@myself}
                placeholder="Paste 3D object URL (.ply, .splat)..."
                aria-label="3D object URL"
                class="flex-1 bg-gray-700 border border-gray-600 text-white text-sm rounded px-3 py-2 focus:ring-cyan-500 focus:border-cyan-500"
              />
              <button
                type="submit"
                class="px-4 py-2 bg-cyan-600 hover:bg-cyan-500 text-white text-sm rounded transition-colors"
              >
                Add
              </button>
            </div>
            <%= if @add_object_error do %>
              <p class="text-red-400 text-xs mt-1">{@add_object_error}</p>
            <% end %>
          </form>

          <%!-- Playlist Toggle --%>
          <button
            phx-click="toggle_playlist"
            phx-target={@myself}
            class="w-full flex items-center justify-between text-sm text-gray-400 hover:text-white py-2"
          >
            <span>Objects ({length(@playlist_items)})</span>
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
              id={"object3d-playlist-items-#{@room_id}"}
              phx-hook="SortablePlaylist"
              phx-target={@myself}
              class="max-h-60 overflow-y-auto space-y-1"
            >
              <%= if Enum.empty?(@playlist_items) do %>
                <p class="text-gray-500 text-sm text-center py-4">No 3D objects in playlist</p>
              <% else %>
                <%= for item <- @playlist_items do %>
                  <% is_current = @current_item && @current_item.id == item.id %>
                  <div
                    data-item-id={item.id}
                    class={"flex items-center gap-2 p-2 rounded group transition-all #{if is_current, do: "bg-gray-700/50 border-l-4 border-cyan-400", else: "hover:bg-gray-700"}"}
                  >
                    <%!-- Drag Handle --%>
                    <%= unless is_current do %>
                      <div class="drag-handle cursor-grab active:cursor-grabbing p-1 text-gray-500 hover:text-gray-300 flex-shrink-0">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M8 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm8-12a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0zm0 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0z" />
                        </svg>
                      </div>
                    <% else %>
                      <div class="p-1 text-cyan-400 flex-shrink-0">
                        <Heroicons.icon name="cube-transparent" type="solid" class="w-4 h-4" />
                      </div>
                    <% end %>
                    <%!-- Thumbnail or Icon --%>
                    <div class="relative flex-shrink-0">
                      <%= if item.thumbnail_url do %>
                        <img
                          src={item.thumbnail_url}
                          alt=""
                          class={"w-12 h-12 object-cover rounded cursor-pointer #{if is_current, do: "ring-2 ring-cyan-400"}"}
                          phx-click="view_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                        />
                      <% else %>
                        <div
                          class={"w-12 h-12 bg-gray-700 rounded flex items-center justify-center cursor-pointer #{if is_current, do: "ring-2 ring-cyan-400"}"}
                          phx-click="view_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                        >
                          <Heroicons.icon
                            name="cube-transparent"
                            type="outline"
                            class="w-6 h-6 text-gray-500"
                          />
                        </div>
                      <% end %>
                    </div>
                    <div
                      class="flex-1 min-w-0 cursor-pointer"
                      phx-click="view_item"
                      phx-value-item-id={item.id}
                      phx-target={@myself}
                    >
                      <p class={"text-sm truncate #{if is_current, do: "text-cyan-100 font-medium", else: "text-white"}"}>
                        {item.name || "3D Object"}
                      </p>
                      <%= if item.description do %>
                        <p class="text-xs text-gray-400 truncate">{item.description}</p>
                      <% end %>
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

      <%!-- Control Request Modal - Shows to controller when someone requests control --%>
      <%= if @pending_request_user_id && @current_user && @current_user.id == @controller_user_id do %>
        <%!-- Audio notification when modal appears --%>
        <div
          id={"object3d-request-sound-#{@room_id}"}
          phx-hook="NotificationSound"
          class="hidden"
        >
        </div>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
          phx-click="dismiss_request_modal"
          phx-target={@myself}
        >
          <div
            id={"object3d-control-request-modal-#{@room_id}"}
            phx-hook="CountdownTimer"
            data-seconds="30"
            class="bg-gray-800 rounded-lg p-6 max-w-sm w-full shadow-xl border border-amber-500/50"
            phx-click-away="dismiss_request_modal"
            phx-target={@myself}
          >
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-full bg-amber-500/20 flex items-center justify-center">
                <Heroicons.icon name="hand-raised" type="solid" class="w-5 h-5 text-amber-400" />
              </div>
              <div>
                <h3 class="text-white font-medium">Control Requested</h3>
                <p class="text-amber-300 text-sm">
                  {@pending_request_user_name || "Someone"} wants control
                </p>
              </div>
            </div>

            <p class="text-gray-300 text-sm mb-4">
              Control will transfer in
              <span class="countdown-display font-bold text-amber-400">30</span>
              seconds
              unless you keep it.
            </p>

            <div class="flex gap-3">
              <button
                phx-click="keep_control"
                phx-target={@myself}
                class="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-medium transition-colors"
              >
                Keep Control
              </button>
              <button
                phx-click="release_control"
                phx-target={@myself}
                class="flex-1 px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded-lg font-medium transition-colors"
              >
                Release
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp can_control?(nil, _current_user), do: true
  defp can_control?(_controller_id, nil), do: false
  defp can_control?(controller_id, %{id: user_id}), do: controller_id == user_id
end
