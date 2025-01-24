defmodule SensoctoWeb.Components.SensorTypes.EcgSensorComponent do
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
          {assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
        </p>
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
        sensor_id={assigns.sensor_data.sensor_id}
        samplingrate={assigns.sensor_data.sampling_rate}
        phx-update="ignore"
        class="loading w-full m-0 p-0"
        width="500"
        height="250"
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
          {assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
        </p>
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

      <sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.sensor_data.sensor_id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="500"
        timemode="absolute"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>
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
    ~H"""
    <div class="m-0 p-0">
      <div class="m-0 p-2">
        <p class="font-bold text-s">
          {assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
        </p>
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

      <sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.sensor_data.sensor_id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>
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
          {assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
        </p>
        <p class="text-xs text-gray-500">{assigns.sensor_data.timestamp_formated}</p>
        <p class="text-xs hidden">Conn: {assigns.sensor_data.connector_name}</p>
        <p class="text-xs">Payload: {assigns.sensor_data.payload}</p>
      </div>
    </div>
    """
  end
end
