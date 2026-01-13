defmodule Sensocto.Bio.ResourceArbiterTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.ResourceArbiter

  setup do
    sensor_id = "sensor_#{System.unique_integer([:positive])}"
    {:ok, sensor_id: sensor_id}
  end

  describe "get_multiplier/1" do
    test "returns 1.0 for unknown sensor", %{sensor_id: sensor_id} do
      assert ResourceArbiter.get_multiplier(sensor_id) == 1.0
    end

    test "returns float value", %{sensor_id: sensor_id} do
      multiplier = ResourceArbiter.get_multiplier(sensor_id)
      assert is_float(multiplier) or is_integer(multiplier)
      assert multiplier > 0
    end
  end

  describe "get_allocations/0" do
    test "returns allocation map" do
      allocations = ResourceArbiter.get_allocations()
      assert is_map(allocations)
    end
  end

  describe "reallocate/0" do
    test "triggers reallocation" do
      assert :ok == ResourceArbiter.reallocate()
    end
  end

  describe "get_state/0" do
    test "returns current state struct" do
      state = ResourceArbiter.get_state()
      assert is_struct(state)
    end
  end

  describe "competitive allocation" do
    test "multipliers remain within valid range" do
      # Get multipliers for multiple sensors
      sensors = for i <- 1..5, do: "test_sensor_#{i}"

      multipliers = Enum.map(sensors, &ResourceArbiter.get_multiplier/1)

      # All multipliers should be between 0.5 and 5.0
      for mult <- multipliers do
        assert mult >= 0.5 and mult <= 5.0
      end
    end
  end
end
