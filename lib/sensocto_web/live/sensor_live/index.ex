defmodule SensoctoWeb.SensorLive.Index do
  use SensoctoWeb, :live_view

  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.SimpleSensor

  require Logger

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensors:updates")
      schedule_refresh()
    end

    sensors = list_sensors()

    {:ok,
     socket
     |> assign(:page_title, "Sensors")
     |> assign(:sensors, sensors)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "All Sensors")
    |> assign(:sensor, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Sensor")
    |> assign(:sensor, get_sensor(id))
  end

  @impl true
  def handle_info(:refresh_sensors, socket) do
    schedule_refresh()
    sensors = list_sensors()
    {:noreply, assign(socket, :sensors, sensors)}
  end

  @impl true
  def handle_info({:sensor_added, _sensor_id}, socket) do
    sensors = list_sensors()
    {:noreply, assign(socket, :sensors, sensors)}
  end

  @impl true
  def handle_info({:sensor_removed, _sensor_id}, socket) do
    sensors = list_sensors()
    {:noreply, assign(socket, :sensors, sensors)}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_sensors, 5000)
  end

  defp list_sensors do
    SensorsDynamicSupervisor.get_device_names()
    |> Enum.map(fn sensor_id ->
      try do
        state = SimpleSensor.get_view_state(sensor_id)

        %{
          sensor_id: sensor_id,
          sensor_name: state.sensor_name,
          sensor_type: state.sensor_type,
          attributes: Map.keys(state.attributes || %{})
        }
      catch
        :exit, _ ->
          %{
            sensor_id: sensor_id,
            sensor_name: sensor_id,
            sensor_type: "unknown",
            attributes: []
          }
      end
    end)
    |> Enum.sort_by(& &1.sensor_name)
  end

  defp get_sensor(sensor_id) do
    try do
      SimpleSensor.get_view_state(sensor_id)
    catch
      :exit, _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">Sensors</h1>
        <span class="text-sm text-gray-400">
          {length(@sensors)} active sensors
        </span>
      </div>

      <div :if={@sensors == []} class="text-center py-12">
        <Heroicons.icon name="signal-slash" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
        <h3 class="mt-2 text-sm font-medium text-gray-300">No sensors connected</h3>
        <p class="mt-1 text-sm text-gray-500">
          Connect a sensor using the Web Connector below.
        </p>
      </div>

      <div :if={@sensors != []} class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={sensor <- @sensors}
          navigate={~p"/sensors/#{sensor.sensor_id}"}
          class="block bg-gray-800 rounded-lg p-4 hover:bg-gray-700 transition-colors border border-gray-700 hover:border-gray-600"
        >
          <div class="flex items-start justify-between">
            <div class="flex-1 min-w-0">
              <h3 class="text-lg font-medium text-white truncate">
                {sensor.sensor_name}
              </h3>
              <p class="text-sm text-gray-400 mt-1">
                {sensor.sensor_type}
              </p>
            </div>
            <div class="ml-4 flex-shrink-0">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-900 text-green-300">
                Active
              </span>
            </div>
          </div>

          <div :if={sensor.attributes != []} class="mt-3 flex flex-wrap gap-1">
            <span
              :for={attr <- Enum.take(sensor.attributes, 4)}
              class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-700 text-gray-300"
            >
              {attr}
            </span>
            <span
              :if={length(sensor.attributes) > 4}
              class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-700 text-gray-300"
            >
              +{length(sensor.attributes) - 4} more
            </span>
          </div>

          <div class="mt-3 flex items-center text-sm text-gray-500">
            <Heroicons.icon name="arrow-right" type="outline" class="h-4 w-4 mr-1" /> View details
          </div>
        </.link>
      </div>
    </div>
    """
  end
end
