defmodule SensoctoWeb.Components.SensorTypes.EcgSensorComponent do
  alias SensoctoWeb.Components.SensorTypes.BaseComponent
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  import SensoctoWeb.Live.BaseComponents
  alias SensoctoWeb.Live.BaseComponents
  require Logger

  def mount(_params, _session, socket) do
    IO.puts("test")
  end

  def render(assigns) do
    ~H"""
    <div class="m-2 p-2">
      <div class="m-0 p-2">
        <p class="font-bold text-s">
          {assigns.sensor_data.sensor_name}
        </p>
        <p>Type: {assigns.sensor_data.sensor_type}</p>
        <p class="text-xs text-gray-500">{assigns.sensor_data.timestamp_formated}</p>
        <p class="text-xs hidden">Conn: {assigns.sensor_data.connector_name}</p>
        <button
          class="btn"
          phx-click="clear-attribute"
          phx-value-sensor_id={assigns.sensor_data.sensor_id}
          phx-value-attribute_id={assigns.sensor_data.attribute_id}
        >
          Clear
        </button>
      </div>

      <sensocto-ecg-visualization
        is_loading="true"
        id={ "ecg-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        phx-update="ignore"
        class="loading w-full m-0 p-0 resizeable"
        color="#ffc107"
        backgroundColor="transparent"
        highlighted_areas='{[
      {start: 250, end: 500, color: "lightgreen"},
      {start: 800, end: 1200, color: "lightgreen"},
      {start: 900, end: 1000, color: "red"},
     {start: 1400, end: 1600, color: "brown"}
    ]}'
      >
      </sensocto-ecg-visualization>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HighSamplingRateSensorComponent do
  alias SensoctoWeb.Components.SensorTypes.BaseComponent
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def mount(_params, _session, socket) do
    IO.puts("test")
  end

  def render(assigns) do
    ~H"""
    <div class="m-2 p-2">
      <div class="m-0 p-2">
        <p class="font-bold text-s">
          {assigns.sensor_data.sensor_name}
        </p>
        <p>Type: {assigns.sensor_data.sensor_type}</p>
        <p class="text-xs text-gray-500">{assigns.sensor_data.timestamp_formated}</p>
        <p class="text-xs hidden">Conn: {assigns.sensor_data.connector_name}</p>
        <button
          class="btn"
          phx-click="clear-attribute"
          phx-value-sensor_id={assigns.sensor_data.sensor_id}
          phx-value-attribute_id={assigns.sensor_data.attribute_id}
        >
          Clear
        </button>
      </div>
      
    <!--<sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="500"
        timemode="absolute"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>-->

      <sensocto-chartjs
        width="300"
        height="30"
        color="#ffc107"
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="absolute"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-chartjs>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HeartrateComponent do
  alias SensoctoWeb.Components.SensorTypes.BaseComponent
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    import SensoctoWeb.Live.BaseComponents

    ~H"""
    <div class="m-0 p-0">
      <!--<sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="relative"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>-->

      <!--<sensocto-chartjs
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="relative"
        phx-update="ignore"
        class="resizeable loading w-full m-0 p-0"
      >
      </sensocto-chartjs>
      -->

      <sensocto-sparkline-wasm-svelte
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="relative"
        phx-update="ignore"
        class="resizeable loading w-full m-0 p-0"
      >
      </sensocto-sparkline-wasm-svelte>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.GenericSensorComponent do
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    ~H"""
    <div class="m-0 p-0">
      <div class="m-0 p-2">
        <p class="font-bold text-s">
          {assigns.sensor_data.sensor_name}
        </p>
        <p>Type: {assigns.sensor_data.sensor_type}</p>
        <p class="text-xs text-gray-500">{assigns.sensor_data.timestamp_formated}</p>
        <p class="text-xs hidden">Conn: {assigns.sensor_data.connector_name}</p>
        {render_payload(assigns.sensor_data.payload, assigns)}
      </div>
    </div>
    """
  end

  defp render_payload(payload, assigns) do
    try do
      case Jason.decode(payload) do
        {:ok, %{} = json_obj} ->
          # Render JSON object
          output =
            Enum.map(json_obj, fn {key, value} ->
              "#{String.capitalize(inspect(key))}: #{inspect(value)}\n"
            end)
            |> Enum.join("")

          ~H"<pre>{output}</pre>"

        _ ->
          # Render single value
          ~H"<p>#{inspect(payload)}</p>"
      end
    rescue
      Jason.DecodeError ->
        Logger.debug("Could not decode payload: #{inspect(payload)}")
        ~H"<p>#{inspect(payload)}</p>"

      _ ->
        Logger.error("Could not decode payload: #{inspect(payload)}")
        ~H"<p>#{inspect(payload)}</p>"
    end
  end
end
