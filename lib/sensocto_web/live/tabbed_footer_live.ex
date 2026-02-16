defmodule SensoctoWeb.TabbedFooterLive do
  @moduledoc """
  Mobile tabbed footer navigation LiveView.

  Provides a tabbed interface at the bottom of the screen for mobile devices,
  switching between:
  - Navigation (5-item bottom nav)
  - Chat (inline chat interface)
  - Controls (placeholder for future sensor controls)
  """
  use SensoctoWeb, :live_view

  # Include AI chat handler for forwarding AI responses
  use Sensocto.Chat.AIChatHandler

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    room_id = session["room_id"] || "global"
    chat_enabled = session["chat_enabled"] || false

    socket =
      socket
      |> assign(:active_tab, :nav)
      |> assign(:current_user, current_user)
      |> assign(:room_id, room_id)
      |> assign(:current_path, session["current_path"] || "/")
      |> assign(:chat_enabled, chat_enabled)
      |> assign(:collapsed, !primary_page?(session["current_path"] || "/"))

    {:ok, socket, layout: false}
  end

  defp primary_page?(path) do
    String.starts_with?(path, "/lobby") or String.starts_with?(path, "/rooms")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :should_collapse, !primary_page?(assigns.current_path))

    ~H"""
    <div
      id="tabbed-footer"
      class="md:hidden fixed bottom-0 left-0 right-0 z-50"
      phx-hook="TabbedFooterHook"
    >
      <%!-- Collapsed pill: shown on non-primary pages when not manually expanded --%>
      <div
        :if={@should_collapse && @collapsed}
        class="flex justify-center pb-2"
      >
        <button
          phx-click="expand_footer"
          class="flex items-center gap-1.5 px-3 py-1.5 bg-gray-800 border border-gray-700 rounded-full text-gray-400 hover:text-white hover:bg-gray-700 transition-colors shadow-lg touch-manipulation"
        >
          <Heroicons.icon name="chevron-up" type="outline" class="h-4 w-4" />
          <Heroicons.icon name="signal" type="outline" class="h-4 w-4" />
        </button>
      </div>

      <%!-- Full footer: shown on primary pages always, or when manually expanded --%>
      <div
        :if={!@should_collapse || !@collapsed}
        class="bg-gray-900 border-t border-gray-700"
      >
        <%!-- Collapse button on non-primary pages --%>
        <button
          :if={@should_collapse}
          phx-click="collapse_footer"
          class="w-full flex justify-center py-1 text-gray-500 hover:text-gray-300 transition-colors touch-manipulation"
        >
          <Heroicons.icon name="chevron-down" type="outline" class="h-4 w-4" />
        </button>
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

          <%!-- Chat Tab Content (only if chat is enabled) --%>
          <div :if={@chat_enabled && @active_tab == :chat} class="h-[50vh] max-h-[400px]">
            <.live_component
              module={SensoctoWeb.Components.ChatComponent}
              id="mobile-chat"
              room_id={@room_id}
              current_user={@current_user}
              mode={:inline}
            />
          </div>

          <%!-- Controls Tab Content --%>
          <div :if={@active_tab == :controls} class="px-3 py-2 bg-gray-800">
            {live_render(@socket, SensoctoWeb.SenseLive,
              id: "bluetooth-mobile-tabbed",
              sticky: true,
              session: %{"parent_id" => self(), "mobile" => true}
            )}
          </div>
        </div>

        <%!-- Tab bar --%>
        <div class={[
          "grid bg-gray-900 border-t border-gray-800",
          if(@chat_enabled, do: "grid-cols-3", else: "grid-cols-2")
        ]}>
          <button
            phx-click="switch_tab"
            phx-value-tab="nav"
            class={[
              "flex flex-col items-center justify-center py-2 transition-colors touch-manipulation",
              if(@active_tab == :nav, do: "text-blue-400", else: "text-gray-400 hover:text-gray-200")
            ]}
          >
            <Heroicons.icon name="squares-2x2" type="outline" class="h-5 w-5" />
            <span class="text-[10px] font-medium mt-0.5">Navigate</span>
          </button>

          <button
            :if={@chat_enabled}
            phx-click="switch_tab"
            phx-value-tab="chat"
            class={[
              "flex flex-col items-center justify-center py-2 transition-colors touch-manipulation relative",
              if(@active_tab == :chat, do: "text-blue-400", else: "text-gray-400 hover:text-gray-200")
            ]}
          >
            <Heroicons.icon name="chat-bubble-left-right" type="outline" class="h-5 w-5" />
            <span class="text-[10px] font-medium mt-0.5">Chat</span>
          </button>

          <button
            phx-click="switch_tab"
            phx-value-tab="controls"
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
  def handle_event("path_changed", %{"path" => path}, socket) do
    # Auto-collapse when navigating away from primary pages, expand when arriving
    collapsed = if primary_page?(path), do: false, else: true
    {:noreply, socket |> assign(:current_path, path) |> assign(:collapsed, collapsed)}
  end

  @impl true
  def handle_event("expand_footer", _params, socket) do
    {:noreply, assign(socket, :collapsed, false)}
  end

  @impl true
  def handle_event("collapse_footer", _params, socket) do
    {:noreply, assign(socket, :collapsed, true)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    active_tab = String.to_existing_atom(tab)

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> push_event("save_active_tab", %{tab: tab})}
  end
end
