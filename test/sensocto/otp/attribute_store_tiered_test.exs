defmodule Sensocto.AttributeStoreTieredTest do
  use ExUnit.Case, async: false

  alias Sensocto.AttributeStoreTiered

  setup do
    # Generate unique sensor_id per test to avoid conflicts
    sensor_id = "test_sensor_#{System.unique_integer([:positive])}"
    {:ok, sensor_id: sensor_id}
  end

  describe "put_attribute/4 and get_attributes/2" do
    test "stores and retrieves attribute data", %{sensor_id: sensor_id} do
      attribute_id = "temp_#{System.unique_integer([:positive])}"
      payload = %{value: 25.5}

      AttributeStoreTiered.put_attribute(
        sensor_id,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      result = AttributeStoreTiered.get_attributes(sensor_id, 1)
      assert Map.has_key?(result, attribute_id)
      assert length(result[attribute_id]) == 1
      assert hd(result[attribute_id]).payload == payload
    end

    test "stores multiple values for same attribute", %{sensor_id: sensor_id} do
      attribute_id = "temp_#{System.unique_integer([:positive])}"

      # Add multiple values
      for i <- 1..5 do
        AttributeStoreTiered.put_attribute(
          sensor_id,
          attribute_id,
          System.system_time(:millisecond) + i,
          %{value: i}
        )

        Process.sleep(1)
      end

      result = AttributeStoreTiered.get_attributes(sensor_id, 5)
      assert Map.has_key?(result, attribute_id)
      assert length(result[attribute_id]) == 5
    end
  end

  describe "cleanup/1" do
    test "removes all data for a sensor", %{sensor_id: sensor_id} do
      attribute_id = "cleanup_test_#{System.unique_integer([:positive])}"
      payload = %{value: 42}

      # Add some data
      AttributeStoreTiered.put_attribute(
        sensor_id,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      # Verify data exists
      result = AttributeStoreTiered.get_attributes(sensor_id, 1)
      assert Map.has_key?(result, attribute_id)

      # Cleanup the sensor
      assert :ok = AttributeStoreTiered.cleanup(sensor_id)

      # Verify data is gone
      result = AttributeStoreTiered.get_attributes(sensor_id, 1)
      assert result == %{}
    end

    test "does not affect other sensors" do
      sensor1 = "cleanup_other1_#{System.unique_integer([:positive])}"
      sensor2 = "cleanup_other2_#{System.unique_integer([:positive])}"
      attribute_id = "attr_#{System.unique_integer([:positive])}"
      payload = %{value: 123}

      # Add data to both sensors
      AttributeStoreTiered.put_attribute(
        sensor1,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      AttributeStoreTiered.put_attribute(
        sensor2,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      # Verify both have data
      assert Map.has_key?(AttributeStoreTiered.get_attributes(sensor1, 1), attribute_id)
      assert Map.has_key?(AttributeStoreTiered.get_attributes(sensor2, 1), attribute_id)

      # Cleanup only sensor1
      AttributeStoreTiered.cleanup(sensor1)

      # sensor1 should be empty, sensor2 should still have data
      assert AttributeStoreTiered.get_attributes(sensor1, 1) == %{}
      assert Map.has_key?(AttributeStoreTiered.get_attributes(sensor2, 1), attribute_id)

      # Cleanup sensor2 too
      AttributeStoreTiered.cleanup(sensor2)
    end
  end

  describe "clear_all/0" do
    test "removes all data from all sensors" do
      sensor1 = "clear_all1_#{System.unique_integer([:positive])}"
      sensor2 = "clear_all2_#{System.unique_integer([:positive])}"
      attribute_id = "attr_#{System.unique_integer([:positive])}"
      payload = %{value: 999}

      # Add data to both sensors
      AttributeStoreTiered.put_attribute(
        sensor1,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      AttributeStoreTiered.put_attribute(
        sensor2,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      # Verify both have data
      assert Map.has_key?(AttributeStoreTiered.get_attributes(sensor1, 1), attribute_id)
      assert Map.has_key?(AttributeStoreTiered.get_attributes(sensor2, 1), attribute_id)

      # Clear all
      assert :ok = AttributeStoreTiered.clear_all()

      # Both should be empty
      assert AttributeStoreTiered.get_attributes(sensor1, 1) == %{}
      assert AttributeStoreTiered.get_attributes(sensor2, 1) == %{}
    end
  end

  describe "remove_attribute/2" do
    test "removes a specific attribute from a sensor", %{sensor_id: sensor_id} do
      attr1 = "attr1_#{System.unique_integer([:positive])}"
      attr2 = "attr2_#{System.unique_integer([:positive])}"
      payload = %{value: 50}

      # Add two attributes
      AttributeStoreTiered.put_attribute(
        sensor_id,
        attr1,
        System.system_time(:millisecond),
        payload
      )

      AttributeStoreTiered.put_attribute(
        sensor_id,
        attr2,
        System.system_time(:millisecond),
        payload
      )

      # Verify both exist
      result = AttributeStoreTiered.get_attributes(sensor_id, 1)
      assert Map.has_key?(result, attr1)
      assert Map.has_key?(result, attr2)

      # Remove only attr1
      AttributeStoreTiered.remove_attribute(sensor_id, attr1)

      # attr1 should be gone, attr2 should remain
      result = AttributeStoreTiered.get_attributes(sensor_id, 1)
      refute Map.has_key?(result, attr1)
      assert Map.has_key?(result, attr2)

      # Cleanup
      AttributeStoreTiered.cleanup(sensor_id)
    end
  end

  describe "stats/1" do
    test "returns store statistics for a sensor", %{sensor_id: sensor_id} do
      attribute_id = "stats_test_#{System.unique_integer([:positive])}"
      payload = %{value: 100}

      # Add some data
      AttributeStoreTiered.put_attribute(
        sensor_id,
        attribute_id,
        System.system_time(:millisecond),
        payload
      )

      stats = AttributeStoreTiered.stats(sensor_id)

      assert is_map(stats)
      assert Map.has_key?(stats, :hot_entries)
      assert Map.has_key?(stats, :warm_entries)
      assert Map.has_key?(stats, :attributes)
      assert is_integer(stats.hot_entries)
      assert is_integer(stats.warm_entries)

      # Cleanup
      AttributeStoreTiered.cleanup(sensor_id)
    end
  end
end
