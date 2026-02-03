defmodule SensoctoWeb.Components.TabbedFooterComponent do
  @moduledoc """
  Mobile tabbed footer navigation component.

  Provides a tabbed interface at the bottom of the screen for mobile devices,
  switching between:
  - Navigation (5-item bottom nav)
  - Chat (inline chat interface)
  - Controls (SenseLive bluetooth controls)
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:active_tab, :nav)
     |> assign(:chat_unread, 0)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_path, assigns[:current_path] || "/")
      |> assign(:current_user, assigns[:current_user])
      |> assign(:room_id, assigns[:room_id] || "global")

    # Track unread from chat component updates
    socket =
      if assigns[:chat_unread] do
        assign(socket, :chat_unread, assigns.chat_unread)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="tabbed-footer"
      class="md:hidden fixed bottom-0 left-0 right-0 z-50 bg-gray-900 border-t border-gray-700"
      phx-hook="TabbedFooterHook"
    >
      <%!-- Tab content area --%>
      <div class="relative">
        <%!-- Navigation Tab Content --%>
        <div :if={@active_tab == :nav} class="bg-gray-800">
          <div class="grid grid-cols-5 h-14">
            <.nav_item
              navigate={~p"/"}
              icon="home"
              label="Home"
              active={@current_path == "/"}
            />
            <.nav_item
              navigate={~p"/lobby"}
              icon="squares-2x2"
              label="Lobby"
              active={String.starts_with?(@current_path, "/lobby")}
            />
            <.nav_item
              navigate={~p"/rooms"}
              icon="building-office"
              label="Rooms"
              active={String.starts_with?(@current_path, "/rooms")}
            />
            <.nav_item
              navigate={~p"/sensors"}
              icon="signal"
              label="Sensors"
              active={String.starts_with?(@current_path, "/sensors")}
            />
            <.nav_item
              navigate={~p"/simulator"}
              icon="cpu-chip"
              label="Sim"
              active={String.starts_with?(@current_path, "/simulator")}
            />
          </div>
        </div>

        <%!-- Chat Tab Content --%>
        <div :if={@active_tab == :chat} class="h-[60vh] max-h-[500px]">
          <.live_component
            module={SensoctoWeb.Components.ChatComponent}
            id="mobile-chat"
            room_id={@room_id}
            current_user={@current_user}
            mode={:inline}
          />
        </div>

        <%!-- Controls Tab Content --%>
        <div :if={@active_tab == :controls} class="p-3 bg-gray-800">
          <div class="text-sm text-gray-400 mb-2 flex items-center gap-2">
            <Heroicons.icon name="signal" type="outline" class="h-4 w-4" />
            <span>Sensor Controls</span>
          </div>
          <div id="mobile-sense-controls">
            <%!-- SenseLive will be rendered here by the layout --%>
            <div class="text-gray-500 text-sm text-center py-4">
              Sensor controls loading...
            </div>
          </div>
        </div>
      </div>

      <%!-- Tab bar --%>
      <div class="grid grid-cols-3 bg-gray-900 border-t border-gray-800">
        <button
          phx-click="switch_tab"
          phx-value-tab="nav"
          phx-target={@myself}
          class={[
            "flex flex-col items-center justify-center py-2 transition-colors touch-manipulation",
            if(@active_tab == :nav, do: "text-blue-400", else: "text-gray-400 hover:text-gray-200")
          ]}
        >
          <Heroicons.icon name="squares-2x2" type="outline" class="h-5 w-5" />
          <span class="text-[10px] font-medium mt-0.5">Navigate</span>
        </button>

        <button
          phx-click="switch_tab"
          phx-value-tab="chat"
          phx-target={@myself}
          class={[
            "flex flex-col items-center justify-center py-2 transition-colors touch-manipulation relative",
            if(@active_tab == :chat, do: "text-blue-400", else: "text-gray-400 hover:text-gray-200")
          ]}
        >
          <div class="relative">
            <Heroicons.icon name="chat-bubble-left-right" type="outline" class="h-5 w-5" />
            <span
              :if={@chat_unread > 0 && @active_tab != :chat}
              class="absolute -top-1 -right-1 bg-red-500 text-white text-[8px] rounded-full h-4 w-4 flex items-center justify-center"
            >
              {@chat_unread}
            </span>
          </div>
          <span class="text-[10px] font-medium mt-0.5">Chat</span>
        </button>

        <button
          phx-click="switch_tab"
          phx-value-tab="controls"
          phx-target={@myself}
          class={[
            "flex flex-col items-center justify-center py-2 transition-colors touch-manipulation",
            if(@active_tab == :controls,
              do: "text-blue-400",
              else: "text-gray-400 hover:text-gray-200"
            )
          ]}
        >
          <Heroicons.icon name="signal" type="outline" class="h-5 w-5" />
          <span class="text-[10px] font-medium mt-0.5">Sensors</span>
        </button>
      </div>
    </div>
    """
  end

  # Navigation item component
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex flex-col items-center justify-center gap-0.5 transition-colors touch-manipulation",
        "min-h-[44px]",
        @active && "text-blue-400",
        !@active && "text-gray-400 hover:text-gray-200 active:text-blue-400"
      ]}
    >
      <Heroicons.icon name={@icon} type="outline" class="w-5 h-5" />
      <span class="text-[10px] font-medium">{@label}</span>
    </.link>
    """
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    active_tab = String.to_existing_atom(tab)

    socket =
      socket
      |> assign(:active_tab, active_tab)
      # Clear unread when switching to chat tab
      |> then(fn s ->
        if active_tab == :chat, do: assign(s, :chat_unread, 0), else: s
      end)

    # Notify hook to persist tab preference
    {:noreply, push_event(socket, "save_active_tab", %{tab: tab})}
  end
end
