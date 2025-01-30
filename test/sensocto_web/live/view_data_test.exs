defmodule SensoctoWeb.Live.Components.ViewDataTest do
  use ExUnit.Case, async: true
  alias Sensocto.Utils
  alias SensoctoWeb.Live.Components.ViewData

  test "update_sensor_data/2 adds a new attribute to a sensor" do
    sensors = %{
      "sensor_1" => %{
        attributes: %{
          "temp" => [%{timestamp: 123, payload: 25}]
        }
      }
    }

    sensor_data = %{
      sensor_id: "sensor_1",
      uuid: "humidity",
      timestamp: 456,
      payload: 60
    }

    result = ViewData.update_sensor_data(sensors, sensor_data)

    assert result == %{
             "sensor_1" => %{
               attributes: %{
                 "temp" => [%{timestamp: 123, payload: 25}],
                 "humidity" => [%{timestamp: 456, payload: 60}]
               }
             }
           }
  end

  test "update_sensor_data/2 updates an existing attribute of a sensor" do
    sensors = %{
      "sensor_1" => %{
        attributes: %{
          "temp" => [%{timestamp: 123, payload: 25}]
        }
      }
    }

    sensor_data = %{
      sensor_id: "sensor_1",
      uuid: "temp",
      timestamp: 456,
      payload: 60
    }

    result = ViewData.update_sensor_data(sensors, sensor_data)

    assert result == %{
             "sensor_1" => %{
               attributes: %{
                 "temp" => [%{timestamp: 456, payload: 60}]
               }
             }
           }
  end

  test "generate_sensor_view_data/2 generates the correct view data" do
    sensor_data = %{
      metadata: %{
        sensor_id: "sensor_1",
        sensor_type: "temp"
      },
      attributes: %{
        "temp" => [%{timestamp: 123, payload: 25}]
      }
    }

    result = ViewData.generate_sensor_view_data("sensor_1", sensor_data)

    assert result == %{
             "temp" => %{
               id: "sensor_1",
               timestamp: 123,
               payload: 25,
               connector_id: nil,
               sensor_type: "temp",
               attribute_id: "temp",
               sensor_id: "sensor_1",
               sensor_name: nil,
               timestamp_formated: "1970-01-01 00:00:00.123Z",
               connector_name: nil,
               sampling_rate: nil,
               append_data: "{\"timestamp\": 123, \"payload\": 25}"
             }
           }
  end

  test "generate_sensor_view_data/2 generates the correct view data with string keys" do
    sensor_data = %{
      "metadata" => %{
        "sensor_id" => "sensor_1",
        "sensor_type" => "temp"
      },
      "attributes" => %{
        "temp" => [%{"timestamp" => 123, "payload" => 25}]
      }
    }

    sensor_data = Utils.string_keys_to_atom_keys(sensor_data)

    result = ViewData.generate_sensor_view_data("sensor_1", sensor_data)

    assert result == %{
             :temp => %{
               append_data: "{\"timestamp\": 123, \"payload\": 25}",
               attribute_id: :temp,
               connector_id: nil,
               connector_name: nil,
               id: "sensor_1",
               payload: 25,
               sampling_rate: nil,
               sensor_id: :sensor_1,
               sensor_name: nil,
               sensor_type: :temp,
               timestamp: 123,
               timestamp_formated: "1970-01-01 00:00:00.123Z"
             }
           }
  end

  test "generate_sensor_view_data/2 generates the correct view data with default values" do
    sensor_data = %{
      attributes: %{
        "temp" => [%{}]
      }
    }

    result = ViewData.generate_sensor_view_data("sensor_1", sensor_data)

    assert result == %{
             "temp" => %{
               id: "sensor_1",
               timestamp: nil,
               payload: nil,
               connector_id: nil,
               sensor_type: nil,
               attribute_id: "temp",
               sensor_id: nil,
               sensor_name: nil,
               timestamp_formated: "Invalid Date",
               connector_name: nil,
               sampling_rate: nil,
               append_data: "{\"timestamp\": null, \"payload\": null}"
             }
           }
  end

  test "sanitize_sensor_id/1 replaces colons with underscores" do
    assert ViewData.sanitize_sensor_id("sensor:123") == "sensor_123"
  end
end
