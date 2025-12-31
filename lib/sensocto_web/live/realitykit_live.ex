defmodule SensoctoWeb.RealitykitLive do
  alias Phoenix.PubSub
  use SensoctoWeb, :live_view
  # LVN_ACTIVATION use SensoctoNative, :live_view
  require Logger
  import SensoctoWeb.Live.Components.ControllerComponents

  @colors ["red", "green", "blue", "black", "yellow", "orange"]

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def mount(_params, _session, socket) do
    PubSub.subscribe(Sensocto.PubSub, "sensors_realitykit")

    {:ok,
     assign(
       socket,
       sensors: SensorsStateAgent.get_state(),
       colors: SensorsStateAgent.get_colors(),
       config: SensorsStateAgent.get_default_config(),
       defaults: SensorsStateAgent.get_form_defaults(),
       counter: 0
     )}
  end

  @spec handle_event(<<_::64, _::_*8>>, any(), any()) :: {:noreply, any()}
  def handle_event(
        "update_sensor",
        %{
          "sensor_id" => sensor_id,
          "color" => color,
          "size" => size,
          "translation.x" => translation_x,
          "translation.y" => translation_y,
          "translation.z" => translation_z,
          "rotation_axis" => rotation_axis,
          "rotation_angle" => rotation_angle
        } = _params,
        socket
      ) do
    SensorsStateAgent.put_attribute(sensor_id, :color, color)
    SensorsStateAgent.put_attribute(sensor_id, :size, get_rounded_float(size))

    SensorsStateAgent.put_attribute(sensor_id, :translation, %{
      x: get_rounded_float(translation_x),
      y: get_rounded_float(translation_y),
      z: get_rounded_float(translation_z)
    })

    {rx, ry, rz} =
      case rotation_axis do
        "x" -> {1.0, 0.0, 0.0}
        "y" -> {0.0, 1.0, 0.0}
        "z" -> {0.0, 0.0, 1.0}
        # Default
        _ -> {0.0, 0.0, 0.0}
      end

    {rx_normalized, ry_normalized, rz_normalized} =
      Sensocto.Vector.normalize({rx, ry, rz})

    SensorsStateAgent.put_attribute(sensor_id, :rotation, %{
      x: rx_normalized,
      y: ry_normalized,
      z: rz_normalized,
      angle: get_rounded_float(rotation_angle)
    })

    PubSub.broadcast(Sensocto.PubSub, "sensors_realitykit", {
      :update_sensor,
      %{
        :sensor_id => sensor_id
      }
    })

    {:noreply,
     assign(
       socket,
       sensors: SensorsStateAgent.get_state(),
       counter: socket.assigns.counter + 1
     )}
  end

  defp get_rounded_float(str_value) do
    {float_value, _} = Float.parse(str_value)
    round(float_value * 1000.0) / 1000.0
  end

  def handle_event(
        "config_sensors",
        %{
          "_target" => _target,
          "rotation" => rotation,
          "scale" => scale,
          "width" => width,
          "height" => height,
          "depth" => depth,
          "config.number_of_sensors" => number_of_sensors,
          "config.x_max" => x_max,
          "config.x_min" => x_min,
          "config.y_max" => y_max,
          "config.y_min" => y_min,
          "config.z_amplitude" => z_amplitude,
          "config.z_offset" => z_offset,
          "config.size" => size
        } = params,
        socket
      ) do
    Logger.debug("config_sensors #{inspect(params)}")

    {number_int, _} = Integer.parse(number_of_sensors)

    new_config = %{
      :number_of_sensors => number_int,
      :rotation => get_rounded_float(rotation),
      :scale => get_rounded_float(scale),
      :width => get_rounded_float(width),
      :height => get_rounded_float(height),
      :depth => get_rounded_float(depth),
      :x_min => get_rounded_float(x_min),
      :x_max => get_rounded_float(x_max),
      :y_min => get_rounded_float(y_min),
      :y_max => get_rounded_float(y_max),
      :z_offset => get_rounded_float(z_offset),
      :z_amplitude => get_rounded_float(z_amplitude),
      :size => get_rounded_float(size)
    }

    SensorsStateAgent.reset(new_config)

    PubSub.broadcast(Sensocto.PubSub, "sensors_realitykit", :config_sensors)

    {:noreply,
     assign(
       socket,
       sensors: SensorsStateAgent.get_state(),
       config: new_config,
       counter: socket.assigns.counter + 1
     )}
  end

  def handle_event("test_event_realitykit", params, socket) do
    Logger.debug("test_event_realitykit #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("test-event2", params, socket) do
    Logger.debug("Gesture #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("reset_sensors", %{"number_of_sensors" => number_of_sensors} = params, socket) do
    {number_of_sensors_int, _} = Integer.parse(number_of_sensors)
    SensorsStateAgent.reset(%{:number_of_sensors => number_of_sensors_int})
    {:noreply, socket}
  end

  def handle_info(
        {:update_sensor, %{:sensor_id => sensor_id}} =
          params,
        socket
      ) do
    Logger.debug("Received broadcast: PID: #{inspect(self())} #{inspect(params)}")

    {:noreply,
     assign(socket,
       sensors: SensorsStateAgent.get_state(),
       config: socket.assigns.config,
       counter: socket.assigns.counter + 1
     )}
  end

  def handle_info(
        :config_sensors,
        socket
      ) do
    Logger.debug("Received broadcast: PID: #{inspect(self())} :config_sensors")

    {:noreply,
     assign(socket,
       sensors: SensorsStateAgent.get_state(),
       config: socket.assigns.config,
       counter: socket.assigns.counter + 1
     )}
  end

  def render(assigns) do
    Logger.debug("Live pid: #{inspect(self())}")

    ~H"""
    <h2>Realitykit html view</h2>
    Logger.debug("Rotation #{assigns.config.rotation}") {inspect(assigns.config.rotation)}

    <.controller_config_form config={@config} defaults={@defaults}></.controller_config_form>

    <form
      :for={{sensor_id, sensor} <- @sensors}
      id={"form-#{sensor_id}"}
      phx-debounce="300"
      phx-change="update_sensor"
      phx-value-sensor_id={sensor_id}
    >
      <strong>Sensor: {sensor_id}</strong>
      <ul>
        <li>
          <label style={"background-color:#{sensor.color}"} for="color">Color</label>

          {inspect(@colors)}

          <select name="color">
            <option :for={color <- @colors} value={color} selected={sensor.color == color}>
              {color}
            </option>
          </select>

          <.sensor_range_field field_name="size" value={sensor.size} defaults={@defaults.config.size} />
        </li>

        <li>
          <strong>Rotation:</strong>
          <label>
            <input
              type="radio"
              name="rotation_axis"
              value="x"
              checked
              checked={sensor.rotation.x == 1.0}
            /> X
          </label>
          <label>
            <input type="radio" name="rotation_axis" value="y" checked={sensor.rotation.y == 1.0} /> Y
          </label>
          <label>
            <input type="radio" name="rotation_axis" value="z" checked={sensor.rotation.z == 1.0} /> Z
          </label>
          <label for="rotation_angle">Angle</label>
          <input
            name="rotation_angle"
            type="range"
            value={sensor.rotation.angle}
            min="-1"
            max="1"
            step="0.001"
            phx-value={sensor.rotation.angle}
          />
          {sensor.rotation.angle}
        </li>
        <li>
          <.sensor_range_field
            field_name="translation.x"
            value={sensor.translation.x}
            defaults={@defaults.sensor.translation_x}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="translation.y"
            value={sensor.translation.y}
            defaults={@defaults.sensor.translation_y}
          />
        </li>
        <li>
          <.sensor_range_field
            field_name="translation.z"
            value={sensor.translation.z}
            defaults={@defaults.sensor.translation_z}
          />
        </li>
      </ul>
    </form>
    """
  end
end

defmodule Sensocto.Vector do
  @doc """
  Normalizes a 3D vector (represented as a tuple) so its magnitude is 1.
  """
  def normalize({x, y, z}) do
    magnitude = :math.sqrt(x * x + y * y + z * z)
    # Avoid division by zero
    if magnitude > 0 do
      {
        # round to 3 decimal places
        round(x / magnitude * 1000) / 1000,
        round(y / magnitude * 1000) / 1000,
        round(z / magnitude * 1000) / 1000
      }
    else
      # Handle the case where the vector is (0, 0, 0)
      {0.0, 0.0, 0.0}
    end
  end
end
