defmodule SensoctoWeb.LiveHelpers.SensorData do
  @moduledoc """
  Shared helper functions for transforming sensor data into graph-friendly structures.
  Used by both LobbyLive and IndexLive.
  """

  def group_sensors_by_user(sensors) do
    sensors
    |> Enum.group_by(fn {_id, sensor} -> {sensor.connector_id, sensor.connector_name} end)
    |> Enum.map(fn {{connector_id, connector_name}, sensor_list} ->
      all_attributes =
        sensor_list
        |> Enum.flat_map(fn {_id, sensor} ->
          (sensor.attributes || %{})
          |> Map.values()
          |> Enum.map(fn attr ->
            %{
              type: attr.attribute_type,
              name: Map.get(attr, :attribute_name, attr.attribute_id),
              value: attr.lastvalue && attr.lastvalue.payload,
              timestamp: attr.lastvalue && attr.lastvalue.timestamp
            }
          end)
        end)

      attributes_summary =
        all_attributes
        |> Enum.group_by(& &1.type)
        |> Enum.map(fn {type, attrs} ->
          latest = Enum.max_by(attrs, fn a -> a.timestamp || 0 end, fn -> %{value: nil} end)
          %{type: type, count: length(attrs), latest_value: latest.value}
        end)
        |> Enum.sort_by(& &1.type)

      %{
        connector_id: connector_id,
        connector_name: connector_name || "Unknown",
        sensor_count: length(sensor_list),
        sensors:
          Enum.map(sensor_list, fn {id, s} ->
            %{sensor_id: id, sensor_name: s.sensor_name}
          end),
        attributes_summary: attributes_summary,
        total_attributes: length(all_attributes)
      }
    end)
    |> Enum.sort_by(& &1.connector_name)
  end

  def enrich_sensors_with_attention(sensors) do
    Map.new(sensors, fn {id, sensor} ->
      level = Sensocto.AttentionTracker.get_sensor_attention_level(id)
      {id, Map.put(sensor, :attention_level, level)}
    end)
  end
end
