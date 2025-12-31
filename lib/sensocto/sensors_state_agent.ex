defmodule SensorsStateAgent do
  alias Sensocto.SensorArrangement
  use Agent
  require Logger

  def start_link(_params) do
    configuration = get_default_config()

    Logger.debug("SensorsStateAgent start_link2: #{inspect(configuration)}")
    # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
    Agent.start_link(
      fn ->
        create_state_from_config(configuration)
      end,
      name: :sensors_state_agent
    )
  end

  def get_default_config() do
    %{
      :number_of_sensors => 40,
      :sensors_per_row => 20,
      :shrink_factor => 0.8,
      :z_offset_per_row => 0.15,
      :rotation => 0.0,
      :width => 25,
      :height => 25,
      :depth => 25,
      :scale => 0.7,
      :x_min => -0.8,
      :x_max => 0.8,
      :y_min => -1.5,
      :y_max => 0.3,
      :z_amplitude => -1.5,
      :z_offset => 0.1,
      :size => 0.1
    }
  end

  def get_form_defaults() do
    %{
      :sensor => %{
        :translation_x => %{:min => "-0.5", :max => "0.5", :step => "0.01"},
        :translation_y => %{:min => "-0.5", :max => "0.5", :step => "0.01"},
        :translation_z => %{:min => "-0.5", :max => "0.5", :step => "0.01"}
      },
      :config => %{
        :number_of_sensors => %{
          :min => 5,
          :max => 200,
          :step => 1
        },
        :size => %{
          min: 0.02,
          max: 1,
          step: 0.001
        },
        :x_min => %{
          min: -1.0,
          max: 1.0,
          step: 0.01
        },
        :x_max => %{
          min: -0.8,
          max: 0.8,
          step: 0.01
        },
        :y_min => %{
          min: -2,
          max: 0.5,
          step: 0.01
        },
        :y_max => %{
          min: -2.0,
          max: 0.5,
          step: 0.01
        },
        :z_amplitude => %{
          min: -1.5,
          max: 1.5,
          step: 0.01
        },
        :z_offset => %{
          min: -1,
          max: 1,
          step: 0.01
        }
      }
    }
  end

  def get_colors() do
    Agent.get(:sensors_state_agent, fn state ->
      get_in(state, [:colors])
    end)
  end

  def put_sensor(sensor_id, payload) do
    Agent.update(:sensors_state_agent, fn state ->
      update_in(state, [:sensors, sensor_id], fn _sensor ->
        # Logger.debug("Updating sensor: Old: #{inspect(sensor)} New: #{inspect(payload)}")
        payload
      end)
    end)
  end

  def put_attribute(sensor_id, attribute, payload) do
    Agent.update(:sensors_state_agent, fn state ->
      update_in(state, [:sensors, sensor_id, attribute], fn _attribute ->
        # Logger.debug("Updating attribute: Old: #{inspect(attribute)} New: #{inspect(payload)}")
        payload
      end)
    end)
  end

  def get_attribute(sensor_id, attribute) do
    Agent.get(:sensors_state_agent, fn state ->
      get_in(state, [:sensors, sensor_id, attribute])
    end)
  end

  def get_sensor(sensor_id) do
    Agent.get(:sensors_state_agent, fn state ->
      get_in(state, [:sensors, sensor_id])
    end)
  end

  def get_state() do
    # Agent.get(:sensors_state_agent, & &1)

    Agent.get(:sensors_state_agent, fn state ->
      get_in(state, [:sensors])
    end)

    # |> dbg()
  end

  def reset(config) do
    # Logger.debug("Agent reset config #{inspect(config)}")

    Agent.update(:sensors_state_agent, fn _state ->
      create_state_from_config(config)
    end)
  end

  # defp via_tuple(sensor_id) do
  #   # Sensocto.RegistryUtils.via_dynamic_registry(Sensocto.SimpleAttributeRegistry, sensor_id)

  #   {:via, Registry, {Sensor, sensor_id}}
  # end

  defp create_state_from_config(config) do
    %{
      :sensors => SensorArrangement.get_initial_sensors(config),
      :colors => SensorArrangement.get_colors(config[:number_of_sensors])
    }
  end
end

defmodule Sensocto.SensorArrangement do
  require Logger

  @colors [
    "red",
    "green",
    "blue",
    "orange",
    "yellow",
    "pink",
    "purple",
    "teal",
    "indigo",
    "brown",
    "gray"
    # "gray2",
    # "gray3",
    # "gray4",
    # "gray5",
    # "gray6",
    # "label"
    # "secondarylabel",
    # "tertiarylabel",
    # "quaternarylabel",
    # "fill",
    # "secondarysystemfill",
    # "tertiarysystemfill",
    # "quaternarysystemfill",
    # "placeholdertext"
  ]

  def get_colors_(number \\ 100) do
    generate_rgb_colors(number)
  end

  def get_colors(_) do
    @colors
  end

  @doc """
  Arranges sensors in multiple rows with denser edges, adjusts size based on row count, and stacks in Z.

  Args:
    config: Configuration map.
      - `number_of_sensors`: Total number of sensors.
      - `sensors_per_row`: Maximum sensors per row (optional, defaults to 10).
      - `x_min`: Minimum X coordinate (optional, defaults to -0.3).
      - `x_max`: Maximum X coordinate (optional, defaults to 0.3).
      - `y_min`: Minimum Y coordinate (optional, defaults to -0.1).
      - `y_max`: Maximum Y coordinate (optional, defaults to 0.2).
      - `z_amplitude`: Z amplitude (optional, defaults to 0.25).
      - `z_offset`: Random Z position offset (optional, defaults to 0.0).
      - `z_offset_per_row`: Z spacing between rows (optional, defaults to 0.3).
      - `rotation_randomize`: Random rotation adjust.
      - `size`: Base size.
      - `base_size`: Base value of size.
      - `row_size_factor`: Amount to multiply size by for every sensor in a row.
      - `size_row_offset`: Additional size value for each row.
      - `edge_density_factor`: Higher value for more density.
      - `shrink_factor`: Percentage to shrink X and Y bounds on each new row (optional, defaults to 0.8).
      - `arc_intensity`: Power of the arc on sensors curve.

  Returns:
    A map where keys are sensor IDs and values are sensor properties.
  """
  @spec get_initial_sensors(map()) :: map()
  def get_initial_sensors(config) do
    number_of_sensors = config[:number_of_sensors]
    sensors_per_row = config[:sensors_per_row] || 10
    x_min = config[:x_min] || -0.3
    x_max = config[:x_max] || 0.3
    y_min = config[:y_min] || -0.1
    y_max = config[:y_max] || 0.2
    z_amplitude = config[:z_amplitude] || 0.25
    z_offset = config[:z_offset] || 0.0
    rotation_randomize = config[:rotation_randomize] || 0.2

    base_size = config[:base_size] || 0.03
    row_size_factor = config[:row_size_factor] || 0.002
    size_row_offset = config[:size_row_offset] || 0.01
    edge_density_factor = config[:edge_density_factor] || 3.0
    _size = config[:size] || 0.05

    shrink_factor = config[:shrink_factor] || 0.8
    z_offset_per_row = config[:z_offset_per_row] || 0.3
    arc_intensity = config[:arc_intensity] || 1.0

    Enum.map(get_sensors_from_number(number_of_sensors), fn sensor_num ->
      row = div(sensor_num - 1, sensors_per_row)
      sensor_index_in_row = rem(sensor_num - 1, sensors_per_row)

      # Density and Size modifications
      # Normalize the sensor number to a value between -1 and 1. Higher edge_density_factor values means it will be denser.
      d = sensor_index_in_row / max(1, sensors_per_row - 1) * 2.0 - 1.0

      # Shape the distribution to be denser on the edges by taking it to a power
      edge_t = d / 2

      edge_t =
        cond do
          d < 0 -> -pow(-edge_t, edge_density_factor)
          true -> pow(edge_t, edge_density_factor)
        end

      edge_t = edge_t * 2

      # Size calculation
      final_size =
        base_size + Float.floor(sensors_per_row / 2) * row_size_factor -
          edge_t * size_row_offset

      # Shrink
      current_shrink_factor = pow(shrink_factor, row)

      current_x_min = x_min * current_shrink_factor
      current_x_max = x_max * current_shrink_factor
      current_y_min = y_min * current_shrink_factor
      current_y_max = y_max * current_shrink_factor

      # Normalize
      t = max(0, sensor_index_in_row) / max(1, min(number_of_sensors - 1, sensors_per_row - 1))

      # Y: Create an elliptic arc within y_min..y_max
      # Center the arc vertically
      y_center = (current_y_min + current_y_max) / 2
      # Amplitude of the arc (half the height)
      y_amplitude = (current_y_max - current_y_min) / 2
      # Position on the semi-circle with arc shaping
      angle = t * :math.pi()
      # Arc
      sensor_y = y_center + y_amplitude * pow(:math.sin(angle), arc_intensity)

      sensor_x = current_x_min + t * (current_x_max - current_x_min)

      sensor_z =
        row * z_offset_per_row + z_amplitude * :math.sin(:math.pi() * t) +
          :rand.uniform(max(1, round(z_offset * 10))) / 10

      sensor_id = "Connector#{sensor_num}"

      vector_rotation = %{
        x: 1.0,
        y: 0.0,
        z: 0.0,
        angle: :rand.uniform(max(1, round(rotation_randomize * 100))) / 100
      }

      %{
        sensor_id => %{
          :size => get_rounded_float(final_size),
          :translation => %{
            :x => get_rounded_float(sensor_x),
            :y => get_rounded_float(sensor_y),
            :z => get_rounded_float(sensor_z)
          },
          :rotation => vector_rotation,
          :color => get_sensor_color(sensor_num),
          :attributes => %{
            "heartrate" => %{
              :timestamp => "2021-03-08T14:39:36Z"
            }
          }
        }
      }
    end)
    |> Enum.reduce(&Map.merge(&1, &2))
  end

  defp pow(base, exponent) do
    :math.pow(base, exponent)
  end

  def get_sensor_color(sensor_number) do
    num_colors = Enum.count(@colors)
    color_index = rem(sensor_number - 1, num_colors)
    Enum.at(@colors, color_index)
  end

  defp get_sensors_from_number(number_of_sensors) do
    if number_of_sensors > 1 do
      Enum.map(1..number_of_sensors, fn n -> n end)
    else
      [1]
    end
  end

  def generate_rgb_colors(count) do
    Enum.map(1..count, fn _ ->
      r = :rand.uniform()
      g = :rand.uniform()
      b = :rand.uniform()
      [r, g, b]
    end)
  end

  defp get_rounded_float(float_value) do
    round(float_value * 1000.0) / 1000.0
  end
end
