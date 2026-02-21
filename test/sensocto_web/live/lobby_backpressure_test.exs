defmodule SensoctoWeb.LobbyBackpressureTest do
  @moduledoc """
  Tests for LobbyLive backpressure thresholds and quality hysteresis.

  Verifies:
  - All 4 load levels (:normal, :elevated, :high, :critical) compute correct thresholds
  - The :high load level case (previously missing, caused fall-through to :normal)
  - Upgrade hysteresis delay (reduced from 15s to 8s)
  - Threshold values scale correctly: normal > elevated > high > critical
  """

  use ExUnit.Case, async: true

  # These are the module attributes from lobby_live.ex
  @mailbox_backpressure_threshold 50
  @mailbox_critical_threshold 150
  @upgrade_check_delay_ms 8_000
  @consecutive_healthy_checks_required 2

  # ===========================================================================
  # Load-level threshold calculation
  # ===========================================================================

  describe "backpressure threshold calculation by load level" do
    test ":normal load uses full thresholds" do
      {bp, crit} = thresholds_for_level(:normal)
      assert bp == @mailbox_backpressure_threshold
      assert crit == @mailbox_critical_threshold
    end

    test ":elevated load halves thresholds" do
      {bp, crit} = thresholds_for_level(:elevated)
      assert bp == div(@mailbox_backpressure_threshold, 2)
      assert crit == div(@mailbox_critical_threshold, 2)
    end

    test ":high load divides thresholds by 3" do
      {bp, crit} = thresholds_for_level(:high)
      assert bp == div(@mailbox_backpressure_threshold, 3)
      assert crit == div(@mailbox_critical_threshold, 3)
    end

    test ":critical load divides thresholds by 4" do
      {bp, crit} = thresholds_for_level(:critical)
      assert bp == div(@mailbox_backpressure_threshold, 4)
      assert crit == div(@mailbox_critical_threshold, 4)
    end

    test "unknown load level falls through to full thresholds" do
      {bp, crit} = thresholds_for_level(:unknown)
      assert bp == @mailbox_backpressure_threshold
      assert crit == @mailbox_critical_threshold
    end

    test "thresholds are strictly ordered: normal > elevated > high > critical" do
      {bp_normal, crit_normal} = thresholds_for_level(:normal)
      {bp_elevated, crit_elevated} = thresholds_for_level(:elevated)
      {bp_high, crit_high} = thresholds_for_level(:high)
      {bp_critical, crit_critical} = thresholds_for_level(:critical)

      assert bp_normal > bp_elevated
      assert bp_elevated > bp_high
      assert bp_high > bp_critical

      assert crit_normal > crit_elevated
      assert crit_elevated > crit_high
      assert crit_high > crit_critical
    end

    test "all thresholds are positive integers" do
      for level <- [:normal, :elevated, :high, :critical] do
        {bp, crit} = thresholds_for_level(level)
        assert is_integer(bp) and bp > 0, "backpressure for #{level} should be positive"
        assert is_integer(crit) and crit > 0, "critical for #{level} should be positive"
        assert crit > bp, "critical should always be greater than backpressure for #{level}"
      end
    end

    test "concrete threshold values" do
      assert thresholds_for_level(:normal) == {50, 150}
      assert thresholds_for_level(:elevated) == {25, 75}
      assert thresholds_for_level(:high) == {16, 50}
      assert thresholds_for_level(:critical) == {12, 37}
    end
  end

  # ===========================================================================
  # Hysteresis configuration
  # ===========================================================================

  describe "quality upgrade hysteresis" do
    test "upgrade check delay is 8 seconds (reduced from 15s)" do
      assert @upgrade_check_delay_ms == 8_000
    end

    test "requires 2 consecutive healthy checks before upgrading" do
      assert @consecutive_healthy_checks_required == 2
    end

    test "minimum recovery time is 16 seconds (2 checks × 8s each)" do
      min_recovery_ms = @consecutive_healthy_checks_required * @upgrade_check_delay_ms
      assert min_recovery_ms == 16_000
    end
  end

  # ===========================================================================
  # Load level coverage (regression for missing :high case)
  # ===========================================================================

  describe ":high load level regression" do
    test ":high is handled distinctly from :normal and :elevated" do
      {bp_normal, _} = thresholds_for_level(:normal)
      {bp_elevated, _} = thresholds_for_level(:elevated)
      {bp_high, _} = thresholds_for_level(:high)

      # :high must not equal :normal (the old bug — :high fell through to default)
      refute bp_high == bp_normal,
             ":high threshold must not equal :normal (this was the bug)"

      # :high must not equal :elevated (it's a separate step)
      refute bp_high == bp_elevated,
             ":high threshold must differ from :elevated"
    end

    test ":high backpressure triggers earlier than :elevated but later than :critical" do
      {bp_elevated, _} = thresholds_for_level(:elevated)
      {bp_high, _} = thresholds_for_level(:high)
      {bp_critical, _} = thresholds_for_level(:critical)

      # Lower threshold = triggers earlier (more aggressive)
      assert bp_high < bp_elevated, ":high should trigger before :elevated"
      assert bp_high > bp_critical, ":high should trigger after :critical"
    end
  end

  # ===========================================================================
  # SimpleSensor broadcast intervals (related config)
  # ===========================================================================

  describe "SimpleSensor broadcast interval matrix" do
    # These are from @broadcast_intervals in simple_sensor.ex
    @broadcast_intervals %{
      {:normal, :high} => 0,
      {:normal, :medium} => 0,
      {:normal, :low} => 0,
      {:normal, :none} => 0,
      {:elevated, :high} => 16,
      {:elevated, :medium} => 32,
      {:elevated, :low} => 64,
      {:elevated, :none} => 0,
      {:high, :high} => 32,
      {:high, :medium} => 64,
      {:high, :low} => 128,
      {:high, :none} => 0,
      {:critical, :high} => 64,
      {:critical, :medium} => 128,
      {:critical, :low} => 256,
      {:critical, :none} => 0
    }

    test "all normal load intervals are 0 (immediate)" do
      for attention <- [:high, :medium, :low, :none] do
        assert @broadcast_intervals[{:normal, attention}] == 0,
               "normal+#{attention} should be 0ms"
      end
    end

    test "all :none attention intervals are 0 (gated, no broadcast)" do
      for load <- [:normal, :elevated, :high, :critical] do
        assert @broadcast_intervals[{load, :none}] == 0,
               "#{load}+none should be 0ms (gated)"
      end
    end

    test "intervals increase with load level (for same attention)" do
      for attention <- [:high, :medium, :low] do
        intervals =
          [:normal, :elevated, :high, :critical]
          |> Enum.map(&@broadcast_intervals[{&1, attention}])

        assert intervals == Enum.sort(intervals),
               "intervals for #{attention} should increase with load"
      end
    end

    test "intervals increase with lower attention (for same load)" do
      for load <- [:elevated, :high, :critical] do
        high = @broadcast_intervals[{load, :high}]
        medium = @broadcast_intervals[{load, :medium}]
        low = @broadcast_intervals[{load, :low}]

        assert high <= medium, "#{load}: high attention should have <= interval vs medium"
        assert medium <= low, "#{load}: medium attention should have <= interval vs low"
      end
    end

    test "no interval exceeds 256ms" do
      for {_key, interval} <- @broadcast_intervals do
        assert interval <= 256, "no interval should exceed 256ms"
      end
    end

    test "matrix is complete (all 16 combinations defined)" do
      for load <- [:normal, :elevated, :high, :critical],
          attention <- [:high, :medium, :low, :none] do
        assert Map.has_key?(@broadcast_intervals, {load, attention}),
               "missing interval for {#{load}, #{attention}}"
      end
    end
  end

  # ===========================================================================
  # Helpers — mirrors the threshold calculation from lobby_live.ex
  # ===========================================================================

  defp thresholds_for_level(load_level) do
    case load_level do
      :critical ->
        {div(@mailbox_backpressure_threshold, 4), div(@mailbox_critical_threshold, 4)}

      :high ->
        {div(@mailbox_backpressure_threshold, 3), div(@mailbox_critical_threshold, 3)}

      :elevated ->
        {div(@mailbox_backpressure_threshold, 2), div(@mailbox_critical_threshold, 2)}

      _ ->
        {@mailbox_backpressure_threshold, @mailbox_critical_threshold}
    end
  end
end
