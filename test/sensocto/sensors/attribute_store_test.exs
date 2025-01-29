defmodule Sensocto.Sensors.AttributeStoreTest do
  use ExUnit.Case, async: true
  alias Sensocto.AttributeStore
  alias Sensocto.SensorAttributeRegistry

  setup do
    {:ok, _} = SensorAttributeRegistry.start_link()

    on_exit(fn ->
      Registry.shutdown(SimpleAttributeRegistry)
    end)

    :ok
  end

  def start_agent(sensor_id) do
    {:ok, agent_pid} = AttributeStore.start_link(%{sensor_id: sensor_id})
    agent_pid
  end

  test "starts an agent" do
    sensor_id = "test_sensor_1"
    agent_pid = start_agent(sensor_id)
    assert {:ok, ^agent_pid} = AttributeStore.get_pid(sensor_id)
  end

  test "put_attribute/4 stores a new attribute" do
    sensor_id = "test_sensor_2"
    agent_pid = start_agent(sensor_id)

    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)

    assert %{"heart_rate" => %{values: [%{payload: 70, timestamp: 1000}]}} =
             AttributeStore.get_attributes(sensor_id)
  end

  test "put_attribute/4 updates an existing attribute" do
    sensor_id = "test_sensor_3"
    agent_pid = start_agent(sensor_id)

    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.put_attribute(sensor_id, "heart_rate", 2000, 72)

    assert %{
             "heart_rate" => %{
               values: [%{payload: 72, timestamp: 2000}, %{payload: 70, timestamp: 1000}]
             }
           } =
             AttributeStore.get_attributes(sensor_id)
  end

  test "put_attribute/4 enforces value limit" do
    sensor_id = "test_sensor_4"
    agent_pid = start_agent(sensor_id)

    1..10005
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    %{"heart_rate" => %{values: values}} = AttributeStore.get_attributes(sensor_id)
    assert length(values) == 10000
    assert Enum.at(values, 0).timestamp == 10005
    assert Enum.at(values, 9999).timestamp == 6
  end

  test "get_attribute/3 with limit returns last N values" do
    sensor_id = "test_sensor_5"
    agent_pid = start_agent(sensor_id)

    1..10
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    assert [
             %{payload: 10, timestamp: 10},
             %{payload: 9, timestamp: 9},
             %{payload: 8, timestamp: 8}
           ] =
             AttributeStore.get_attribute(sensor_id, "heart_rate", 3)
  end

  test "get_attribute/4 with from/to returns values within the range" do
    sensor_id = "test_sensor_6"
    agent_pid = start_agent(sensor_id)

    1..10
    |> Enum.each(fn i ->
      AttributeStore.put_attribute(sensor_id, "heart_rate", i, i)
    end)

    assert [%{payload: 5, timestamp: 5}, %{payload: 4, timestamp: 4}] =
             AttributeStore.get_attribute(sensor_id, "heart_rate", 4, 5)

    assert [] = AttributeStore.get_attribute(sensor_id, "heart_rate", 11, 12)
  end

  test "remove_attribute/2 removes an attribute" do
    sensor_id = "test_sensor_7"
    agent_pid = start_agent(sensor_id)

    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.remove_attribute(sensor_id, "heart_rate")
    assert %{} = AttributeStore.get_attributes(sensor_id)
  end

  test "getting unknown attribute returns empty list" do
    sensor_id = "test_sensor_8"
    agent_pid = start_agent(sensor_id)
    assert [] = AttributeStore.get_attribute(sensor_id, "test", 3)
    assert [] = AttributeStore.get_attribute(sensor_id, "test", 100, 200)
  end

  test "get_attributes returns all the attributes" do
    sensor_id = "test_sensor_9"
    agent_pid = start_agent(sensor_id)

    AttributeStore.put_attribute(sensor_id, "heart_rate", 1000, 70)
    AttributeStore.put_attribute(sensor_id, "temperature", 1000, 36.6)

    assert %{
             "heart_rate" => %{values: [%{payload: 70, timestamp: 1000}]},
             "temperature" => %{values: [%{payload: 36.6, timestamp: 1000}]}
           } =
             AttributeStore.get_attributes(sensor_id)
  end
end
