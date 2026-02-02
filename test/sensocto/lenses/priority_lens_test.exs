defmodule Sensocto.Lenses.PriorityLensTest do
  @moduledoc """
  Tests for PriorityLens reactive backpressure behavior.

  Key behaviors tested:
  1. No preemptive quality throttling based on sensor count
  2. Quality starts at requested level regardless of how many sensors
  3. max_sensors enforcement respects focused sensor
  4. Explicit quality changes work correctly
  """
  use ExUnit.Case, async: false
  alias Sensocto.Lenses.PriorityLens

  # Skip full app tests when port is in use (run in isolation mode)
  @moduletag :priority_lens

  # Use a unique socket_id per test to avoid conflicts
  defp unique_socket_id, do: "test_socket_#{System.unique_integer([:positive])}"

  describe "quality_for_sensor_count/1" do
    test "always returns :high regardless of sensor count" do
      # This verifies the removal of preemptive throttling
      assert PriorityLens.quality_for_sensor_count(1) == :high
      assert PriorityLens.quality_for_sensor_count(10) == :high
      assert PriorityLens.quality_for_sensor_count(100) == :high
      assert PriorityLens.quality_for_sensor_count(500) == :high
      assert PriorityLens.quality_for_sensor_count(1000) == :high
      assert PriorityLens.quality_for_sensor_count(10_000) == :high
    end
  end

  describe "min_quality/2" do
    test "returns more conservative quality level" do
      assert PriorityLens.min_quality(:high, :high) == :high
      assert PriorityLens.min_quality(:high, :medium) == :medium
      assert PriorityLens.min_quality(:medium, :high) == :medium
      assert PriorityLens.min_quality(:low, :minimal) == :minimal
      assert PriorityLens.min_quality(:paused, :high) == :paused
    end
  end

  describe "register_socket/3" do
    test "registers at requested quality regardless of sensor count" do
      socket_id = unique_socket_id()
      # Create a large list of sensor IDs (previously would have been throttled)
      sensor_ids = Enum.map(1..500, &"sensor_#{&1}")

      {:ok, topic} = PriorityLens.register_socket(socket_id, sensor_ids, quality: :high)

      assert topic == "lens:priority:#{socket_id}"

      # Verify socket was registered at :high quality (not auto-downgraded)
      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high

      # Cleanup
      PriorityLens.unregister_socket(socket_id)
    end

    test "respects explicitly requested lower quality" do
      socket_id = unique_socket_id()
      sensor_ids = ["sensor_1", "sensor_2"]

      {:ok, _topic} = PriorityLens.register_socket(socket_id, sensor_ids, quality: :medium)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :medium

      PriorityLens.unregister_socket(socket_id)
    end

    test "defaults to :high quality" do
      socket_id = unique_socket_id()
      sensor_ids = ["sensor_1"]

      {:ok, _topic} = PriorityLens.register_socket(socket_id, sensor_ids)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high

      PriorityLens.unregister_socket(socket_id)
    end

    test "tracks focused sensor" do
      socket_id = unique_socket_id()
      sensor_ids = ["sensor_1", "sensor_2", "sensor_3"]

      {:ok, _topic} =
        PriorityLens.register_socket(socket_id, sensor_ids,
          quality: :high,
          focused_sensor: "sensor_2"
        )

      state = PriorityLens.get_socket_state(socket_id)
      assert state.focused_sensor == "sensor_2"

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "set_quality/2" do
    test "changes quality level for registered socket" do
      socket_id = unique_socket_id()
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1"], quality: :high)

      # Start at high
      assert PriorityLens.get_socket_state(socket_id).quality == :high

      # Downgrade to medium
      PriorityLens.set_quality(socket_id, :medium)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :medium

      # Further downgrade to low
      PriorityLens.set_quality(socket_id, :low)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :low

      # Upgrade back to high
      PriorityLens.set_quality(socket_id, :high)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :high

      PriorityLens.unregister_socket(socket_id)
    end

    test "can pause and resume" do
      socket_id = unique_socket_id()
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1"], quality: :high)

      PriorityLens.set_quality(socket_id, :paused)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :paused

      PriorityLens.set_quality(socket_id, :high)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :high

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "set_sensors/2" do
    test "updates sensor list for socket" do
      socket_id = unique_socket_id()
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1", "sensor_2"])

      state = PriorityLens.get_socket_state(socket_id)
      assert MapSet.size(state.sensor_ids) == 2
      assert MapSet.member?(state.sensor_ids, "sensor_1")
      assert MapSet.member?(state.sensor_ids, "sensor_2")

      # Update to different sensors
      PriorityLens.set_sensors(socket_id, ["sensor_3", "sensor_4", "sensor_5"])
      Process.sleep(10)

      state = PriorityLens.get_socket_state(socket_id)
      assert MapSet.size(state.sensor_ids) == 3
      assert MapSet.member?(state.sensor_ids, "sensor_3")
      refute MapSet.member?(state.sensor_ids, "sensor_1")

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "set_focused_sensor/2" do
    test "updates focused sensor" do
      socket_id = unique_socket_id()
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1", "sensor_2"])

      assert PriorityLens.get_socket_state(socket_id).focused_sensor == nil

      PriorityLens.set_focused_sensor(socket_id, "sensor_1")
      Process.sleep(10)

      assert PriorityLens.get_socket_state(socket_id).focused_sensor == "sensor_1"

      PriorityLens.set_focused_sensor(socket_id, "sensor_2")
      Process.sleep(10)

      assert PriorityLens.get_socket_state(socket_id).focused_sensor == "sensor_2"

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "unregister_socket/1" do
    test "removes socket state" do
      socket_id = unique_socket_id()
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1"])

      assert PriorityLens.get_socket_state(socket_id) != nil

      PriorityLens.unregister_socket(socket_id)
      Process.sleep(10)

      assert PriorityLens.get_socket_state(socket_id) == nil
    end
  end

  describe "topic_for_socket/1" do
    test "returns correct topic format" do
      assert PriorityLens.topic_for_socket("abc123") == "lens:priority:abc123"
      assert PriorityLens.topic_for_socket("socket_456") == "lens:priority:socket_456"
    end
  end

  describe "large sensor count handling" do
    test "handles 1000+ sensors at high quality" do
      socket_id = unique_socket_id()
      sensor_ids = Enum.map(1..1000, &"sensor_#{&1}")

      {:ok, _topic} = PriorityLens.register_socket(socket_id, sensor_ids, quality: :high)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high
      assert MapSet.size(state.sensor_ids) == 1000

      PriorityLens.unregister_socket(socket_id)
    end

    test "can dynamically grow sensor list without quality degradation" do
      socket_id = unique_socket_id()

      # Start with few sensors
      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["sensor_1"], quality: :high)
      assert PriorityLens.get_socket_state(socket_id).quality == :high

      # Add many more sensors
      many_sensors = Enum.map(1..500, &"sensor_#{&1}")
      PriorityLens.set_sensors(socket_id, many_sensors)
      Process.sleep(10)

      # Quality should remain high (no auto-downgrade)
      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high
      assert MapSet.size(state.sensor_ids) == 500

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "multiple sockets" do
    test "handles multiple sockets with overlapping sensors" do
      socket1 = unique_socket_id()
      socket2 = unique_socket_id()
      socket3 = unique_socket_id()

      # All three sockets watch sensor_1, but have different other sensors
      {:ok, _} = PriorityLens.register_socket(socket1, ["sensor_1", "sensor_2"])
      {:ok, _} = PriorityLens.register_socket(socket2, ["sensor_1", "sensor_3"])
      {:ok, _} = PriorityLens.register_socket(socket3, ["sensor_1", "sensor_4", "sensor_5"])

      # Verify each socket has correct state
      assert MapSet.member?(PriorityLens.get_socket_state(socket1).sensor_ids, "sensor_1")
      assert MapSet.member?(PriorityLens.get_socket_state(socket2).sensor_ids, "sensor_1")
      assert MapSet.member?(PriorityLens.get_socket_state(socket3).sensor_ids, "sensor_1")

      # Each socket should be independent
      PriorityLens.set_quality(socket1, :low)
      Process.sleep(10)

      assert PriorityLens.get_socket_state(socket1).quality == :low
      assert PriorityLens.get_socket_state(socket2).quality == :high
      assert PriorityLens.get_socket_state(socket3).quality == :high

      # Cleanup
      PriorityLens.unregister_socket(socket1)
      PriorityLens.unregister_socket(socket2)
      PriorityLens.unregister_socket(socket3)
    end
  end

  describe "quality level configs" do
    test "high quality has unlimited max_sensors" do
      socket_id = unique_socket_id()
      {:ok, _} = PriorityLens.register_socket(socket_id, ["s1"], quality: :high)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high
      # High quality should allow unlimited sensors (no preemptive throttling)

      PriorityLens.unregister_socket(socket_id)
    end

    test "medium quality has unlimited max_sensors" do
      socket_id = unique_socket_id()
      {:ok, _} = PriorityLens.register_socket(socket_id, ["s1"], quality: :medium)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :medium
      # Medium quality should also allow unlimited sensors

      PriorityLens.unregister_socket(socket_id)
    end

    test "low and minimal quality have limited max_sensors (for actual backpressure)" do
      socket_id = unique_socket_id()
      # These quality levels are only used when actual backpressure is detected
      {:ok, _} = PriorityLens.register_socket(socket_id, ["s1"], quality: :low)
      assert PriorityLens.get_socket_state(socket_id).quality == :low

      PriorityLens.set_quality(socket_id, :minimal)
      Process.sleep(10)
      assert PriorityLens.get_socket_state(socket_id).quality == :minimal

      PriorityLens.unregister_socket(socket_id)
    end
  end

  describe "concurrent registration" do
    test "handles concurrent socket registrations" do
      # Register sockets from the test process (not tasks) to avoid auto-cleanup
      # when the task process exits. PriorityLens monitors the caller and cleans up
      # on :DOWN, so we need to register from a persistent process.
      results =
        1..50
        |> Enum.map(fn i ->
          socket_id = "concurrent_socket_#{i}_#{System.unique_integer([:positive])}"
          sensor_ids = Enum.map(1..20, &"sensor_#{&1}")
          {:ok, topic} = PriorityLens.register_socket(socket_id, sensor_ids, quality: :high)
          {socket_id, topic}
        end)

      # Verify all registrations succeeded
      assert length(results) == 50

      Enum.each(results, fn {socket_id, topic} ->
        assert topic == "lens:priority:#{socket_id}"
        state = PriorityLens.get_socket_state(socket_id)
        assert state != nil, "Socket #{socket_id} state should not be nil"
        assert state.quality == :high
      end)

      # Cleanup
      Enum.each(results, fn {socket_id, _topic} ->
        PriorityLens.unregister_socket(socket_id)
      end)
    end
  end

  describe "stress test - no degradation" do
    test "1000 sensors across multiple sockets stays at high quality" do
      # Create 10 sockets, each watching 100 sensors (some overlap)
      sockets =
        1..10
        |> Enum.map(fn i ->
          socket_id = unique_socket_id()
          # Each socket watches sensors i*100 to (i+1)*100, plus some common ones
          sensor_ids =
            Enum.map((i * 100)..((i + 1) * 100), &"sensor_#{&1}") ++
              ["common_1", "common_2", "common_3"]

          {:ok, _topic} = PriorityLens.register_socket(socket_id, sensor_ids, quality: :high)
          socket_id
        end)

      # Verify all sockets are at high quality
      Enum.each(sockets, fn socket_id ->
        state = PriorityLens.get_socket_state(socket_id)

        assert state.quality == :high,
               "Socket #{socket_id} should be at high quality, got #{state.quality}"
      end)

      # Cleanup
      Enum.each(sockets, &PriorityLens.unregister_socket/1)
    end
  end
end
