defmodule SensoctoWeb.Live.Components.WhiteboardComponent do
  @moduledoc """
  LiveComponent for collaborative whiteboard drawing.
  Handles canvas controls, stroke synchronization, and coordinates with JavaScript hooks.
  """
  use SensoctoWeb, :live_component
  require Logger

  alias Sensocto.Whiteboard.WhiteboardServer
  alias Sensocto.Whiteboard.WhiteboardSupervisor

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:strokes, [])
     |> assign(:controller_user_id, nil)
     |> assign(:controller_user_name, nil)
     |> assign(:pending_request_user_id, nil)
     |> assign(:pending_request_user_name, nil)
     |> assign(:background_color, "#1a1a1a")
     |> assign(:collapsed, false)
     |> assign(:current_tool, "pen")
     |> assign(:stroke_color, "#22c55e")
     |> assign(:stroke_width, 3)
     |> assign(:show_color_picker, false)}
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
      |> maybe_assign(assigns, :strokes)
      |> maybe_assign(assigns, :controller_user_id)
      |> maybe_assign(assigns, :controller_user_name)
      |> maybe_assign(assigns, :pending_request_user_id)
      |> maybe_assign(assigns, :pending_request_user_name)
      |> maybe_assign(assigns, :background_color)

    # On first update, load initial state from server
    socket =
      if is_first_update and room_id do
        ensure_whiteboard_started(socket, room_id)
      else
        socket
      end

    # Push events to JavaScript hook for real-time sync
    socket =
      cond do
        Map.has_key?(assigns, :new_stroke) and assigns[:new_stroke] ->
          push_event(socket, "whiteboard_stroke_added", %{stroke: assigns[:new_stroke]})

        Map.has_key?(assigns, :undo_stroke) ->
          push_event(socket, "whiteboard_undo", %{removed_stroke: assigns[:undo_stroke]})

        Map.has_key?(assigns, :strokes) and assigns[:strokes] == [] ->
          # Clear was triggered (strokes set to empty list)
          push_event(socket, "whiteboard_cleared", %{})

        true ->
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

  defp ensure_whiteboard_started(socket, room_id) do
    opts = if room_id == :lobby, do: [is_lobby: true], else: []

    case WhiteboardSupervisor.get_or_start_whiteboard(room_id, opts) do
      {:ok, _pid} ->
        case WhiteboardServer.get_state(room_id) do
          {:ok, state} ->
            socket
            |> assign(:strokes, state.strokes)
            |> assign(:background_color, state.background_color)
            |> assign(:controller_user_id, state.controller_user_id)
            |> assign(:controller_user_name, state.controller_user_name)
            |> push_event("whiteboard_sync", %{
              strokes: state.strokes,
              background_color: state.background_color
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
  def handle_event("set_tool", %{"tool" => tool}, socket) do
    {:noreply, assign(socket, :current_tool, tool)}
  end

  @impl true
  def handle_event("set_color", %{"color" => color}, socket) do
    {:noreply,
     socket
     |> assign(:stroke_color, color)
     |> assign(:show_color_picker, false)}
  end

  @impl true
  def handle_event("set_width", %{"width" => width}, socket) do
    width = String.to_integer(width)
    {:noreply, assign(socket, :stroke_width, width)}
  end

  @impl true
  def handle_event("toggle_color_picker", _, socket) do
    {:noreply, assign(socket, :show_color_picker, !socket.assigns.show_color_picker)}
  end

  @impl true
  def handle_event("stroke_complete", %{"stroke" => stroke_data}, socket) do
    user = socket.assigns.current_user
    user_id = user && user.id

    stroke = %{
      type: Map.get(stroke_data, "type", "freehand"),
      points: Map.get(stroke_data, "points", []),
      color: Map.get(stroke_data, "color", socket.assigns.stroke_color),
      width: Map.get(stroke_data, "width", socket.assigns.stroke_width)
    }

    case WhiteboardServer.add_stroke(socket.assigns.room_id, stroke, user_id) do
      {:ok, _stroke} ->
        {:noreply, socket}

      {:error, :not_controller} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Only the controller can draw")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_whiteboard", _, socket) do
    user = socket.assigns.current_user
    user_id = user && user.id

    case WhiteboardServer.clear(socket.assigns.room_id, user_id) do
      :ok ->
        {:noreply, socket}

      {:error, :not_controller} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Only the controller can clear")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("undo", _, socket) do
    user = socket.assigns.current_user
    user_id = user && user.id

    case WhiteboardServer.undo(socket.assigns.room_id, user_id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :not_controller} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Only the controller can undo")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("take_control", _, socket) do
    user = socket.assigns.current_user
    user_name = Map.get(user, :email) || Map.get(user, :display_name) || "Unknown"
    WhiteboardServer.take_control(socket.assigns.room_id, user.id, user_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("release_control", _, socket) do
    user = socket.assigns.current_user
    WhiteboardServer.release_control(socket.assigns.room_id, user.id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("request_control", _, socket) do
    user = socket.assigns.current_user
    controller_user_id = socket.assigns.controller_user_id

    if user && controller_user_id && to_string(user.id) != to_string(controller_user_id) do
      requester_name = Map.get(user, :email) || Map.get(user, :display_name) || "Someone"

      case WhiteboardServer.request_control(socket.assigns.room_id, user.id, requester_name) do
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
      WhiteboardServer.keep_control(socket.assigns.room_id, user.id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_request_modal", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("request_whiteboard_sync", _params, socket) do
    case WhiteboardServer.get_state(socket.assigns.room_id) do
      {:ok, state} ->
        socket =
          push_event(socket, "whiteboard_sync", %{
            strokes: state.strokes,
            background_color: state.background_color
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"whiteboard-#{@room_id}"}
      phx-hook="WhiteboardHook"
      phx-target={@myself}
      data-room-id={@room_id}
      data-current-user-id={@current_user && @current_user.id}
      data-controller-user-id={@controller_user_id}
      data-tool={@current_tool}
      data-color={@stroke_color}
      data-width={@stroke_width}
      class="bg-gray-800 rounded-lg overflow-hidden"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-3 py-2 bg-gray-900/50 border-b border-gray-700">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <Heroicons.icon
            name="pencil-square"
            type="solid"
            class="w-4 h-4 text-green-500 flex-shrink-0"
          />
          <span class="text-sm text-gray-300">
            Collab Whiteboard
          </span>
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
        <%!-- Canvas Container --%>
        <div
          class="relative aspect-video overflow-hidden"
          style={"background-color: #{@background_color};"}
        >
          <canvas
            id={"whiteboard-canvas-#{@room_id}"}
            phx-update="ignore"
            data-whiteboard-canvas="true"
            class="absolute inset-0 w-full h-full"
            style="touch-action: none;"
          >
          </canvas>
        </div>

        <%!-- Tools --%>
        <div class="p-3 border-t border-gray-700">
          <%!-- Tool Selection --%>
          <div class="flex items-center gap-2 mb-3">
            <div class="flex items-center gap-1 bg-gray-700 rounded-lg p-1">
              <button
                phx-click="set_tool"
                phx-value-tool="pen"
                phx-target={@myself}
                class={"p-2 rounded transition-colors " <> if(@current_tool == "pen", do: "bg-green-600 text-white", else: "text-gray-400 hover:text-white")}
                title="Pen"
              >
                <Heroicons.icon name="pencil" type="outline" class="w-4 h-4" />
              </button>
              <button
                phx-click="set_tool"
                phx-value-tool="eraser"
                phx-target={@myself}
                class={"p-2 rounded transition-colors " <> if(@current_tool == "eraser", do: "bg-green-600 text-white", else: "text-gray-400 hover:text-white")}
                title="Eraser"
              >
                <Heroicons.icon name="backspace" type="outline" class="w-4 h-4" />
              </button>
              <button
                phx-click="set_tool"
                phx-value-tool="line"
                phx-target={@myself}
                class={"p-2 rounded transition-colors " <> if(@current_tool == "line", do: "bg-green-600 text-white", else: "text-gray-400 hover:text-white")}
                title="Line"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-width="2" d="M4 20L20 4" />
                </svg>
              </button>
              <button
                phx-click="set_tool"
                phx-value-tool="rect"
                phx-target={@myself}
                class={"p-2 rounded transition-colors " <> if(@current_tool == "rect", do: "bg-green-600 text-white", else: "text-gray-400 hover:text-white")}
                title="Rectangle"
              >
                <Heroicons.icon name="stop" type="outline" class="w-4 h-4" />
              </button>
            </div>

            <%!-- Color Picker --%>
            <div class="relative">
              <button
                phx-click="toggle_color_picker"
                phx-target={@myself}
                class="w-8 h-8 rounded border-2 border-gray-600 hover:border-gray-500"
                style={"background-color: #{@stroke_color};"}
                title="Color"
              >
              </button>
              <%= if @show_color_picker do %>
                <div class="absolute bottom-full left-0 mb-2 p-2 bg-gray-800 rounded-lg border border-gray-600 shadow-lg grid grid-cols-5 gap-1 z-10">
                  <%= for color <- ["#22c55e", "#ef4444", "#3b82f6", "#eab308", "#a855f7", "#f97316", "#06b6d4", "#ec4899", "#ffffff", "#1a1a1a"] do %>
                    <button
                      phx-click="set_color"
                      phx-value-color={color}
                      phx-target={@myself}
                      class={"w-6 h-6 rounded border #{if @stroke_color == color, do: "border-white", else: "border-gray-600"}"}
                      style={"background-color: #{color};"}
                    >
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Stroke Width --%>
            <select
              phx-change="set_width"
              phx-target={@myself}
              name="width"
              class="bg-gray-700 text-white text-sm rounded px-2 py-1 border border-gray-600"
            >
              <option value="1" selected={@stroke_width == 1}>1px</option>
              <option value="3" selected={@stroke_width == 3}>3px</option>
              <option value="5" selected={@stroke_width == 5}>5px</option>
              <option value="8" selected={@stroke_width == 8}>8px</option>
              <option value="12" selected={@stroke_width == 12}>12px</option>
            </select>

            <%!-- Actions --%>
            <div class="ml-auto flex items-center gap-2">
              <button
                phx-click="undo"
                phx-target={@myself}
                class="p-2 bg-gray-700 hover:bg-gray-600 text-gray-300 hover:text-white rounded transition-colors"
                title="Undo"
              >
                <Heroicons.icon name="arrow-uturn-left" type="outline" class="w-4 h-4" />
              </button>
              <button
                phx-click="clear_whiteboard"
                phx-target={@myself}
                class="p-2 bg-gray-700 hover:bg-red-600 text-gray-300 hover:text-white rounded transition-colors"
                title="Clear All"
              >
                <Heroicons.icon name="trash" type="outline" class="w-4 h-4" />
              </button>
            </div>
          </div>

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
                      <span class="px-3 py-1 text-xs bg-amber-700 text-amber-200 rounded">
                        Request pending...
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
                    class="px-3 py-1 text-xs bg-green-600 hover:bg-green-500 text-white rounded transition-colors"
                  >
                    Take Control
                  </button>
                <% end %>
              <% end %>
            </div>
            <%!-- Pending Request Alert for Controller --%>
            <%= if @pending_request_user_id && @current_user && @current_user.id == @controller_user_id do %>
              <div class="mt-2 px-3 py-2 bg-amber-900/50 border border-amber-600 rounded text-xs text-amber-200 flex items-center gap-2">
                <Heroicons.icon name="hand-raised" type="solid" class="w-4 h-4 text-amber-400" />
                <span>
                  <span class="font-medium">{@pending_request_user_name || "Someone"}</span>
                  is requesting control (30s timeout)
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Control Request Modal with Sound and Countdown --%>
        <%= if @pending_request_user_id && @current_user && @current_user.id == @controller_user_id do %>
          <div
            id={"whiteboard-request-sound-#{@room_id}"}
            phx-hook="NotificationSound"
            class="hidden"
          >
          </div>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
            <div
              id={"whiteboard-control-request-modal-#{@room_id}"}
              phx-hook="CountdownTimer"
              data-seconds="30"
              phx-click-away="dismiss_request_modal"
              phx-target={@myself}
              class="bg-gray-800 rounded-lg p-6 max-w-sm w-full shadow-xl border border-amber-600"
            >
              <div class="text-center">
                <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-amber-600/20 flex items-center justify-center">
                  <Heroicons.icon name="hand-raised" type="solid" class="w-6 h-6 text-amber-400" />
                </div>
                <h3 class="text-lg font-semibold text-white mb-2">Control Requested</h3>
                <p class="text-gray-300 mb-4">
                  <span class="font-medium text-amber-400">
                    {@pending_request_user_name || "Someone"}
                  </span>
                  wants to draw on the whiteboard
                </p>
                <div class="text-2xl font-mono text-amber-400 mb-4">
                  <span class="countdown-display">30</span>s
                </div>
                <div class="flex gap-3 justify-center">
                  <button
                    phx-click="keep_control"
                    phx-target={@myself}
                    class="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg transition-colors font-medium"
                  >
                    Keep Control
                  </button>
                  <button
                    phx-click="release_control"
                    phx-target={@myself}
                    class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded-lg transition-colors"
                  >
                    Release
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
