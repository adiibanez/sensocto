defmodule SensoctoWeb.Components.SensorTypes.ECGComponent do
  use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    ~H"""
    <div>
      <p class="font-bold">
        {assigns.sensor_data.connector_name}:{assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
      </p>
      <p class="text-sm text-gray-500">{assigns.sensor_data.timestamp_formated}</p>

      <sensocto-sparkline
        width="200"
        height="50"
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.id}
        maxlength="400"
        phx-update="ignore"
        class="loading"
      >
      </sensocto-sparkline>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HeartrateComponent do
  use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    ~H"""
    <div>
      <p class="font-bold">
        {assigns.sensor_data.connector_name}:{assigns.sensor_data.sensor_name}:{assigns.sensor_data.sensor_type}
      </p>
      <p class="text-sm text-gray-500">{assigns.sensor_data.timestamp_formated}</p>

      <sensocto-sparkline
        width="200"
        height="50"
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        sensor_id={assigns.sensor_data.id}
        maxlength="400"
        phx-update="ignore"
        class="loading"
      >
      </sensocto-sparkline>
    </div>
    """
  end
end
