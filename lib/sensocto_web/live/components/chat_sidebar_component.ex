defmodule SensoctoWeb.Components.ChatSidebarComponent do
  @moduledoc """
  Desktop chat sidebar component.

  Provides a collapsible right sidebar containing the chat interface.
  Uses the existing Sidebar component for slide-in/out animations.
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:unread_count, 0)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_user, assigns[:current_user])
      |> assign(:room_id, assigns[:room_id] || "global")

    # Handle unread updates from chat
    socket =
      if assigns[:chat_unread] do
        assign(socket, :unread_count, assigns.chat_unread)
      else
        socket
      end

    # Handle open state from parent or restore
    socket =
      if Map.has_key?(assigns, :open) do
        assign(socket, :open, assigns.open)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chat-sidebar-wrapper" class="hidden md:block" phx-hook="ChatSidebarHook">
      <%!-- Toggle button (visible when sidebar closed) --%>
      <button
        :if={!@open}
        phx-click="open_sidebar"
        phx-target={@myself}
        class="fixed bottom-28 right-4 z-30 bg-blue-600 hover:bg-blue-700 text-white rounded-full p-3 shadow-lg transition-all"
        title="Open chat"
      >
        <div class="relative">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
            />
          </svg>
          <span
            :if={@unread_count > 0}
            class="absolute -top-2 -right-2 bg-red-500 text-white text-xs rounded-full h-5 w-5 flex items-center justify-center"
          >
            {@unread_count}
          </span>
        </div>
      </button>

      <%!-- Sidebar panel --%>
      <aside
        :if={@open}
        id="chat-sidebar"
        class={[
          "fixed top-0 end-0 h-screen w-80 bg-gray-800 border-l border-gray-700 z-30",
          "transition-transform transform-none"
        ]}
      >
        <%!-- Sidebar header with close button --%>
        <div class="flex items-center justify-between p-3 border-b border-gray-700">
          <div class="flex items-center gap-2">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 text-blue-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
              />
            </svg>
            <h2 class="font-semibold text-white">Chat</h2>
          </div>
          <button
            phx-click="close_sidebar"
            phx-target={@myself}
            class="text-gray-400 hover:text-white p-1 rounded transition-colors"
            title="Close chat"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fill-rule="evenodd"
                d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
                clip-rule="evenodd"
              />
            </svg>
          </button>
        </div>

        <%!-- Chat content --%>
        <div class="h-[calc(100vh-57px)]">
          <.live_component
            module={SensoctoWeb.Components.ChatComponent}
            id="sidebar-chat"
            room_id={@room_id}
            current_user={@current_user}
            mode={:sidebar}
          />
        </div>
      </aside>
    </div>
    """
  end

  @impl true
  def handle_event("open_sidebar", _params, socket) do
    socket =
      socket
      |> assign(:open, true)
      |> assign(:unread_count, 0)

    {:noreply, push_event(socket, "sidebar_opened", %{})}
  end

  def handle_event("close_sidebar", _params, socket) do
    {:noreply,
     socket
     |> assign(:open, false)
     |> push_event("sidebar_closed", %{})}
  end
end
