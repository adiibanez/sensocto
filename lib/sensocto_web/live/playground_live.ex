defmodule SensoctoWeb.Live.PlaygroundLive do
  alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  # use LiveSvelte.Components
  alias SensoctoWeb.Live.Components.ViewData

  @impl true
  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:sensors, %{
       1 => %{id: 1, name: "Temperature", unit: "°C", data: [], highlighted: false},
       2 => %{id: 2, name: "Humidity", unit: "%", data: [], highlighted: false},
       3 => %{id: 3, name: "Pressure", unit: "hPa", data: [], highlighted: false},
       4 => %{id: 4, name: "Light", unit: "lux", data: [], highlighted: false},
       5 => %{id: 5, name: "ECG", unit: "mV", data: [], highlighted: false},
       6 => %{id: 6, name: "ECG", unit: "mV", data: [], highlighted: false}
     })
     |> assign(:sensor_ids, [1, 2, 3, 4, 5, 6])}
  end

  @spec handle_event(<<_::104>>, map(), map()) :: {:noreply, map()}
  def handle_event("set_highlight", params, socket) do
    Logger.info("Received highlight event: #{inspect(params)}")

    updated_sensors =
      socket.assigns.sensors
      |> Map.map(fn {key, sensor} ->
        if String.to_integer(params["id"]) == key do
          Map.put(sensor, :highlighted, not sensor.highlighted)
        else
          Map.put(sensor, :highlighted, false)
        end
      end)
      |> Map.values()
      |> Enum.reduce(%{}, fn sensor, acc ->
        Map.put(acc, sensor.id, sensor)
      end)

    {:noreply, assign(socket, :sensors, updated_sensors)}
  end

  def render(assigns) do
    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 lg:gap-8 xl:gap-8 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
      <div
        :for={{id, sensor} <- @sensors}
        class="flex flex-col  rounded-lg shadow-md p-4 sm:p-6 md:p-8 lg:p-8 xl:p-8 cursor-pointer bg-dark-gray text-light-gray"
        class:col-span-2={sensor.highlighted}
        class:row-span-2={sensor.highlighted}
        phx-click="set_highlight"
        phx-value-id={id}
      >
        Highlight: {sensor.highlighted}
        <div class="flex-1">
          <div class="font-bold text-orange sm:text-xl md:text-2xl mb-2">{sensor.name}</div>
          <div class="text-sm sm:text-base mb-4 text-medium-gray">Unit: {sensor.unit}</div>
          <div class="h-24 sm:h-32 md:h-40 border border-dark-gray rounded-md bg-medium-gray">
            <!-- Sensor Visualization component goes here -->
          </div>
        </div>
        <div class="mt-4 sm:mt-6 md:mt-8 text-sm sm:text-base text-medium-gray">
          {inspect(sensor)}
        </div>
      </div>
    </div>
    """
  end
end
