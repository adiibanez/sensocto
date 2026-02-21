defmodule Sensocto.SensorsDynamicSupervisorTest do
  @moduledoc """
  Tests for Sensocto.SensorsDynamicSupervisor.

  Verifies:
  - add_sensor/2 starts sensor processes and broadcasts
  - remove_sensor/1 terminates and cleans up
  - get_device_names/0 returns all sensor IDs
  - get_all_sensors_state/3 parallel fetching with timeout handling
  - get_sensor_state/3 individual state retrieval
  - count_children/0 and children/0
  - PubSub broadcasts on sensor lifecycle
  - Already-started sensors are handled gracefully
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.SimpleSensor

  @moduletag :integration

  defp sensor_config(sensor_id, attrs \\ %{}) do
    Map.merge(
      %{
        sensor_id: sensor_id,
        sensor_name: "Test Sensor",
        sensor_type: "test_type",
        connector_id: "test_connector",
        connector_name: "Test Connector",
        batch_size: 10,
        sampling_rate: 100,
        attributes: %{
          "temperature" => %{attribute_type: "numeric", sampling_rate: 100},
          "humidity" => %{attribute_type: "numeric", sampling_rate: 50}
        }
      },
      attrs
    )
  end

  defp unique_sensor_id, do: "dyn_sup_test_#{System.unique_integer([:positive])}"

  # ===========================================================================
  # add_sensor/2
  # ===========================================================================

  describe "add_sensor/2" do
    test "starts a sensor and returns {:ok, pid}" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      result = SensorsDynamicSupervisor.add_sensor(sensor_id, config)

      case result do
        {:ok, pid} when is_pid(pid) ->
          assert Process.alive?(pid)

        {:ok, :already_started} ->
          :ok
      end

      # Cleanup
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "sensor appears in get_device_names after add" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      Process.sleep(200)

      device_names = SensorsDynamicSupervisor.get_device_names()
      assert sensor_id in device_names

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "broadcasts :sensor_online on add" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensors:global")

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)

      assert_receive {:sensor_online, ^sensor_id, _config}, 1000

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "adding same sensor twice returns :already_started" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      Process.sleep(100)

      result = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      assert result == {:ok, :already_started}

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end
  end

  # ===========================================================================
  # remove_sensor/1
  # ===========================================================================

  describe "remove_sensor/1" do
    test "removes sensor and returns :ok" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      Process.sleep(200)

      assert :ok = SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "sensor disappears from get_device_names after remove" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      Process.sleep(200)

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
      Process.sleep(200)

      device_names = SensorsDynamicSupervisor.get_device_names()
      refute sensor_id in device_names
    end

    test "broadcasts :sensor_offline on remove" do
      sensor_id = unique_sensor_id()
      config = sensor_config(sensor_id)

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, config)
      Process.sleep(200)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensors:global")

      SensorsDynamicSupervisor.remove_sensor(sensor_id)

      assert_receive {:sensor_offline, ^sensor_id}, 1000
    end

    test "removing non-existent sensor returns :error" do
      result =
        SensorsDynamicSupervisor.remove_sensor("nonexistent_sensor_#{System.unique_integer()}")

      assert result == :error
    end
  end

  # ===========================================================================
  # get_device_names/0
  # ===========================================================================

  describe "get_device_names/0" do
    test "returns a list" do
      assert is_list(SensorsDynamicSupervisor.get_device_names())
    end

    test "includes all added sensors" do
      ids = Enum.map(1..3, fn _ -> unique_sensor_id() end)

      Enum.each(ids, fn id ->
        {:ok, _} = SensorsDynamicSupervisor.add_sensor(id, sensor_config(id))
      end)

      Process.sleep(300)

      device_names = SensorsDynamicSupervisor.get_device_names()

      Enum.each(ids, fn id ->
        assert id in device_names, "#{id} should be in device names"
      end)

      # Cleanup
      Enum.each(ids, &SensorsDynamicSupervisor.remove_sensor/1)
    end
  end

  # ===========================================================================
  # get_all_sensors_state/3
  # ===========================================================================

  describe "get_all_sensors_state/3" do
    test "returns map of sensor states" do
      sensor_id = unique_sensor_id()
      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(200)

      states = SensorsDynamicSupervisor.get_all_sensors_state()
      assert is_map(states)
      assert Map.has_key?(states, sensor_id)

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "state includes metadata and attributes" do
      sensor_id = unique_sensor_id()
      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(200)

      states = SensorsDynamicSupervisor.get_all_sensors_state()
      state = states[sensor_id]

      assert state != nil
      assert state.metadata.sensor_id == sensor_id
      assert is_map(state.attributes)

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test ":view mode returns view-transformed state" do
      sensor_id = unique_sensor_id()
      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(200)

      states = SensorsDynamicSupervisor.get_all_sensors_state(:view)
      assert is_map(states)
      assert Map.has_key?(states, sensor_id)

      state = states[sensor_id]
      assert state.sensor_id == sensor_id

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end
  end

  # ===========================================================================
  # get_sensor_state/3
  # ===========================================================================

  describe "get_sensor_state/3" do
    test "returns state for existing sensor" do
      sensor_id = unique_sensor_id()
      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(200)

      result = SensorsDynamicSupervisor.get_sensor_state(sensor_id, :default, 1)
      assert is_map(result)

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end

    test "returns :error for non-existent sensor" do
      result =
        SensorsDynamicSupervisor.get_sensor_state(
          "nonexistent_#{System.unique_integer()}",
          :default,
          1
        )

      assert result == :error
    end
  end

  # ===========================================================================
  # count_children/0 and children/0
  # ===========================================================================

  describe "count_children/0" do
    test "reflects number of managed sensors" do
      sensor_id = unique_sensor_id()
      initial = SensorsDynamicSupervisor.count_children()

      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(100)

      after_add = SensorsDynamicSupervisor.count_children()
      assert after_add[:active] >= initial[:active] + 1

      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end
  end

  describe "children/0" do
    test "returns a list" do
      children = SensorsDynamicSupervisor.children()
      assert is_list(children)
    end
  end

  # ===========================================================================
  # Full lifecycle integration
  # ===========================================================================

  describe "full sensor lifecycle" do
    test "add → put data → get state → remove" do
      sensor_id = unique_sensor_id()
      {:ok, _} = SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config(sensor_id))
      Process.sleep(200)

      # Put some data
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.5,
        timestamp: System.system_time(:millisecond)
      })

      Process.sleep(50)

      # Verify state contains data
      states = SensorsDynamicSupervisor.get_all_sensors_state()
      state = states[sensor_id]
      temp_data = Map.get(state.attributes, "temperature", [])
      assert length(temp_data) > 0

      # Remove
      assert :ok = SensorsDynamicSupervisor.remove_sensor(sensor_id)
      Process.sleep(100)

      refute sensor_id in SensorsDynamicSupervisor.get_device_names()
    end
  end
end
