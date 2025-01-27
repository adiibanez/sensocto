defmodule SensoctoWeb.Live.Components.ViewData do
  alias Timex.DateTime
  import String, only: [replace: 3]
  alias Jason

  alias Timex.DateTime
  import String, only: [replace: 3]

  def merge_sensor_data(sensors, sensor_data) do
    # existing_data = Map.get(sensors, :result, %{})
    # IO.inspect(existing_data, label: "Existing sensors async_assign data")

    new_data_updated = update_sensor_data(sensors, sensor_data)

    new_data_async_assign =
      Map.merge(sensors, new_data_updated)
      |> Enum.reduce(%{}, fn {sensor_id, sensor_data}, acc ->
        Map.put(
          acc,
          sensor_id,
          Map.put(
            sensor_data,
            :viewdata,
            generate_sensor_view_data(sensor_id, sensor_data)
          )
        )
      end)

    # IO.inspect(new_data_async_assign, label: "New sensors async_assign data")
  end

  def update_sensor_data(sensors, sensor_data) do
    sensor_id = Map.get(sensor_data, :sensor_id)
    sensor_id_string = to_string(sensor_id)

    updated_sensors =
      Enum.map(sensors, fn {key, value} ->
        if key == sensor_id_string do
          updated_attributes =
            Map.get(value, :attributes, %{})
            |> Map.put(Map.get(sensor_data, :uuid), [
              %{
                timestamp: Map.get(sensor_data, :timestamp),
                payload: Map.get(sensor_data, :payload)
              }
            ])

          {key, Map.put(value, :attributes, updated_attributes)}
        else
          {key, value}
        end
      end)

    Map.new(updated_sensors)
  end

  def update_view_data(sensors, sensor_id, attribute_id) do
    sensor_id_string = to_string(sensor_id)

    Enum.reduce(sensors, %{}, fn {key, value}, acc ->
      if key == sensor_id_string do
        updated_sensor =
          Map.put(value, :viewdata, generate_sensor_view_data(key, value))

        Map.put(acc, key, updated_sensor)
      else
        Map.put(acc, key, value)
      end
    end)
  end

  def update_sensor(sensors, attribute_update) do
    sensor_id_string =
      attribute_update
      |> Map.get("sensor_id", Map.get(attribute_update, :sensor_id))
      |> to_string()

    Enum.map(sensors, fn sensor ->
      case Map.get(sensor, sensor_id_string) do
        nil ->
          sensor

        sensor_data ->
          updated_attributes =
            sensor_data
            |> Map.get(:attributes, %{})
            |> Map.update(
              Map.get(attribute_update, :attribute_id),
              fn attribute_values ->
                [Map.drop(attribute_update, [:attribute_id, :sensor_id]) | attribute_values]
              end,
              [Map.drop(attribute_update, [:attribute_id, :sensor_id])]
            )

          Map.put(sensor, sensor_id_string, Map.put(sensor_data, :attributes, updated_attributes))
      end
    end)
  end

  def generate_view_data(sensors) when is_map(sensors) do
    sensors
    |> Enum.reduce(%{}, fn {sensor_id, sensor_data}, acc ->
      view_data = generate_sensor_view_data(sensor_id, sensor_data)
      Map.put(acc, sensor_id, Map.put(sensor_data, :viewdata, view_data))
    end)
  end

  def generate_sensor_view_data(sensor_id, sensor_data) do
    attributes = Map.get(sensor_data, :attributes, %{})

    Enum.reduce(attributes, %{}, fn {attribute_id, attribute_values}, acc ->
      view_data =
        generate_single_view_data(sensor_id, attribute_id, attribute_values, sensor_data)

      Map.put(acc, attribute_id, view_data)
    end)
  end

  def generate_single_view_data(sensor_id, attribute_id, attribute_values, sensor_data) do
    metadata = Map.get(sensor_data, :metadata, %{})

    attribute_values
    |> Enum.reduce(%{}, fn attribute_value, _acc ->
      timestamp = Map.get(attribute_value, :timestamp)

      timestamp_formatted =
        try do
          case timestamp do
            nil ->
              "Invalid Date"

            timestamp ->
              timestamp
              |> Kernel./(1000)
              |> Timex.from_unix()
              |> Timex.to_string()
          end
        rescue
          _ ->
            "Invalid Date"
        end

      %{
        # liveview streams id, remove : for document.querySelector compliance
        id: "#{sensor_id}_#{attribute_id}",
        payload: Map.get(attribute_value, :payload),
        timestamp: timestamp,
        timestamp_formated: timestamp_formatted,
        attribute_id: attribute_id,
        sensor_id: Map.get(metadata, :sensor_id),
        sensor_name: Map.get(metadata, :sensor_name),
        sensor_type: Map.get(metadata, :sensor_type),
        connector_id: Map.get(metadata, :connector_id),
        connector_name: Map.get(metadata, :connector_name),
        sampling_rate: Map.get(metadata, :sampling_rate),
        append_data:
          ~s|{"timestamp": #{timestamp}, "payload": #{Jason.encode!(Map.get(attribute_value, :payload))}}|
      }
    end)
  end

  def sanitize_sensor_id(sensor_id) when is_binary(sensor_id) do
    replace(sensor_id, ":", "_")
  end
end
