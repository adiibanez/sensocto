defmodule SensoctoWeb.Live.Components.SyncStatusComponent do
  @moduledoc """
  Component showing sync status of connected users.
  Displays a compact badge showing how many users are synced ("pack")
  vs watching independently ("lone wolves").
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:expanded, false)
     |> assign(:synced_users, [])
     |> assign(:solo_users, [])
     |> assign(:controller_user_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:synced_users, assigns[:synced_users] || socket.assigns.synced_users)
      |> assign(:solo_users, assigns[:solo_users] || socket.assigns.solo_users)
      |> assign(
        :controller_user_id,
        assigns[:controller_user_id] || socket.assigns.controller_user_id
      )
      |> assign(:current_user, assigns[:current_user] || socket.assigns[:current_user])

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_expanded", _, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Compact Badge --%>
      <button
        phx-click="toggle_expanded"
        phx-target={@myself}
        class="flex items-center gap-3 px-3 py-1.5 bg-gray-800/80 hover:bg-gray-700/80 rounded-lg transition-colors border border-gray-700"
        title="Click to see who's synced"
      >
        <%!-- Synced Users (Pack) --%>
        <div class="flex items-center gap-1.5">
          <div class="flex -space-x-1">
            <%= for i <- 0..min(3, length(@synced_users) - 1) do %>
              <span
                class="w-2 h-2 bg-green-400 rounded-full border border-gray-800 sync-dot"
                style={"animation-delay: #{i * 150}ms"}
              >
              </span>
            <% end %>
            <%= if length(@synced_users) > 4 do %>
              <span class="text-xs text-green-400 ml-1">+{length(@synced_users) - 4}</span>
            <% end %>
          </div>
          <span class="text-xs text-gray-300">
            {length(@synced_users)} synced
          </span>
        </div>

        <%!-- Divider --%>
        <%= if length(@solo_users) > 0 do %>
          <span class="w-px h-3 bg-gray-600"></span>

          <%!-- Solo Users (Lone Wolves) --%>
          <div class="flex items-center gap-1.5">
            <div class="flex -space-x-1">
              <%= for _i <- 0..min(2, length(@solo_users) - 1) do %>
                <span class="w-2 h-2 bg-slate-400 rounded-full border border-gray-800"></span>
              <% end %>
              <%= if length(@solo_users) > 3 do %>
                <span class="text-xs text-slate-400 ml-1">+{length(@solo_users) - 3}</span>
              <% end %>
            </div>
            <span class="text-xs text-slate-400">
              {length(@solo_users)} solo
            </span>
          </div>
        <% end %>

        <%!-- Expand indicator --%>
        <svg
          class={"w-3 h-3 text-gray-500 transition-transform #{if @expanded, do: "rotate-180"}"}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      <%!-- Expanded Panel --%>
      <%= if @expanded do %>
        <div class="absolute top-full left-0 mt-2 w-64 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 overflow-hidden">
          <div class="px-3 py-2 border-b border-gray-700 flex items-center justify-between">
            <span class="text-sm font-medium text-white">Sync Status</span>
            <button
              phx-click="toggle_expanded"
              phx-target={@myself}
              class="text-gray-400 hover:text-white"
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

          <div class="max-h-64 overflow-y-auto">
            <%!-- Synced Users Section --%>
            <%= if length(@synced_users) > 0 do %>
              <div class="px-3 py-2">
                <div class="text-xs text-green-400 font-medium mb-2 flex items-center gap-1">
                  <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                  Connected ({length(@synced_users)})
                </div>
                <div class="space-y-1">
                  <%= for user <- @synced_users do %>
                    <div class="flex items-center gap-2 text-sm">
                      <%= if user.user_id == @controller_user_id do %>
                        <svg
                          class="w-3.5 h-3.5 text-amber-400"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                        </svg>
                      <% else %>
                        <span class="w-2 h-2 bg-green-400 rounded-full"></span>
                      <% end %>
                      <span class="text-gray-300 truncate">{user.user_name || "Anonymous"}</span>
                      <%= if user.user_id == @controller_user_id do %>
                        <span class="text-xs text-amber-400">(controlling)</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Solo Users Section --%>
            <%= if length(@solo_users) > 0 do %>
              <div class="px-3 py-2 border-t border-gray-700">
                <div class="text-xs text-slate-400 font-medium mb-2 flex items-center gap-1">
                  <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  Solo Explorers ({length(@solo_users)})
                </div>
                <div class="space-y-1">
                  <%= for user <- @solo_users do %>
                    <div class="flex items-center gap-2 text-sm">
                      <span class="w-2 h-2 bg-slate-400 rounded-full"></span>
                      <span class="text-gray-400 truncate">{user.user_name || "Anonymous"}</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Empty State --%>
            <%= if length(@synced_users) == 0 and length(@solo_users) == 0 do %>
              <div class="px-3 py-4 text-center text-gray-500 text-sm">
                No other viewers
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
