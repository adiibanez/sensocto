defmodule SensoctoWeb.Live.PlaygroundLive do
  use SensoctoWeb, :live_view
  require Logger

  import SensoctoWeb.Components.RangeField
  import SensoctoWeb.Components.RadioField
  # import SensoctoWeb.Components.RadioGroup
  import SensoctoWeb.Components.SpeedDial
  import SensoctoWeb.Components.Sidebar

  # import Phoenix.HTML.Form
  import LiveSvelte
  # use LiveSvelte.Components

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
     # |> assign(:form, %Phoenix.HTML.Form{})
     |> assign(:form, %{
       windowsize: 10_000,
       selection: "Option 1"
     })
     |> assign(:windowsize, 10_000)
     |> assign(:sensor_id, "test1")
     |> assign(:attribute_id, "test2")
     |> assign(:sensor_ids, [1, 2, 3, 4, 5, 6])
     |> assign(:number, 10)}
  end

  # @impl true
  # def render_(assigns) do
  #   ~H"""
  #   <div class="grid gap-4 sm:gap-6 md:gap-8 lg:gap-10 xl:gap-12 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
  #     <div
  #       class="flex flex-col  rounded-lg shadow-md p-4 sm:p-6 md:p-8 lg:p-10 xl:p-12 cursor-pointer bg-dark-gray text-light-gray"
  #       class:col-span-2={true}
  #       class:row-span-2={true}
  #     >
  #       <div class="flex-1">
  #         <div class="font-bold text-orange sm:text-xl md:text-2xl mb-2">Test</div>
  #         <div class="text-sm sm:text-base mb-4 text-medium-gray">Test</div>
  #         <div class="h-24 sm:h-32 md:h-40 border border-dark-gray rounded-md bg-medium-gray"></div>
  #       </div>
  #       <div class="mt-4 sm:mt-6 md:mt-8 text-sm sm:text-base text-medium-gray">
  #         Test
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  @impl true
  @spec handle_event(<<_::104>>, map(), map()) :: {:noreply, map()}
  def handle_event("set_highlight", params, socket) do
    Logger.info("Received highlight event: #{inspect(params)}")

    updated_sensors =
      socket.assigns.sensors
      |> Map.new(fn {key, sensor} ->
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

  @impl true
  def handle_event("increment", _values, socket) do
    # This will increment the number when the increment events gets sent
    Logger.info("Incrementing number")
    {:noreply, assign(socket, :number, socket.assigns.number + 1)}
  end

  @impl true
  def handle_event("decrement", _values, socket) do
    # This will increment the number when the increment events gets sent
    Logger.info("Decrementing number")
    {:noreply, assign(socket, :number, socket.assigns.number - 1)}
  end

  @impl true
  def handle_event(
        "test",
        %{"windowsize" => windowsize} = params,
        socket
      ) do
    Logger.info("Received test event: #{inspect(params)}")

    {
      :noreply,
      socket
      |> assign(:windowsize, String.to_integer(windowsize))
      # |> assign(@form[:windowsize], String.to_integer(windowsize))
    }
  end

  @impl true
  def render(assigns) do
    ~V"""
    <script>
    import { onMount } from 'svelte';
    import { onDestroy } from 'svelte';

    let chartDiv;
    let chart;
    let sciChartSurface;
    let series;
    let data = []; // Initial ECG data (empty)
    let timer;

    // Default ECG data update interval (milliseconds)
    export let updateInterval = 10;

    // Function to update the chart data
    export function updateData(newData) {
    if (series) {
      data = newData;
      series.dataSeries.clear();
      series.dataSeries.appendRange(data.map((value, index) => index), data);
    }
    }

    onMount(async () => {
    // Load SciChart resources from CDN
    await loadSciChartResources();

    // Create the chart
    createChart();

    // Start the data update timer (optional)
    startTimer();
    });

    onDestroy(() => {
    // Dispose of the chart when the component unmounts
    disposeChart();

    // Stop the timer
    stopTimer();
    });

    async function loadSciChartResources() {
    const sciChartBaseUri = "https://cdn.jsdelivr.net/npm/scichart@3.3.401/"; // Replace with the desired SciChart version

    // Load scichart.js
    await loadScript(`${sciChartBaseUri}scichart.browser.js`);

    // Load scichart.wasm (if needed - check SciChart documentation)
    // You might need to adjust the path based on your SciChart version
    // await loadScript(`${sciChartBaseUri}scichart.wasm`);

    // Initialize SciChart (this is important!)
    SciChartSurface.useWasmFromCDN();
    }

    function loadScript(src) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
    }

    function createChart() {
    // JSON definition for the chart
    const chartDefinition = {
      "series": [
        {
          "type": "LineSeries",
          "options": {
            "stroke": "#50C7E0",
            "strokeThickness": 2,
            "dataSeries": {
              "type": "XyDataSeries",
              "options": {
                "xValues": [],
                "yValues": data,
                "metadata": { "seriesName": "ECG" }
              }
            }
          }
        }
      ],
      "chartOptions": {
        "title": "ECG Chart",
        "surface": {
          "padding": { "top": 10, "right": 10, "bottom": 10, "left": 10 },
          "xAxis": { "title": "Time" },
          "yAxis": { "title": "Amplitude" }
        },
        "licenseKey": "" // Replace with your SciChart license key (if applicable)
      }
    };

    // Create SciChartSurface from JSON
    SciChartSurface.create(chartDefinition, chartDiv)
      .then(surface => {
        sciChartSurface = surface;
        series = surface.series[0]; // Get the first series
      })
      .catch(err => console.error("Error creating SciChartSurface:", err));
    }

    function disposeChart() {
    if (sciChartSurface) {
      sciChartSurface.delete();
    }
    }

    function startTimer() {
    timer = setInterval(() => {
      // Simulate new ECG data (replace with your actual data source)
      const newData = Array.from({ length: 100 }, () => Math.sin(Date.now() / 100 + Math.random()) * 10);
      updateData(newData);
    }, updateInterval);
    }

    function stopTimer() {
    if (timer) {
      clearInterval(timer);
    }
    }
    </script>

    <div bind:this={chartDiv} style="width: 100%; height: 400px;"></div>
    """
  end

  # @impl true
  def _render(assigns) do
    ~H"""
    <!--<script defer phx-track-static type="text/javascript" src={~p"/assets/sparkline.js"}>
    </script>-->

    <.sidebar id="sidebar-left" variant="default" size="small" color="dark" hide_position="left">
      <div class="px-4 py-2">
        <h2 class="text-white">Menu</h2>
      </div>
    </.sidebar>

    <.speed_dial icon="hero-plus" space="large" icon_animated id="test-1" size="extra_small" clickable>
      <:item icon="hero-home" href="/examples/navbar" color="danger"></:item>
      <:item icon="hero-bars-3" href="/examples/navbar" variant="shadow" color="misc">11</:item>
      <:item icon="hero-chart-bar" href="/examples/navbar" variant="unbordered" color="warning">
      </:item>
    </.speed_dial>

    <!--{inspect(assigns)}-->

    <p>Window size: {@windowsize}ms</p>

    <.form for={@form} phx-change="test">
      <.range_field
        appearance="custom"
        value={@windowsize}
        color="warning"
        size="extra_small"
        min="1000"
        field={@form[:windowsize]}
        id="custom-range-1"
        max="60000"
        name="windowsize"
        step="500"
        phx-change="test"
        phx-value-sensor_id={@sensor_id}
        phx-value-attribute_id={@attribute_id}
      >
        <:range_value position="start">1sec</:range_value>
        <:range_value position="end">60sec</:range_value>
      </.range_field>

      <.group_radio
        variation="horizontal"
        field={@form[:selection]}
        name="selection"
        space="extrasmall"
      >
        <:radio value="option1">Option 1</:radio>
        <:radio value="option2">Option 2</:radio>
        <:radio value="option3">Option 3</:radio>
        <:radio value="option4" checked>Option 4</:radio>
      </.group_radio>

      <.radio_field
        name="selection"
        value="option1"
        space="medium"
        field={@form[:selection]}
        color="secondary"
        label="Option 1 Label"
        checked={@form[:selection] == "option1"}
      />

      <.radio_field
        name="selection"
        value="option2"
        space="medium"
        field={@form[:selection]}
        color="secondary"
        label="Option 2 Label"
        checked={@form[:selection] == "option2"}
      />

      <.radio_field
        name="selection"
        value="option3"
        space="medium"
        field={@form[:selection]}
        color="secondary"
        label="Option 3 Label"
        checked={@form[:selection] == "option3"}
      />

      <label for="windowsize">Window Size:</label>
      <input
        type="number"
        name="windowsize2"
        id="windowsize"
        value={@windowsize}
        min="1000"
        max="60000"
        step="500"
        phx-value-sensor_id={@sensor_id}
        phx-value-attribute_id={@attribute_id}
      />
      <button type="submit">Update</button>
    </.form>

    <input
      type="number"
      value={@windowsize}
      class="w-20"
      phx-keyup="test"
      phx-value-sensor_id={@sensor_id}
      phx-value-attribute_id={@attribute_id}
    />

    <div class="grid gap-4 sm:gap-6 md:gap-8 lg:gap-10 xl:gap-12 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
      <div
        :for={{id, sensor} <- @sensors}
        class="flex flex-col  rounded-lg shadow-md p-4 sm:p-6 md:p-8 lg:p-10 xl:p-12 cursor-pointer bg-dark-gray text-light-gray"
        style={
          if sensor.highlighted do
            "grid-column: span 2; grid-row: span 1;"
          else
            ""
          end
        }
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
    <div class="grid grid-cols-4 gap-4">
      <div class="col-span-1 bg-blue-200 p-4">1</div>
      <div class="col-span-2 bg-green-200 p-4">2</div>
      <div class="col-span-1 bg-red-200 p-4">3</div>
    </div>
    """
  end
end
