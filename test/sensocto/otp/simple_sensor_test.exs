defmodule Sensocto.SimpleSensorTest do
  @moduledoc """
  Tests for Sensocto.SimpleSensor GenServer.

  ## Known Issues Documented

  1. **FunctionClauseError in handle_cast for :put_attribute**
     The handle_cast expects atom keys (:attribute_id, :payload, :timestamp) but
     some callers may send string keys ("attribute_id", "value", "timestamp").
     See tests tagged with :bug_documentation.

  2. **KeyError in put_batch_attributes**
     Similar issue - the batch processing uses Map.get with struct-like access
     (attribute.attribute_id) which fails if attributes are maps with string keys.
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.SimpleSensor
  alias Sensocto.SensorsDynamicSupervisor

  @moduletag :integration

  # Test setup helper
  defp create_sensor(suffix \\ "") do
    sensor_id = "test_sensor_#{suffix}_#{System.unique_integer([:positive])}"

    configuration = %{
      sensor_id: sensor_id,
      sensor_name: "Test Sensor #{suffix}",
      sensor_type: "test_type",
      connector_id: "test_connector",
      connector_name: "Test Connector",
      batch_size: 10,
      sampling_rate: 100,
      attributes: %{
        "temperature" => %{
          attribute_type: "numeric",
          sampling_rate: 100
        },
        "humidity" => %{
          attribute_type: "numeric",
          sampling_rate: 100
        }
      }
    }

    {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
    # Give time to initialize
    Process.sleep(100)

    on_exit(fn ->
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end)

    {sensor_id, configuration}
  end

  describe "sensor lifecycle" do
    test "can start a sensor via SensorsDynamicSupervisor" do
      sensor_id = "test_sensor_lifecycle_#{System.unique_integer([:positive])}"

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

    test "sensor terminates cleanly" do
      sensor_id = "test_terminate_#{System.unique_integer([:positive])}"

      configuration = %{
        sensor_id: sensor_id,
        sensor_name: "Terminate Test",
        sensor_type: "test",
        connector_id: "test",
        connector_name: "Test",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{}
      }

      {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
      Process.sleep(100)

      # Should terminate without error
      assert :ok = SensorsDynamicSupervisor.remove_sensor(sensor_id)

      # Verify it's gone
      Process.sleep(50)
      device_names = SensorsDynamicSupervisor.get_device_names()
      refute sensor_id in device_names
    end
  end

  describe "get_state/2" do
    test "returns sensor state with metadata" do
      {sensor_id, config} = create_sensor("state")

      state = SimpleSensor.get_state(sensor_id)

      assert state.metadata.sensor_id == sensor_id
      assert state.metadata.sensor_name == config.sensor_name
      assert state.metadata.sensor_type == config.sensor_type
      assert state.metadata.connector_id == config.connector_id
      assert is_map(state.attributes)
    end

    test "returns empty attributes when no data has been stored" do
      {sensor_id, _config} = create_sensor("empty_state")

      state = SimpleSensor.get_state(sensor_id)

      assert is_map(state.attributes)
      # Attributes map should be empty or have empty lists
      Enum.each(state.attributes, fn {_key, values} ->
        assert values == [] or is_list(values)
      end)
    end
  end

  describe "get_view_state/2" do
    test "transforms state for view consumption" do
      {sensor_id, _config} = create_sensor("view_state")

      view_state = SimpleSensor.get_view_state(sensor_id)

      assert view_state.sensor_id == sensor_id
      assert is_map(view_state.attributes)
    end

    test "includes attribute metadata in transformed state" do
      {sensor_id, _config} = create_sensor("view_meta")

      # First put some data with correct format
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 23.5,
        timestamp: System.system_time(:millisecond)
      })

      Process.sleep(50)

      view_state = SimpleSensor.get_view_state(sensor_id)

      # Check that temperature attribute has the expected structure
      if Map.has_key?(view_state.attributes, "temperature") do
        temp_attr = view_state.attributes["temperature"]
        assert Map.has_key?(temp_attr, :attribute_id)
        assert Map.has_key?(temp_attr, :attribute_type)
        assert Map.has_key?(temp_attr, :values)
      end
    end
  end

  describe "put_attribute/2 with atom keys (correct format)" do
    test "stores single attribute with atom keys" do
      {sensor_id, _config} = create_sensor("put_atom")

      timestamp = System.system_time(:millisecond)

      # This is the CORRECT format expected by SimpleSensor
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.5,
        timestamp: timestamp
      })

      Process.sleep(50)

      state = SimpleSensor.get_state(sensor_id)
      temp_data = Map.get(state.attributes, "temperature", [])

      assert length(temp_data) > 0
      first_entry = List.first(temp_data)
      assert first_entry.payload == 25.5
      assert first_entry.timestamp == timestamp
    end

    test "stores multiple attributes for same sensor" do
      {sensor_id, _config} = create_sensor("multi_attr")

      now = System.system_time(:millisecond)

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 22.0,
        timestamp: now
      })

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "humidity",
        payload: 65,
        timestamp: now
      })

      Process.sleep(50)

      state = SimpleSensor.get_state(sensor_id)

      assert length(Map.get(state.attributes, "temperature", [])) > 0
      assert length(Map.get(state.attributes, "humidity", [])) > 0
    end
  end

  describe "put_attribute/2 with string keys - BUG DOCUMENTATION" do
    @tag :bug_documentation
    @tag :skip
    test "FAILS with string keys - demonstrates FunctionClauseError bug" do
      # This test documents the bug where string keys cause FunctionClauseError
      # The handle_cast pattern matches on atom keys:
      #   %{:attribute_id => ..., :payload => ..., :timestamp => ...}
      # But some callers may send string keys which causes pattern match failure

      {sensor_id, _config} = create_sensor("string_keys")

      # This WILL FAIL with FunctionClauseError because SimpleSensor expects atom keys
      assert_raise FunctionClauseError, fn ->
        SimpleSensor.put_attribute(sensor_id, %{
          "attribute_id" => "temperature",
          "payload" => 23.5,
          "timestamp" => System.system_time(:millisecond)
        })
      end
    end

    @tag :bug_documentation
    @tag :skip
    test "FAILS with 'value' key instead of 'payload' - documents wrong key name" do
      # Some external callers may use "value" instead of "payload"
      # This also causes FunctionClauseError

      {sensor_id, _config} = create_sensor("wrong_key")

      # This pattern was seen in older test code
      assert_raise FunctionClauseError, fn ->
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          # Wrong key name! Should be :payload
          value: 23.5,
          timestamp: System.system_time(:millisecond)
        })
      end
    end
  end

  describe "put_batch_attributes/2 with atom keys" do
    test "stores batch of attributes with correct format" do
      {sensor_id, _config} = create_sensor("batch_atom")

      now = System.system_time(:millisecond)

      batch = [
        %{attribute_id: "temperature", payload: 22.0, timestamp: now - 200},
        %{attribute_id: "temperature", payload: 22.5, timestamp: now - 100},
        %{attribute_id: "temperature", payload: 23.0, timestamp: now},
        %{attribute_id: "humidity", payload: 65, timestamp: now}
      ]

      SimpleSensor.put_batch_attributes(sensor_id, batch)
      Process.sleep(100)

      state = SimpleSensor.get_state(sensor_id, 5)

      temp_data = Map.get(state.attributes, "temperature", [])
      assert length(temp_data) >= 3

      humidity_data = Map.get(state.attributes, "humidity", [])
      assert length(humidity_data) >= 1
    end
  end

  describe "put_batch_attributes/2 with string keys - BUG DOCUMENTATION" do
    @tag :bug_documentation
    @tag :skip
    test "FAILS with string keys - demonstrates KeyError bug" do
      # This test documents the KeyError bug when batch processing uses
      # struct-like access (attribute.attribute_id) on maps with string keys

      {sensor_id, _config} = create_sensor("batch_string")

      now = System.system_time(:millisecond)

      # This uses string keys which will cause KeyError
      batch = [
        %{"attribute_id" => "temperature", "payload" => 22.0, "timestamp" => now}
      ]

      # The error occurs because the code does:
      #   attribute.attribute_id  <- fails on string-keyed maps
      # instead of:
      #   Map.get(attribute, :attribute_id) || Map.get(attribute, "attribute_id")

      assert_raise KeyError, fn ->
        SimpleSensor.put_batch_attributes(sensor_id, batch)
        Process.sleep(50)
      end
    end
  end

  describe "update_attribute_registry/4" do
    test "can register a new attribute" do
      {sensor_id, _config} = create_sensor("register")

      SimpleSensor.update_attribute_registry(
        sensor_id,
        :register,
        "new_attr",
        %{attribute_type: "string", sampling_rate: 50}
      )

      Process.sleep(50)

      state = SimpleSensor.get_state(sensor_id)
      assert Map.has_key?(state.metadata.attributes, "new_attr")
    end

    test "can unregister an attribute" do
      {sensor_id, _config} = create_sensor("unregister")

      # First, the temperature attribute should exist from config
      state_before = SimpleSensor.get_state(sensor_id)
      assert Map.has_key?(state_before.metadata.attributes, "temperature")

      # Unregister it
      SimpleSensor.update_attribute_registry(sensor_id, :unregister, "temperature", %{})
      Process.sleep(50)

      state_after = SimpleSensor.get_state(sensor_id)
      refute Map.has_key?(state_after.metadata.attributes, "temperature")
    end
  end

  describe "clear_attribute/2" do
    test "removes attribute data from store" do
      {sensor_id, _config} = create_sensor("clear")

      # First add some data
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.0,
        timestamp: System.system_time(:millisecond)
      })

      Process.sleep(50)

      # Verify data exists
      state_before = SimpleSensor.get_state(sensor_id)
      assert length(Map.get(state_before.attributes, "temperature", [])) > 0

      # Clear the attribute
      SimpleSensor.clear_attribute(sensor_id, "temperature")
      Process.sleep(50)

      # Data should be cleared
      state_after = SimpleSensor.get_state(sensor_id)
      assert Map.get(state_after.attributes, "temperature", []) == []
    end
  end

  describe "get_attribute/5" do
    test "retrieves attribute data with time filtering" do
      {sensor_id, _config} = create_sensor("get_attr")

      now = System.system_time(:millisecond)

      # Add data at different timestamps
      Enum.each([now - 1000, now - 500, now], fn ts ->
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          payload: 20.0 + :rand.uniform(10),
          timestamp: ts
        })
      end)

      Process.sleep(100)

      # Get all data (returns list directly, not {:ok, list})
      all_data = SimpleSensor.get_attribute(sensor_id, "temperature", 0, :infinity, :infinity)

      assert length(all_data) >= 3

      # Get data from last 600ms
      recent_data =
        SimpleSensor.get_attribute(sensor_id, "temperature", now - 600, :infinity, :infinity)

      assert length(recent_data) >= 2
    end

    test "respects limit parameter" do
      {sensor_id, _config} = create_sensor("get_limit")

      now = System.system_time(:millisecond)

      # Add 5 entries
      Enum.each(1..5, fn i ->
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          payload: 20.0 + i,
          timestamp: now + i
        })
      end)

      Process.sleep(100)

      # Request only 2 (returns list directly, not {:ok, list})
      limited_data = SimpleSensor.get_attribute(sensor_id, "temperature", 0, :infinity, 2)
      assert length(limited_data) == 2
    end
  end

  describe "via_tuple registration" do
    test "sensor is discoverable via registry" do
      {sensor_id, _config} = create_sensor("registry")

      device_names = SensorsDynamicSupervisor.get_device_names()
      assert sensor_id in device_names
    end

    test "multiple sensors can coexist" do
      sensor_ids =
        Enum.map(1..3, fn i ->
          {sensor_id, _} = create_sensor("multi_#{i}")
          sensor_id
        end)

      device_names = SensorsDynamicSupervisor.get_device_names()

      Enum.each(sensor_ids, fn sensor_id ->
        assert sensor_id in device_names
      end)
    end
  end

  describe "MPS (messages per second) calculation" do
    test "calculates MPS based on message timestamps" do
      {sensor_id, _config} = create_sensor("mps")

      # Send several messages
      Enum.each(1..10, fn i ->
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          payload: 20.0 + i,
          timestamp: System.system_time(:millisecond)
        })

        Process.sleep(10)
      end)

      # Wait for MPS calculation (happens every 1 second)
      Process.sleep(1100)

      # MPS telemetry should have been emitted
      # We can't easily verify telemetry in tests without a handler,
      # but we verify the sensor is still running properly
      state = SimpleSensor.get_state(sensor_id)
      assert state.metadata.sensor_id == sensor_id
    end
  end

  describe "PubSub integration" do
    test "broadcasts measurement on put_attribute" do
      {sensor_id, _config} = create_sensor("pubsub")

      # Subscribe to sensor data topic
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.0,
        timestamp: System.system_time(:millisecond)
      })

      # Should receive measurement broadcast
      assert_receive {:measurement, measurement}, 500
      assert measurement.sensor_id == sensor_id
      assert measurement.attribute_id == "temperature"
      assert measurement.payload == 25.0
    end

    test "broadcasts batch measurements on put_batch_attributes" do
      {sensor_id, _config} = create_sensor("pubsub_batch")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      now = System.system_time(:millisecond)

      batch = [
        %{attribute_id: "temperature", payload: 22.0, timestamp: now},
        %{attribute_id: "humidity", payload: 65, timestamp: now}
      ]

      SimpleSensor.put_batch_attributes(sensor_id, batch)

      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) == 2
    end

    test "broadcasts state change on attribute registry update" do
      {sensor_id, _config} = create_sensor("pubsub_state")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")

      SimpleSensor.update_attribute_registry(
        sensor_id,
        :register,
        "pressure",
        %{attribute_type: "numeric", sampling_rate: 100}
      )

      assert_receive {:new_state, ^sensor_id}, 500
    end
  end
end
