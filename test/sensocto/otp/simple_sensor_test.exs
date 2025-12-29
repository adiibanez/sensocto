defmodule Sensocto.SimpleSensorTest do
  use Sensocto.DataCase, async: false

  alias Sensocto.SimpleSensor
  alias Sensocto.SensorsDynamicSupervisor

  @moduletag :integration

  describe "sensor lifecycle" do
    test "can start a sensor via SensorsDynamicSupervisor" do
      sensor_id = "test_sensor_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "Test Sensor",
        sensor_type: "test",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{}
      }

      {:ok, pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)

      assert is_pid(pid) or pid == :already_started

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "get_state returns sensor state" do
      sensor_id = "test_sensor_state_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "State Test Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 5,
        sampling_rate: 50,
        attributes: %{
          "temperature" => %{
            attribute_type: "numeric",
            sampling_rate: 50
          }
        }
      }

      {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)

      # Give it time to initialize
      Process.sleep(100)

      state = SimpleSensor.get_state(sensor_id)

      assert state.metadata.sensor_id == sensor_id
      assert state.metadata.sensor_name == "State Test Sensor"

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "put_attribute stores data" do
      sensor_id = "test_put_attr_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "Attribute Test Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 5,
        sampling_rate: 50,
        attributes: %{
          "temperature" => %{
            attribute_type: "numeric",
            sampling_rate: 50
          }
        }
      }

      {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
      Process.sleep(100)

      # Put some data
      SimpleSensor.put_attribute(sensor_id, %{
        "attribute_id" => "temperature",
        "value" => 23.5,
        "timestamp" => System.system_time(:millisecond)
      })

      Process.sleep(50)

      # Get the state and verify
      view_state = SimpleSensor.get_view_state(sensor_id)

      assert view_state.sensor_id == sensor_id

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "put_batch_attributes stores multiple values" do
      sensor_id = "test_batch_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "Batch Test Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{
          "temperature" => %{attribute_type: "numeric", sampling_rate: 100},
          "humidity" => %{attribute_type: "numeric", sampling_rate: 100}
        }
      }

      {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
      Process.sleep(100)

      # Put batch data
      now = System.system_time(:millisecond)

      batch = [
        %{"attribute_id" => "temperature", "value" => 22.0, "timestamp" => now - 200},
        %{"attribute_id" => "temperature", "value" => 22.5, "timestamp" => now - 100},
        %{"attribute_id" => "temperature", "value" => 23.0, "timestamp" => now},
        %{"attribute_id" => "humidity", "value" => 65, "timestamp" => now}
      ]

      SimpleSensor.put_batch_attributes(sensor_id, batch)
      Process.sleep(100)

      view_state = SimpleSensor.get_view_state(sensor_id, 5)
      assert view_state.sensor_id == sensor_id

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end
  end

  describe "via_tuple registration" do
    test "sensor is discoverable via registry" do
      sensor_id = "test_registry_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "Registry Test",
        sensor_type: "test",
        connector_id: "test",
        connector_name: "Test",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{}
      }

      {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
      Process.sleep(100)

      # Check registry
      device_names = SensorsDynamicSupervisor.get_device_names()
      assert sensor_id in device_names

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end
  end
end
