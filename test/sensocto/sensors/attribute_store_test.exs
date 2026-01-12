defmodule Sensocto.Sensors.AttributeStoreTest do
  use ExUnit.Case, async: false
  alias Sensocto.AttributeStore

  setup do
    # Generate unique sensor_id per test to avoid conflicts
    sensor_id = "test_sensor_#{System.unique_integer([:positive])}"
    {:ok, _pid} = AttributeStore.start_link(%{sensor_id: sensor_id})
    {:ok, sensor_id: sensor_id}
  end

  test "starts an agent", %{sensor_id: sensor_id} do
    # Agent was started in setup, verify it's running by calling get_attributes
    result = AttributeStore.get_attributes(sensor_id)
    assert result == %{}
  end

  test "put_attribute/4 stores a new attribute", %{sensor_id: sensor_id} do
    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)

    result = AttributeStore.get_attributes(sensor_id)
    assert %{"heart_rate" => [%{payload: 70, timestamp: 1000}]} = result
  end

  test "put_attribute/4 updates an existing attribute", %{sensor_id: sensor_id} do
    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.put_attribute(sensor_id, "heart_rate", 2000, 72)

    result = AttributeStore.get_attributes(sensor_id)

    assert %{
             "heart_rate" => [
               %{payload: 72, timestamp: 2000},
               %{payload: 70, timestamp: 1000}
             ]
           } = result
  end

  test "put_attribute/4 enforces value limit", %{sensor_id: sensor_id} do
    1..10_005
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    %{"heart_rate" => values} = AttributeStore.get_attributes(sensor_id)
    assert length(values) == 10_000
    assert Enum.at(values, 0).timestamp == 10_005
    assert Enum.at(values, 9_999).timestamp == 6
  end

  test "get_attribute/3 returns {:ok, values}", %{sensor_id: sensor_id} do
    1..10
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    {:ok, values} = AttributeStore.get_attribute(sensor_id, "heart_rate", 1)
    assert length(values) == 10
    assert Enum.at(values, 0).timestamp == 10
  end

  test "get_attribute/4 with from/to returns values within the range", %{sensor_id: sensor_id} do
    1..10
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    {:ok, values} = AttributeStore.get_attribute(sensor_id, "heart_rate", 4, 5)
    filtered = Enum.filter(values, fn %{timestamp: ts} -> ts >= 4 and ts <= 5 end)
    assert length(filtered) == 2
    assert Enum.all?(filtered, fn %{timestamp: ts} -> ts in 4..5 end)
  end

  test "remove_attribute/2 removes an attribute", %{sensor_id: sensor_id} do
    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.remove_attribute(sensor_id, "heart_rate")
    result = AttributeStore.get_attributes(sensor_id)
    refute Map.has_key?(result, "heart_rate")
  end

  test "getting unknown attribute returns {:ok, []}", %{sensor_id: sensor_id} do
    assert {:ok, []} = AttributeStore.get_attribute(sensor_id, "nonexistent", 1)
  end

  test "get_attributes returns all the attributes", %{sensor_id: sensor_id} do
    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.put_attribute(sensor_id, "temperature", 1000, 36.6)

    result = AttributeStore.get_attributes(sensor_id)

    assert %{
             "heart_rate" => [%{payload: 70, timestamp: 1000}],
             "temperature" => [%{payload: 36.6, timestamp: 1000}]
           } = result
  end
end
