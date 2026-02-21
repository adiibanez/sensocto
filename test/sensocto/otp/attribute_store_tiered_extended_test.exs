defmodule Sensocto.AttributeStoreTieredExtendedTest do
  @moduledoc """
  Extended tests for AttributeStoreTiered.

  Verifies:
  - Hot/warm tier data flow
  - put_attribute stores data in ETS
  - get_attribute retrieves with time filtering and limits
  - Cleanup removes all sensor data
  - Data ordering (newest last)
  """

  use ExUnit.Case, async: false

  alias Sensocto.AttributeStoreTiered

  @moduletag :integration

  defp unique_sensor_id, do: "attr_store_test_#{System.unique_integer([:positive])}"

  setup do
    sensor_id = unique_sensor_id()

    on_exit(fn ->
      AttributeStoreTiered.cleanup(sensor_id)
    end)

    {:ok, sensor_id: sensor_id}
  end

  # Helper to unwrap {:ok, list} | list
  defp unwrap_result({:ok, list}) when is_list(list), do: list
  defp unwrap_result(list) when is_list(list), do: list

  # ===========================================================================
  # put_attribute / get_attribute
  # ===========================================================================

  describe "put_attribute/4 and get_attribute/5" do
    test "stores and retrieves a single value", %{sensor_id: sensor_id} do
      attr_id = "temperature"
      now = System.system_time(:millisecond)

      AttributeStoreTiered.put_attribute(sensor_id, attr_id, now, 25.0)

      result =
        AttributeStoreTiered.get_attribute(sensor_id, attr_id, 0, :infinity, 10)
        |> unwrap_result()

      assert length(result) == 1

      entry = List.first(result)
      assert entry.payload == 25.0
      assert entry.timestamp == now
    end

    test "stores multiple values for same attribute", %{sensor_id: sensor_id} do
      attr_id = "temperature"
      now = System.system_time(:millisecond)

      for i <- 1..5 do
        AttributeStoreTiered.put_attribute(sensor_id, attr_id, now + i, 20.0 + i)
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, attr_id, 0, :infinity, 10)
        |> unwrap_result()

      assert length(result) == 5
    end

    test "respects limit parameter", %{sensor_id: sensor_id} do
      attr_id = "temperature"
      now = System.system_time(:millisecond)

      for i <- 1..10 do
        AttributeStoreTiered.put_attribute(sensor_id, attr_id, now + i, 20.0 + i)
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, attr_id, 0, :infinity, 3) |> unwrap_result()

      assert length(result) == 3
    end

    test "returns most recent entries when limited", %{sensor_id: sensor_id} do
      attr_id = "temperature"
      now = System.system_time(:millisecond)

      for i <- 1..10 do
        AttributeStoreTiered.put_attribute(
          sensor_id,
          attr_id,
          now + i * 100,
          Float.round(20.0 + i * 0.1, 1)
        )
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, attr_id, 0, :infinity, 3) |> unwrap_result()

      assert length(result) == 3

      timestamps = Enum.map(result, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)
      assert List.last(timestamps) == now + 10 * 100
    end

    test "filters by start time", %{sensor_id: sensor_id} do
      attr_id = "temperature"
      now = System.system_time(:millisecond)

      for i <- 1..5 do
        AttributeStoreTiered.put_attribute(sensor_id, attr_id, now + i * 1000, 20.0 + i)
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, attr_id, now + 3000, :infinity, 10)
        |> unwrap_result()

      assert length(result) >= 2
    end

    test "returns empty for non-existent sensor" do
      result =
        AttributeStoreTiered.get_attribute("nonexistent_sensor", "temperature", 0, :infinity, 10)
        |> unwrap_result()

      assert result == []
    end

    test "returns empty for non-existent attribute", %{sensor_id: sensor_id} do
      result =
        AttributeStoreTiered.get_attribute(sensor_id, "nonexistent_attr", 0, :infinity, 10)
        |> unwrap_result()

      assert result == []
    end
  end

  # ===========================================================================
  # Different attribute types
  # ===========================================================================

  describe "multiple attributes" do
    test "stores data independently per attribute", %{sensor_id: sensor_id} do
      now = System.system_time(:millisecond)

      AttributeStoreTiered.put_attribute(sensor_id, "temperature", now, 25.0)
      AttributeStoreTiered.put_attribute(sensor_id, "humidity", now, 65)
      AttributeStoreTiered.put_attribute(sensor_id, "pressure", now, 1013.25)

      temp =
        AttributeStoreTiered.get_attribute(sensor_id, "temperature", 0, :infinity, 10)
        |> unwrap_result()

      hum =
        AttributeStoreTiered.get_attribute(sensor_id, "humidity", 0, :infinity, 10)
        |> unwrap_result()

      pres =
        AttributeStoreTiered.get_attribute(sensor_id, "pressure", 0, :infinity, 10)
        |> unwrap_result()

      assert length(temp) == 1
      assert length(hum) == 1
      assert length(pres) == 1

      assert List.first(temp).payload == 25.0
      assert List.first(hum).payload == 65
      assert List.first(pres).payload == 1013.25
    end
  end

  # ===========================================================================
  # Cleanup
  # ===========================================================================

  describe "cleanup/1" do
    test "removes all data for a sensor", %{sensor_id: sensor_id} do
      now = System.system_time(:millisecond)

      AttributeStoreTiered.put_attribute(sensor_id, "temperature", now, 25.0)
      AttributeStoreTiered.put_attribute(sensor_id, "humidity", now, 65)

      temp_before =
        AttributeStoreTiered.get_attribute(sensor_id, "temperature", 0, :infinity, 10)
        |> unwrap_result()

      assert length(temp_before) > 0

      AttributeStoreTiered.cleanup(sensor_id)

      temp_after =
        AttributeStoreTiered.get_attribute(sensor_id, "temperature", 0, :infinity, 10)
        |> unwrap_result()

      hum_after =
        AttributeStoreTiered.get_attribute(sensor_id, "humidity", 0, :infinity, 10)
        |> unwrap_result()

      assert temp_after == []
      assert hum_after == []
    end

    test "cleanup is idempotent", %{sensor_id: sensor_id} do
      AttributeStoreTiered.cleanup(sensor_id)
      AttributeStoreTiered.cleanup(sensor_id)
    end

    test "cleanup of non-existent sensor is safe" do
      AttributeStoreTiered.cleanup("totally_nonexistent_sensor")
    end
  end

  # ===========================================================================
  # High-volume data
  # ===========================================================================

  describe "high-volume operations" do
    test "handles 1000 rapid inserts", %{sensor_id: sensor_id} do
      now = System.system_time(:millisecond)

      for i <- 1..1000 do
        AttributeStoreTiered.put_attribute(sensor_id, "ecg", now + i, :rand.uniform() * 100)
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, "ecg", 0, :infinity, 1000)
        |> unwrap_result()

      assert length(result) >= 100
    end

    test "data is ordered by timestamp", %{sensor_id: sensor_id} do
      now = System.system_time(:millisecond)

      timestamps = Enum.shuffle(1..20)

      for i <- timestamps do
        AttributeStoreTiered.put_attribute(sensor_id, "temperature", now + i * 100, 20.0 + i)
      end

      result =
        AttributeStoreTiered.get_attribute(sensor_id, "temperature", 0, :infinity, 20)
        |> unwrap_result()

      result_timestamps = Enum.map(result, & &1.timestamp)

      assert result_timestamps == Enum.sort(result_timestamps),
             "Results should be in chronological order"
    end
  end

  # ===========================================================================
  # ETS table existence
  # ===========================================================================

  describe "ETS tables" do
    test "hot tier table exists" do
      assert :ets.whereis(:attribute_store_hot) != :undefined
    end

    test "warm tier table exists" do
      assert :ets.whereis(:attribute_store_warm) != :undefined
    end

    test "sensors table exists" do
      assert :ets.whereis(:attribute_store_sensors) != :undefined
    end
  end
end
