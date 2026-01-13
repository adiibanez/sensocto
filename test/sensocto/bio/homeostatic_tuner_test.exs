defmodule Sensocto.Bio.HomeostaticTunerTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.HomeostaticTuner

  describe "get_offsets/0" do
    test "returns offset map with expected keys" do
      offsets = HomeostaticTuner.get_offsets()

      assert is_map(offsets)
      assert Map.has_key?(offsets, :elevated)
      assert Map.has_key?(offsets, :high)
      assert Map.has_key?(offsets, :critical)
    end

    test "returns float values" do
      offsets = HomeostaticTuner.get_offsets()

      assert is_float(offsets.elevated) or is_integer(offsets.elevated)
      assert is_float(offsets.high) or is_integer(offsets.high)
      assert is_float(offsets.critical) or is_integer(offsets.critical)
    end
  end

  describe "get_target_distribution/0" do
    test "returns target distribution map" do
      dist = HomeostaticTuner.get_target_distribution()

      assert is_map(dist)
      # Should have keys for different load levels
      assert Map.has_key?(dist, :normal) or Map.has_key?(dist, :elevated)
    end
  end

  describe "record_sample/1" do
    test "accepts load level samples" do
      assert :ok == HomeostaticTuner.record_sample(:normal)
      assert :ok == HomeostaticTuner.record_sample(:elevated)
      assert :ok == HomeostaticTuner.record_sample(:high)
      assert :ok == HomeostaticTuner.record_sample(:critical)
    end
  end

  describe "get_state/0" do
    test "returns current state struct" do
      state = HomeostaticTuner.get_state()
      assert is_struct(state)
    end
  end

  describe "threshold self-tuning" do
    test "offsets remain bounded after many samples" do
      # Record many samples
      for _ <- 1..20 do
        HomeostaticTuner.record_sample(:normal)
      end

      for _ <- 1..5 do
        HomeostaticTuner.record_sample(:elevated)
      end

      Process.sleep(100)

      offsets = HomeostaticTuner.get_offsets()

      # Offsets should be bounded within reasonable range
      assert offsets.elevated >= -0.3 and offsets.elevated <= 0.3
      assert offsets.high >= -0.3 and offsets.high <= 0.3
      assert offsets.critical >= -0.3 and offsets.critical <= 0.3
    end
  end
end
