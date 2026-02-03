defmodule Sensocto.AI.SensorContext do
  @moduledoc """
  Builds context from sensor data for LLM prompts.

  Transforms sensor readings into natural language context that can be
  included in prompts to help the AI understand the current state of
  the sensor network.
  """

  alias Sensocto.Sensors.Sensor

  @doc """
  Build a text summary of current sensor state.

  ## Options

    * `:sensor_ids` - List of specific sensor IDs to include
    * `:limit` - Maximum number of sensors to include (default: 10)
    * `:include_values` - Include recent values (default: true)
  """
  def build_context(opts \\ []) do
    sensor_ids = Keyword.get(opts, :sensor_ids)
    limit = Keyword.get(opts, :limit, 10)
    include_values = Keyword.get(opts, :include_values, true)

    sensors = fetch_sensors(sensor_ids, limit)

    if Enum.empty?(sensors) do
      "No sensors currently available."
    else
      build_sensor_summary(sensors, include_values)
    end
  end

  @doc """
  Build context for a specific sensor by ID.
  """
  def build_sensor_context(sensor_id) when is_binary(sensor_id) do
    case fetch_sensor(sensor_id) do
      nil -> "Sensor not found."
      sensor -> format_sensor(sensor, true)
    end
  end

  @doc """
  Build a system prompt that includes sensor context.
  """
  def system_prompt_with_context(base_prompt, opts \\ []) do
    context = build_context(opts)

    """
    #{base_prompt}

    ## Current Sensor Data

    #{context}
    """
  end

  # Private helpers

  defp fetch_sensors(nil, limit) do
    case Ash.read(Sensor, page: [limit: limit]) do
      {:ok, %{results: sensors}} -> sensors
      {:ok, sensors} when is_list(sensors) -> Enum.take(sensors, limit)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp fetch_sensors(sensor_ids, _limit) when is_list(sensor_ids) do
    sensor_ids
    |> Enum.map(&fetch_sensor/1)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_sensor(sensor_id) do
    case Ash.get(Sensor, sensor_id) do
      {:ok, sensor} -> sensor
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp build_sensor_summary(sensors, include_values) do
    sensor_count = length(sensors)

    header = "Currently monitoring #{sensor_count} sensor(s):\n"

    sensor_lines =
      sensors
      |> Enum.with_index(1)
      |> Enum.map(fn {sensor, idx} ->
        "#{idx}. #{format_sensor(sensor, include_values)}"
      end)
      |> Enum.join("\n")

    header <> sensor_lines
  end

  defp format_sensor(sensor, include_values) do
    name = sensor.name || "Unknown"
    type = get_sensor_type(sensor)
    mac = sensor.mac_address

    base = "#{name} (#{type})"
    base = if mac, do: "#{base} [MAC: #{mac}]", else: base

    if include_values do
      attributes = get_sensor_attributes(sensor)

      if Enum.empty?(attributes) do
        base
      else
        attr_text =
          attributes
          |> Enum.map(&format_attribute/1)
          |> Enum.join(", ")

        "#{base} - #{attr_text}"
      end
    else
      base
    end
  end

  defp get_sensor_type(sensor) do
    cond do
      sensor.sensor_type_rel -> sensor.sensor_type_rel.name
      sensor.sensor_type_id -> "Type ID: #{sensor.sensor_type_id}"
      true -> "generic"
    end
  rescue
    _ -> "generic"
  end

  defp get_sensor_attributes(sensor) do
    case sensor.attributes do
      %Ash.NotLoaded{} -> []
      attributes when is_list(attributes) -> attributes
      _ -> []
    end
  rescue
    _ -> []
  end

  defp format_attribute(attr) do
    id = attr.attribute_id || "unknown"
    values = attr.values || %{}

    case values do
      %{"values" => [latest | _]} when is_number(latest) ->
        "#{id}: #{latest}"

      %{"values" => [latest | _]} ->
        "#{id}: #{inspect(latest)}"

      _ ->
        id
    end
  end
end
