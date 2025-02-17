defmodule SensoctoWeb.Live.Components.ControllerComponents do
  use Phoenix.Component

  attr :config, :map, doc: "Sensor config data"
  attr :defaults, :map, doc: "Default values for min, max, step"
  attr :label, :string
  attr :field_name, :string
  attr :value, :integer

  def sensor_range_field(assigns) do
    ~H"""
    <label for="#{@field_name}">config.{@field_name}</label>
    <input
      name={@field_name}
      type="range"
      value={@value}
      min={@defaults.min}
      max={@defaults.max}
      step={@defaults.step}
      phx-value={@value}
    /> {@value}
    """
  end

  attr :config, :map, doc: "Sensor config data"
  attr :defaults, :map, doc: "Default values for min, max, step"

  def controller_config_form(assigns) do
    ~H"""
    <form phx-change="config_sensors" phx-debounce="1000">
      <input type="submit" value="Update sensors" />
      <ul>
        <li>
          <.sensor_range_field
            field_name="width"
            value={@config.width}
            defaults={%{min: 1, max: 25, step: 0.01}}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="height"
            value={@config.height}
            defaults={%{min: 1, max: 25, step: 0.01}}
          />
        </li>

        <li>
          <.sensor_range_field
            field_name="scale"
            value={@config.scale}
            defaults={%{min: 0.1, max: 1, step: 0.01}}
          />
        </li>

        <li>
          <.sensor_range_field
            field_name="depth"
            value={@config.depth}
            defaults={%{min: 1, max: 25, step: 0.01}}
          />
        </li>

        <li>
          <.sensor_range_field
            field_name="rotation"
            value={@config.rotation}
            defaults={%{min: 0, max: 1, step: 0.01}}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.number_of_sensors"
            value={@config.number_of_sensors}
            defaults={@defaults.config.number_of_sensors}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.size"
            value={@config.size}
            defaults={@defaults.config.size}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.x_min"
            value={@config.x_min}
            defaults={@defaults.config.x_min}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.x_max"
            value={@config.x_max}
            defaults={@defaults.config.x_max}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.y_min"
            value={@config.y_min}
            defaults={@defaults.config.y_min}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.y_max"
            value={@config.y_max}
            defaults={@defaults.config.y_max}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.z_amplitude"
            value={@config.z_amplitude}
            defaults={@defaults.config.z_amplitude}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="config.z_offset"
            value={@config.z_offset}
            defaults={@defaults.config.z_offset}
          />
        </li>
      </ul>
    </form>
    """
  end
end
