defmodule Sensocto.Bio.CircadianSchedulerTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.CircadianScheduler

  describe "get_phase_adjustment/0" do
    test "returns float value" do
      adjustment = CircadianScheduler.get_phase_adjustment()
      assert is_float(adjustment) or is_integer(adjustment)
    end

    test "returns value within expected range" do
      adjustment = CircadianScheduler.get_phase_adjustment()
      # Should be between 0.85 (off_peak boost) and 1.2 (peak throttle)
      assert adjustment >= 0.85 and adjustment <= 1.2
    end
  end

  describe "get_phase/0" do
    test "returns valid phase atom" do
      phase = CircadianScheduler.get_phase()

      valid_phases = [:unknown, :normal, :approaching_peak, :peak, :approaching_off_peak, :off_peak]
      assert phase in valid_phases
    end
  end

  describe "record_load/2" do
    test "accepts load level and pressure" do
      assert :ok == CircadianScheduler.record_load(:normal, 0.3)
      assert :ok == CircadianScheduler.record_load(:elevated, 0.5)
      assert :ok == CircadianScheduler.record_load(:high, 0.7)
      assert :ok == CircadianScheduler.record_load(:critical, 0.9)
    end
  end

  describe "get_profile/0" do
    test "returns hourly profile map" do
      profile = CircadianScheduler.get_profile()

      assert is_map(profile)
      # Should have entries for hours 0-23
      assert Map.has_key?(profile, 0)
      assert Map.has_key?(profile, 12)
      assert Map.has_key?(profile, 23)
    end

    test "profile values are between 0 and 1" do
      profile = CircadianScheduler.get_profile()

      for {_hour, value} <- profile do
        assert value >= 0.0 and value <= 1.0
      end
    end
  end

  describe "get_state/0" do
    test "returns current state struct" do
      state = CircadianScheduler.get_state()
      assert is_struct(state)
    end

    test "state contains expected fields" do
      state = CircadianScheduler.get_state()

      assert Map.has_key?(state, :hourly_profile)
      assert Map.has_key?(state, :current_phase)
      assert Map.has_key?(state, :phase_adjustment)
    end
  end

  describe "default profile" do
    test "has sensible daily pattern" do
      profile = CircadianScheduler.get_profile()

      # Night hours should have lower load expectation
      night_avg = (profile[2] + profile[3] + profile[4]) / 3
      # Day hours should have higher load expectation
      day_avg = (profile[9] + profile[10] + profile[14]) / 3

      assert day_avg > night_avg
    end
  end
end
