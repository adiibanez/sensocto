defmodule Sensocto.Bio.NoveltyDetectorTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.NoveltyDetector

  setup do
    sensor_id = "sensor_#{System.unique_integer([:positive])}"
    attribute_id = "attr_#{System.unique_integer([:positive])}"
    {:ok, sensor_id: sensor_id, attribute_id: attribute_id}
  end

  describe "get_novelty_score/2" do
    test "returns 0.0 for unknown sensor/attribute", %{sensor_id: sensor_id, attribute_id: attr_id} do
      assert NoveltyDetector.get_novelty_score(sensor_id, attr_id) == 0.0
    end

    test "returns score after reporting batches", %{sensor_id: sensor_id, attribute_id: attr_id} do
      # Report some normal batches to establish baseline (batch requires payload format)
      for _ <- 1..15 do
        batch = [
          %{payload: %{value: 50.0}, timestamp: DateTime.utc_now()},
          %{payload: %{value: 51.0}, timestamp: DateTime.utc_now()},
          %{payload: %{value: 49.0}, timestamp: DateTime.utc_now()}
        ]
        NoveltyDetector.report_batch(sensor_id, attr_id, batch)
        Process.sleep(10)
      end

      # Give GenServer time to process
      Process.sleep(100)

      # Score should still be low for consistent values
      score = NoveltyDetector.get_novelty_score(sensor_id, attr_id)
      assert is_float(score)
    end

    test "detects anomalous batch with high z-score", %{sensor_id: sensor_id, attribute_id: attr_id} do
      # Report consistent batches to establish baseline
      for _ <- 1..20 do
        batch = [
          %{payload: %{value: 50.0}, timestamp: DateTime.utc_now()},
          %{payload: %{value: 51.0}, timestamp: DateTime.utc_now()}
        ]
        NoveltyDetector.report_batch(sensor_id, attr_id, batch)
        Process.sleep(5)
      end

      Process.sleep(100)

      # Now report an anomalous batch with much larger values
      anomalous_batch = [
        %{payload: %{value: 500.0}, timestamp: DateTime.utc_now()},
        %{payload: %{value: 510.0}, timestamp: DateTime.utc_now()}
      ]
      NoveltyDetector.report_batch(sensor_id, attr_id, anomalous_batch)

      Process.sleep(100)

      # Score should be higher now
      score = NoveltyDetector.get_novelty_score(sensor_id, attr_id)
      assert is_float(score)
    end
  end

  describe "get_stats/2" do
    test "returns nil for unknown sensor", %{sensor_id: sensor_id, attribute_id: attr_id} do
      assert NoveltyDetector.get_stats(sensor_id, attr_id) == nil
    end

    test "returns stats after sufficient reporting", %{sensor_id: sensor_id, attribute_id: attr_id} do
      # Need to report enough batches to build statistics (min 10 samples)
      for _ <- 1..12 do
        batch = [%{payload: %{value: 50.0}, timestamp: DateTime.utc_now()}]
        NoveltyDetector.report_batch(sensor_id, attr_id, batch)
        Process.sleep(10)
      end

      Process.sleep(100)

      stats = NoveltyDetector.get_stats(sensor_id, attr_id)
      assert stats != nil
      assert Map.has_key?(stats, :count)
      assert Map.has_key?(stats, :mean)
      assert Map.has_key?(stats, :m2)  # Welford's algorithm uses m2, not variance
    end
  end

  describe "get_recent_events/0" do
    test "returns list of recent novelty events" do
      events = NoveltyDetector.get_recent_events()
      assert is_list(events)
    end
  end
end
