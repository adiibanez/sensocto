defmodule Sensocto.Bio.PredictiveLoadBalancerTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.PredictiveLoadBalancer

  setup do
    sensor_id = "sensor_#{System.unique_integer([:positive])}"
    {:ok, sensor_id: sensor_id}
  end

  describe "get_predictive_factor/1" do
    test "returns 1.0 for unknown sensor", %{sensor_id: sensor_id} do
      assert PredictiveLoadBalancer.get_predictive_factor(sensor_id) == 1.0
    end

    test "returns float value", %{sensor_id: sensor_id} do
      factor = PredictiveLoadBalancer.get_predictive_factor(sensor_id)
      assert is_float(factor) or is_integer(factor)
      assert factor > 0
    end
  end

  describe "record_attention/2" do
    test "records attention for sensor", %{sensor_id: sensor_id} do
      assert :ok == PredictiveLoadBalancer.record_attention(sensor_id, :high)
    end

    test "accepts different attention levels", %{sensor_id: sensor_id} do
      assert :ok == PredictiveLoadBalancer.record_attention(sensor_id, :none)
      assert :ok == PredictiveLoadBalancer.record_attention(sensor_id, :medium)
      assert :ok == PredictiveLoadBalancer.record_attention(sensor_id, :high)
    end
  end

  describe "get_patterns/1" do
    test "returns patterns for sensor", %{sensor_id: sensor_id} do
      # Record some attention first
      PredictiveLoadBalancer.record_attention(sensor_id, :high)
      Process.sleep(50)

      patterns = PredictiveLoadBalancer.get_patterns(sensor_id)
      # Can be nil or a map depending on state
      assert is_nil(patterns) or is_map(patterns) or is_list(patterns)
    end
  end

  describe "get_predictions/0" do
    test "returns predictions map" do
      predictions = PredictiveLoadBalancer.get_predictions()
      assert is_map(predictions)
    end
  end

  describe "temporal pattern learning" do
    test "learns from repeated attention patterns", %{sensor_id: sensor_id} do
      # Simulate attention pattern
      for _ <- 1..5 do
        PredictiveLoadBalancer.record_attention(sensor_id, :high)
        Process.sleep(10)
      end

      Process.sleep(100)

      # Factor should still be valid
      factor = PredictiveLoadBalancer.get_predictive_factor(sensor_id)
      assert factor >= 0.75 and factor <= 1.2
    end
  end
end
