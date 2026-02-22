defmodule Sensocto.Bio.CorrelationTrackerTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.CorrelationTracker

  setup do
    sensor_a = "sensor_#{System.unique_integer([:positive])}"
    sensor_b = "sensor_#{System.unique_integer([:positive])}"
    sensor_c = "sensor_#{System.unique_integer([:positive])}"
    {:ok, sensor_a: sensor_a, sensor_b: sensor_b, sensor_c: sensor_c}
  end

  describe "record_co_access/1" do
    test "records co-access for sensor pairs", %{sensor_a: a, sensor_b: b} do
      assert :ok == CorrelationTracker.record_co_access([a, b])
    end

    test "ignores single-sensor lists" do
      assert :ok == CorrelationTracker.record_co_access(["only_one"])
    end

    test "ignores empty lists" do
      assert :ok == CorrelationTracker.record_co_access([])
    end
  end

  describe "get_strength/2" do
    test "returns 0.0 for uncorrelated sensors", %{sensor_a: a, sensor_b: b} do
      assert CorrelationTracker.get_strength(a, b) == 0.0
    end

    test "increases after co-access", %{sensor_a: a, sensor_b: b} do
      CorrelationTracker.record_co_access([a, b])
      Process.sleep(50)

      strength = CorrelationTracker.get_strength(a, b)
      assert strength > 0.0
    end

    test "is symmetric", %{sensor_a: a, sensor_b: b} do
      CorrelationTracker.record_co_access([a, b])
      Process.sleep(50)

      assert CorrelationTracker.get_strength(a, b) ==
               CorrelationTracker.get_strength(b, a)
    end

    test "strengthens with repeated co-access", %{sensor_a: a, sensor_b: b} do
      CorrelationTracker.record_co_access([a, b])
      Process.sleep(50)
      first = CorrelationTracker.get_strength(a, b)

      CorrelationTracker.record_co_access([a, b])
      Process.sleep(50)
      second = CorrelationTracker.get_strength(a, b)

      assert second > first
    end
  end

  describe "get_correlated/1" do
    test "returns empty list for unknown sensor", %{sensor_a: a} do
      assert CorrelationTracker.get_correlated(a) == []
    end

    test "returns correlated sensors above threshold", %{sensor_a: a, sensor_b: b, sensor_c: c} do
      # Build up enough correlation to exceed threshold (0.3)
      for _ <- 1..5 do
        CorrelationTracker.record_co_access([a, b, c])
        Process.sleep(10)
      end

      Process.sleep(50)

      correlated = CorrelationTracker.get_correlated(a)
      peer_ids = Enum.map(correlated, fn {id, _strength} -> id end)

      assert b in peer_ids
      assert c in peer_ids
    end

    test "returns results sorted by strength descending", %{sensor_a: a, sensor_b: b, sensor_c: c} do
      # Make a-b stronger than a-c
      for _ <- 1..5 do
        CorrelationTracker.record_co_access([a, b])
        Process.sleep(5)
      end

      for _ <- 1..2 do
        CorrelationTracker.record_co_access([a, c])
        Process.sleep(5)
      end

      Process.sleep(50)

      correlated = CorrelationTracker.get_correlated(a)
      strengths = Enum.map(correlated, fn {_id, strength} -> strength end)

      assert strengths == Enum.sort(strengths, :desc)
    end
  end

  describe "get_all_correlations/0" do
    test "returns map of all correlations" do
      correlations = CorrelationTracker.get_all_correlations()
      assert is_map(correlations)
    end
  end
end
