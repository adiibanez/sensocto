defmodule SensoctoWeb.Live.BaseComponents do
  use Phoenix.Component
  require Logger

  use Gettext,
    backend: SensoctoWeb.Gettext

  def render_sensor_header(assigns) do
    ~H"""
    <div class="m-0 p-2">
      <p class="font-bold text-s">
        {@sensor.sensor_name}
      </p>
      <p>Type: {@sensor.sensor_type}</p>
    </div>
    """
  end
end
