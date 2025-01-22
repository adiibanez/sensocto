defmodule SensoctoWeb.Components.SensorTypes.HighSamplingRateSensorComponent do
  #use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def mount(_params, _session, socket) do
    IO.puts("test");
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
      </div>

      <sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.sensor_data.id}
        maxlength={assigns.sensor_data.sampling_rate * 5}
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HeartrateComponent do
  #use SensoctoWeb, :live_view
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
      </div>

      <sensocto-sparkline
        width="200"
        height="50"
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.sensor_data.id}
        maxlength={assigns.sensor_data.sampling_rate * 60}
        phx-update="ignore"
        class="loading"
      >
      </sensocto-sparkline>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.GenericSensorComponent do
  #use SensoctoWeb, :live_view
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
