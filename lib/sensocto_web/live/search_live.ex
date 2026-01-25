defmodule SensoctoWeb.SearchLive do
  @moduledoc """
  Global search LiveView that can be rendered in the layout.
  Handles keyboard shortcuts (Cmd/Ctrl+K) and displays a command palette.
  """
  use SensoctoWeb, :live_view

  alias Sensocto.Search.SearchIndex

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:query, "")
     |> assign(:results, %{sensors: [], rooms: [], users: []})
     |> assign(:selected_index, 0)
     |> assign(:loading, false), layout: false}
  end

  @impl true
  def handle_event("open", _, socket) do
    {:noreply,
     socket
     |> assign(:open, true)
     |> assign(:query, "")
     |> assign(:results, %{sensors: [], rooms: [], users: []})
     |> assign(:selected_index, 0)
     |> push_event("focus-search-input", %{})}
  end

  @impl true
  def handle_event("close", _, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    if String.length(query) >= 1 do
      results = SearchIndex.search(query)

      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, results)
       |> assign(:selected_index, 0)
       |> assign(:loading, false)}
    else
      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, %{sensors: [], rooms: [], users: []})
       |> assign(:selected_index, 0)
       |> assign(:loading, false)}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    total = total_results(socket.assigns.results)
    new_index = min(socket.assigns.selected_index + 1, total - 1)
    {:noreply, assign(socket, :selected_index, max(0, new_index))}
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    new_index = max(socket.assigns.selected_index - 1, 0)
    {:noreply, assign(socket, :selected_index, new_index)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "Enter"}, socket) do
    case get_selected_item(socket.assigns.results, socket.assigns.selected_index) do
      {:sensor, sensor} ->
        {:noreply,
         socket
         |> assign(:open, false)
         |> push_navigate(to: ~p"/sensors/#{sensor.id}")}

      {:room, room} ->
        {:noreply,
         socket
         |> assign(:open, false)
         |> push_navigate(to: ~p"/rooms/#{room.id}")}

      {:user, _user} ->
        # Users don't have a dedicated page yet, just close
        {:noreply, assign(socket, :open, false)}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("keydown", _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select", %{"type" => "sensor", "id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:open, false)
     |> push_navigate(to: ~p"/sensors/#{id}")}
  end

  @impl true
  def handle_event("select", %{"type" => "room", "id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:open, false)
     |> push_navigate(to: ~p"/rooms/#{id}")}
  end

  defp total_results(%{sensors: sensors, rooms: rooms, users: users}) do
    length(sensors) + length(rooms) + length(users)
  end

  defp get_selected_item(%{sensors: sensors, rooms: rooms, users: users}, index) do
    all_items =
      Enum.map(sensors, &{:sensor, &1}) ++
        Enum.map(rooms, &{:room, &1}) ++
        Enum.map(users, &{:user, &1})

    Enum.at(all_items, index)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="search-container" phx-hook="GlobalSearch">
      <div
        :if={@open}
        class="fixed inset-0 z-[100] overflow-y-auto"
        phx-window-keydown="keydown"
      >
        <div
          class="fixed inset-0 bg-black/60 backdrop-blur-sm"
          phx-click="close"
        >
        </div>

        <div class="relative min-h-screen flex items-start justify-center pt-16 sm:pt-24 px-4">
          <div
            class="relative w-full max-w-xl bg-gray-800 rounded-xl shadow-2xl border border-gray-700 overflow-hidden"
            phx-click-away="close"
          >
            <div class="flex items-center px-4 py-3 border-b border-gray-700">
              <Heroicons.icon
                name="magnifying-glass"
                type="outline"
                class="h-5 w-5 text-gray-400 mr-3"
              />
              <form phx-change="search" phx-submit="search" class="flex-1" role="search">
                <input
                  type="text"
                  name="query"
                  value={@query}
                  placeholder="Search sensors, rooms..."
                  aria-label="Search sensors, rooms, and users"
                  class="w-full bg-transparent text-white placeholder-gray-500 focus:outline-none text-lg"
                  autocomplete="off"
                  phx-debounce="150"
                  id="search-palette-input"
                  phx-hook="SearchPaletteInput"
                />
              </form>
              <kbd class="hidden sm:inline-flex items-center px-2 py-1 text-xs text-gray-500 bg-gray-700 rounded">
                ESC
              </kbd>
            </div>

            <div class="max-h-96 overflow-y-auto">
              <div :if={@loading} class="px-4 py-8 text-center">
                <div class="inline-block animate-spin rounded-full h-6 w-6 border-2 border-gray-600 border-t-blue-500">
                </div>
              </div>

              <div
                :if={!@loading && @query != "" && total_results(@results) == 0}
                class="px-4 py-8 text-center text-gray-400"
              >
                No results found for "{@query}"
              </div>

              <div :if={!@loading && @query == ""} class="px-4 py-6 text-center text-gray-500">
                <Heroicons.icon name="magnifying-glass" type="outline" class="mx-auto h-8 w-8 mb-2" />
                <p>Start typing to search</p>
                <p class="text-xs mt-1">Search sensors, rooms, and users</p>
              </div>

              <%= if !@loading && total_results(@results) > 0 do %>
                <div :if={@results.sensors != []} class="py-2">
                  <div class="px-4 py-1 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                    Sensors
                  </div>
                  <%= for {sensor, idx} <- Enum.with_index(@results.sensors) do %>
                    <button
                      phx-click="select"
                      phx-value-type="sensor"
                      phx-value-id={sensor.id}
                      class={"w-full px-4 py-2 flex items-center gap-3 text-left hover:bg-gray-700/50 #{if idx == @selected_index, do: "bg-gray-700/50", else: ""}"}
                    >
                      <div class="flex-shrink-0 w-8 h-8 rounded-lg bg-blue-500/20 flex items-center justify-center">
                        <Heroicons.icon name="signal" type="outline" class="h-4 w-4 text-blue-400" />
                      </div>
                      <div class="flex-1 min-w-0">
                        <div class="text-sm text-white truncate">{sensor.name}</div>
                        <div class="text-xs text-gray-500 truncate">{sensor.type}</div>
                      </div>
                      <Heroicons.icon name="arrow-right" type="outline" class="h-4 w-4 text-gray-500" />
                    </button>
                  <% end %>
                </div>

                <div :if={@results.rooms != []} class="py-2 border-t border-gray-700/50">
                  <div class="px-4 py-1 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                    Rooms
                  </div>
                  <%= for {room, idx} <- Enum.with_index(@results.rooms) do %>
                    <% adjusted_idx = idx + length(@results.sensors) %>
                    <button
                      phx-click="select"
                      phx-value-type="room"
                      phx-value-id={room.id}
                      class={"w-full px-4 py-2 flex items-center gap-3 text-left hover:bg-gray-700/50 #{if adjusted_idx == @selected_index, do: "bg-gray-700/50", else: ""}"}
                    >
                      <div class="flex-shrink-0 w-8 h-8 rounded-lg bg-green-500/20 flex items-center justify-center">
                        <Heroicons.icon
                          name="building-office"
                          type="outline"
                          class="h-4 w-4 text-green-400"
                        />
                      </div>
                      <div class="flex-1 min-w-0">
                        <div class="text-sm text-white truncate">{room.name}</div>
                        <div :if={room.description} class="text-xs text-gray-500 truncate">
                          {room.description}
                        </div>
                      </div>
                      <span
                        :if={room.is_public}
                        class="text-xs px-1.5 py-0.5 rounded bg-green-900/50 text-green-400"
                      >
                        Public
                      </span>
                      <Heroicons.icon name="arrow-right" type="outline" class="h-4 w-4 text-gray-500" />
                    </button>
                  <% end %>
                </div>

                <div :if={@results.users != []} class="py-2 border-t border-gray-700/50">
                  <div class="px-4 py-1 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                    Users
                  </div>
                  <%= for {user, idx} <- Enum.with_index(@results.users) do %>
                    <% adjusted_idx = idx + length(@results.sensors) + length(@results.rooms) %>
                    <div class={"w-full px-4 py-2 flex items-center gap-3 text-left #{if adjusted_idx == @selected_index, do: "bg-gray-700/50", else: ""}"}>
                      <div class="flex-shrink-0 w-8 h-8 rounded-lg bg-purple-500/20 flex items-center justify-center">
                        <Heroicons.icon name="user" type="outline" class="h-4 w-4 text-purple-400" />
                      </div>
                      <div class="flex-1 min-w-0">
                        <div class="text-sm text-white truncate">{user.name}</div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="px-4 py-2 border-t border-gray-700 flex items-center justify-between text-xs text-gray-500">
              <div class="flex items-center gap-4">
                <span class="flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-gray-700 rounded">↑</kbd>
                  <kbd class="px-1.5 py-0.5 bg-gray-700 rounded">↓</kbd> Navigate
                </span>
                <span class="flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-gray-700 rounded">↵</kbd> Select
                </span>
              </div>
              <span class="hidden sm:inline">
                <kbd class="px-1.5 py-0.5 bg-gray-700 rounded">⌘</kbd>
                <kbd class="px-1.5 py-0.5 bg-gray-700 rounded">K</kbd> to open
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
