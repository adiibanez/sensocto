defmodule SensoctoWeb.Live.Components.Object3DPlayerComponent do
  @moduledoc """
  LiveComponent for synchronized 3D object viewing with Gaussian splats.
  Handles viewer controls, playlist management, and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component

  alias Sensocto.Object3D
  alias Sensocto.Object3D.Object3DPlayerServer
  alias Sensocto.Object3D.Object3DPlayerSupervisor

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:current_item, nil)
     |> assign(:playlist_items, [])
     |> assign(:controller_user_id, nil)
     |> assign(:controller_user_name, nil)
     |> assign(:camera_position, %{x: 0, y: 0, z: 5})
     |> assign(:camera_target, %{x: 0, y: 0, z: 0})
     |> assign(:show_playlist, true)
     |> assign(:add_object_url, "")
     |> assign(:add_object_error, nil)
     |> assign(:collapsed, false)
     |> assign(:loading, false)}
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
    user_name = user.email || "Unknown"
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
    room_id = socket.assigns.room_id

    if user && controller_user_id && user.id != controller_user_id do
      requester_name = user.email || "Someone"

      # Broadcast the control request to the room - the controller will see it as a flash
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "object3d:#{room_id}",
        {:control_requested, %{requester_id: user.id, requester_name: requester_name}}
      )

      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(
         :info,
         "Request sent to #{socket.assigns.controller_user_name}"
       )}
    else
      {:noreply, socket}
    end
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
    user_id = get_user_id(socket)

    # Only sync if we're the controller
    if can_control?(socket.assigns.controller_user_id, socket.assigns.current_user) do
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
              3D Object Viewer
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

            <%!-- Navigation Controls --%>
            <div class="flex items-center justify-center gap-4 mb-3">
              <button
                phx-click="previous"
                phx-target={@myself}
                class="p-2 rounded-full bg-gray-700 hover:bg-gray-600 text-white transition-colors"
                title="Previous"
              >
                <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" />
                </svg>
              </button>
              <button
                phx-click="next"
                phx-target={@myself}
                class="p-2 rounded-full bg-gray-700 hover:bg-gray-600 text-white transition-colors"
                title="Next"
              >
                <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" />
                </svg>
              </button>
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
                  <button
                    phx-click="request_control"
                    phx-target={@myself}
                    class="px-3 py-1 text-xs bg-amber-600 hover:bg-amber-500 text-white rounded transition-colors flex items-center gap-1"
                    title="Send a polite request to the current controller"
                  >
                    <Heroicons.icon name="hand-raised" type="outline" class="w-3.5 h-3.5" /> Request
                  </button>
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

          <%!-- Add Object Input --%>
          <form phx-submit="add_object" phx-target={@myself} class="mb-3">
            <div class="flex gap-2">
              <input
                type="text"
                name="url"
                value={@add_object_url}
                phx-change="update_add_url"
                phx-target={@myself}
                placeholder="Paste 3D object URL (.ply, .splat)..."
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
    </div>
    """
  end

  defp can_control?(nil, _current_user), do: true
  defp can_control?(_controller_id, nil), do: false
  defp can_control?(controller_id, %{id: user_id}), do: controller_id == user_id
end
