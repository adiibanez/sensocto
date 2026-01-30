defmodule SensoctoWeb.LobbyLive.SensorCompareLive do
  @moduledoc """
  Multi-sensor comparison view for viewing 2-10 sensors side-by-side.

  Routes:
  - /lobby/compare?ids=sensor1,sensor2,sensor3

  Features (planned):
  - Grid layout for 2-6 sensors
  - Stacked layout for 7-10 sensors
  - Synchronized time axis
  - Lens filtering across sensors
  """

  use SensoctoWeb, :live_view

  alias Sensocto.SimpleSensor

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:sensor_ids, [])
     |> assign(:sensors, %{})
     |> assign(:lens, nil)
     |> assign(:sync_enabled, true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Parse sensor IDs from query params
    sensor_ids =
      case params["ids"] do
        nil -> []
        ids_string -> String.split(ids_string, ",") |> Enum.take(10)
      end

    lens = params["lens"]

    # Fetch sensor states
    sensors =
      sensor_ids
      |> Enum.map(fn id -> {id, fetch_sensor_state(id)} end)
      |> Enum.into(%{})

    # Subscribe to PubSub for each sensor if connected
    if connected?(socket) do
      Enum.each(sensor_ids, fn sensor_id ->
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      end)
    end

    {:noreply,
     socket
     |> assign(:sensor_ids, sensor_ids)
     |> assign(:sensors, sensors)
     |> assign(:lens, lens)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white">
      <%!-- Header --%>
      <header class="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div class="flex items-center justify-between max-w-7xl mx-auto">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/lobby"}
              class="flex items-center gap-2 text-gray-400 hover:text-white transition-colors"
            >
              <Heroicons.icon name="arrow-left" type="outline" class="h-5 w-5" />
              <span class="hidden sm:inline">Back to Lobby</span>
            </.link>
            <div class="h-6 w-px bg-gray-700" />
            <h1 class="text-lg font-semibold">
              Comparing {length(@sensor_ids)} sensors
            </h1>
          </div>
          <div class="flex items-center gap-4">
            <label class="flex items-center gap-2 text-sm text-gray-400">
              <input
                type="checkbox"
                checked={@sync_enabled}
                phx-click="toggle_sync"
                class="rounded border-gray-600 bg-gray-700 text-green-500 focus:ring-green-500"
              /> Sync Time
            </label>
          </div>
        </div>
      </header>

      <%!-- Main content --%>
      <main class="max-w-7xl mx-auto p-4">
        <%= if @sensor_ids == [] do %>
          <div class="text-center py-12">
            <Heroicons.icon name="squares-2x2" type="outline" class="mx-auto h-16 w-16 text-gray-500" />
            <h2 class="mt-4 text-xl font-semibold text-gray-300">No sensors selected</h2>
            <p class="mt-2 text-gray-400">
              Select sensors from the lobby to compare them side-by-side.
            </p>
            <.link
              navigate={~p"/lobby"}
              class="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg transition-colors"
            >
              <Heroicons.icon name="arrow-left" type="outline" class="h-4 w-4" /> Go to Lobby
            </.link>
          </div>
        <% else %>
          <div class={grid_class(length(@sensor_ids))}>
            <div
              :for={sensor_id <- @sensor_ids}
              class="bg-gray-800 rounded-lg p-4 border border-gray-700"
            >
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h3 class="font-semibold text-white">{@sensors[sensor_id].sensor_name}</h3>
                  <p class="text-sm text-gray-400">{@sensors[sensor_id].sensor_type}</p>
                </div>
                <button
                  phx-click="remove_sensor"
                  phx-value-sensor_id={sensor_id}
                  class="text-gray-400 hover:text-red-400 transition-colors"
                  title="Remove from comparison"
                >
                  <Heroicons.icon name="x-mark" type="outline" class="h-5 w-5" />
                </button>
              </div>
              <div class="text-sm text-gray-400">
                <span>{map_size(@sensors[sensor_id].attributes)} attributes</span>
              </div>
              <%!-- Placeholder for sensor visualization --%>
              <div class="mt-4 h-48 bg-gray-900 rounded flex items-center justify-center text-gray-500">
                Visualization placeholder
              </div>
            </div>
          </div>
        <% end %>
      </main>
    </div>
    """
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_sync", _params, socket) do
    {:noreply, assign(socket, :sync_enabled, !socket.assigns.sync_enabled)}
  end

  @impl true
  def handle_event("remove_sensor", %{"sensor_id" => sensor_id}, socket) do
    new_ids = Enum.reject(socket.assigns.sensor_ids, &(&1 == sensor_id))
    new_sensors = Map.delete(socket.assigns.sensors, sensor_id)

    # Update URL
    ids_param = Enum.join(new_ids, ",")

    {:noreply,
     socket
     |> assign(:sensor_ids, new_ids)
     |> assign(:sensors, new_sensors)
     |> push_patch(to: ~p"/lobby/compare?ids=#{ids_param}")}
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:measurements_batch, {sensor_id, _measurements}}, socket) do
    # Update sensor state
    if sensor_id in socket.assigns.sensor_ids do
      try do
        new_state = SimpleSensor.get_view_state(sensor_id)
        sensors = Map.put(socket.assigns.sensors, sensor_id, new_state)
        {:noreply, assign(socket, :sensors, sensors)}
      catch
        :exit, _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:measurement, %{sensor_id: sensor_id}}, socket) do
    if sensor_id in socket.assigns.sensor_ids do
      try do
        new_state = SimpleSensor.get_view_state(sensor_id)
        sensors = Map.put(socket.assigns.sensors, sensor_id, new_state)
        {:noreply, assign(socket, :sensors, sensors)}
      catch
        :exit, _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp fetch_sensor_state(sensor_id) do
    case SimpleSensor.get_view_state(sensor_id) do
      state when is_map(state) ->
        state

      _ ->
        %{sensor_id: sensor_id, sensor_name: sensor_id, sensor_type: "unknown", attributes: %{}}
    end
  catch
    :exit, _ ->
      %{sensor_id: sensor_id, sensor_name: sensor_id, sensor_type: "unknown", attributes: %{}}
  end

  defp grid_class(count) when count <= 2, do: "grid gap-4 md:grid-cols-2"
  defp grid_class(count) when count <= 4, do: "grid gap-4 md:grid-cols-2"
  defp grid_class(count) when count <= 6, do: "grid gap-4 md:grid-cols-2 lg:grid-cols-3"
  defp grid_class(_count), do: "grid gap-4 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
end
