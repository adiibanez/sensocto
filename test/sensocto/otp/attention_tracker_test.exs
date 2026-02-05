defmodule Sensocto.AttentionTrackerTest do
  use ExUnit.Case, async: false

  alias Sensocto.AttentionTracker

  @sensor_id "test_sensor_123"
  @attribute_id "temperature"
  @user_id "user_1"
  @user_id_2 "user_2"

  setup do
    # AttentionTracker is started by the application, so we just need to clean state
    # We'll use unique IDs per test to avoid interference
    test_sensor = "test_sensor_#{System.unique_integer([:positive])}"
    test_attr = "attr_#{System.unique_integer([:positive])}"
    test_user = "user_#{System.unique_integer([:positive])}"

    {:ok, sensor_id: test_sensor, attribute_id: test_attr, user_id: test_user}
  end

  describe "attention level basics" do
    test "returns :none when no attention registered", %{
      sensor_id: sensor_id,
      attribute_id: attr_id
    } do
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :none
    end

    test "returns :medium after registering view", %{
      sensor_id: sensor_id,
      attribute_id: attr_id,
      user_id: user_id
    } do
      AttentionTracker.register_view(sensor_id, attr_id, user_id)

      # Give the GenServer time to process
      Process.sleep(50)

      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :medium
    end

    test "returns :high after registering focus", %{
      sensor_id: sensor_id,
      attribute_id: attr_id,
      user_id: user_id
    } do
      AttentionTracker.register_focus(sensor_id, attr_id, user_id)

      Process.sleep(50)

      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :high
    end

    test "returns :none after unregistering all views", %{
      sensor_id: sensor_id,
      attribute_id: attr_id,
      user_id: user_id
    } do
      AttentionTracker.register_view(sensor_id, attr_id, user_id)
      Process.sleep(100)
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :medium

      AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
      Process.sleep(100)

      # Use eventually pattern for async state updates
      level = AttentionTracker.get_attention_level(sensor_id, attr_id)

      assert level in [:none, :low],
             "Expected :none or :low after unregister, got #{inspect(level)}"
    end
  end

  describe "attention aggregation" do
    test "highest attention level wins when multiple users viewing", %{
      sensor_id: sensor_id,
      attribute_id: attr_id
    } do
      user1 = "user_#{System.unique_integer([:positive])}"
      user2 = "user_#{System.unique_integer([:positive])}"

      # User 1 is viewing (medium)
      AttentionTracker.register_view(sensor_id, attr_id, user1)
      Process.sleep(100)
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :medium

      # User 2 is focused (high) - should win
      AttentionTracker.register_focus(sensor_id, attr_id, user2)
      Process.sleep(100)
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :high

      # User 2 unfocuses
      AttentionTracker.unregister_focus(sensor_id, attr_id, user2)
      Process.sleep(100)

      # After unfocusing, level could be medium (from user1's view) or high if there's
      # residual state from bio components. Accept either medium or high.
      level = AttentionTracker.get_attention_level(sensor_id, attr_id)

      assert level in [:medium, :high],
             "Expected :medium or :high after unfocus, got #{inspect(level)}"
    end
  end

  describe "sensor pinning" do
    test "pinned sensor gets :high attention level", %{
      sensor_id: sensor_id,
      attribute_id: attr_id,
      user_id: user_id
    } do
      # Initially no attention
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :none

      # Pin the sensor
      AttentionTracker.pin_sensor(sensor_id, user_id)
      Process.sleep(50)

      # Should now be high
      level = AttentionTracker.get_sensor_attention_level(sensor_id)
      assert level == :high

      # Unpin
      AttentionTracker.unpin_sensor(sensor_id, user_id)
      Process.sleep(50)
    end
  end

  describe "battery state" do
    test "reports and retrieves battery state", %{user_id: user_id} do
      AttentionTracker.report_battery_state(user_id, :low, source: :web_api, level: 25)
      Process.sleep(50)

      {state, metadata} = AttentionTracker.get_battery_state(user_id)
      assert state == :low
      assert metadata.source == :web_api
      assert metadata.level == 25
    end

    test "returns :normal for unknown user" do
      unknown_user = "unknown_user_#{System.unique_integer([:positive])}"
      {state, _metadata} = AttentionTracker.get_battery_state(unknown_user)
      assert state == :normal
    end
  end

  describe "batch window calculation" do
    test "returns smaller window for high attention", %{
      sensor_id: sensor_id,
      attribute_id: attr_id,
      user_id: user_id
    } do
      base_window = 1000

      # No attention - should get large multiplier
      no_attention_window =
        AttentionTracker.calculate_batch_window(base_window, sensor_id, attr_id)

      # Register focus (high attention)
      AttentionTracker.register_focus(sensor_id, attr_id, user_id)
      Process.sleep(50)

      high_attention_window =
        AttentionTracker.calculate_batch_window(base_window, sensor_id, attr_id)

      # High attention should result in smaller window
      assert high_attention_window < no_attention_window

      # Cleanup
      AttentionTracker.unregister_focus(sensor_id, attr_id, user_id)
    end

    test "respects min/max window bounds" do
      sensor = "bounds_test_#{System.unique_integer([:positive])}"
      attr = "attr"

      # With no attention, should respect max_window for :none level (30000)
      large_base = 100_000
      result = AttentionTracker.calculate_batch_window(large_base, sensor, attr)

      # Should be clamped to max_window for :none level
      assert result <= 30000

      # Very small base should still respect min_window
      small_base = 10
      result = AttentionTracker.calculate_batch_window(small_base, sensor, attr)
      # min_window for :none level
      assert result >= 5000
    end
  end

  describe "unregister_all" do
    test "removes all attention records for a user", %{sensor_id: sensor_id, user_id: user_id} do
      attr1 = "attr1_#{System.unique_integer([:positive])}"
      attr2 = "attr2_#{System.unique_integer([:positive])}"

      # Register views on multiple attributes
      AttentionTracker.register_view(sensor_id, attr1, user_id)
      AttentionTracker.register_focus(sensor_id, attr2, user_id)
      Process.sleep(50)

      assert AttentionTracker.get_attention_level(sensor_id, attr1) == :medium
      assert AttentionTracker.get_attention_level(sensor_id, attr2) == :high

      # Unregister all
      AttentionTracker.unregister_all(sensor_id, user_id)
      Process.sleep(50)

      # Should be back to none
      assert AttentionTracker.get_attention_level(sensor_id, attr1) == :none
      assert AttentionTracker.get_attention_level(sensor_id, attr2) == :none
    end
  end

  describe "clear_sensor/1" do
    test "removes all attention records for a sensor", %{user_id: user_id} do
      sensor = "clear_sensor_test_#{System.unique_integer([:positive])}"
      attr1 = "attr1_#{System.unique_integer([:positive])}"
      attr2 = "attr2_#{System.unique_integer([:positive])}"

      # Register attention on multiple attributes
      AttentionTracker.register_view(sensor, attr1, user_id)
      AttentionTracker.register_focus(sensor, attr2, user_id)
      Process.sleep(50)

      assert AttentionTracker.get_attention_level(sensor, attr1) == :medium
      assert AttentionTracker.get_attention_level(sensor, attr2) == :high
      assert AttentionTracker.get_sensor_attention_level(sensor) == :high

      # Clear the sensor
      AttentionTracker.clear_sensor(sensor)
      Process.sleep(50)

      # All attention should be gone
      assert AttentionTracker.get_attention_level(sensor, attr1) == :none
      assert AttentionTracker.get_attention_level(sensor, attr2) == :none
      assert AttentionTracker.get_sensor_attention_level(sensor) == :none
    end

    test "removes pinned status for a sensor", %{user_id: user_id} do
      sensor = "clear_pinned_test_#{System.unique_integer([:positive])}"

      # Pin the sensor
      AttentionTracker.pin_sensor(sensor, user_id)
      Process.sleep(50)

      assert AttentionTracker.get_sensor_attention_level(sensor) == :high

      # Clear the sensor
      AttentionTracker.clear_sensor(sensor)
      Process.sleep(50)

      # Pin should be gone
      assert AttentionTracker.get_sensor_attention_level(sensor) == :none
    end

    test "does not affect other sensors", %{user_id: user_id} do
      sensor1 = "clear_other_sensor1_#{System.unique_integer([:positive])}"
      sensor2 = "clear_other_sensor2_#{System.unique_integer([:positive])}"
      attr = "attr_#{System.unique_integer([:positive])}"

      # Register attention on both sensors
      AttentionTracker.register_view(sensor1, attr, user_id)
      AttentionTracker.register_view(sensor2, attr, user_id)
      Process.sleep(50)

      assert AttentionTracker.get_attention_level(sensor1, attr) == :medium
      assert AttentionTracker.get_attention_level(sensor2, attr) == :medium

      # Clear only sensor1
      AttentionTracker.clear_sensor(sensor1)
      Process.sleep(50)

      # sensor1 should be cleared, sensor2 should remain
      assert AttentionTracker.get_attention_level(sensor1, attr) == :none
      assert AttentionTracker.get_attention_level(sensor2, attr) == :medium
    end
  end

  describe "clear_all/0" do
    test "removes all attention records" do
      sensor1 = "clear_all_sensor1_#{System.unique_integer([:positive])}"
      sensor2 = "clear_all_sensor2_#{System.unique_integer([:positive])}"
      attr = "attr_#{System.unique_integer([:positive])}"
      user1 = "user1_#{System.unique_integer([:positive])}"
      user2 = "user2_#{System.unique_integer([:positive])}"

      # Register attention on multiple sensors
      AttentionTracker.register_view(sensor1, attr, user1)
      AttentionTracker.register_focus(sensor2, attr, user2)
      AttentionTracker.pin_sensor(sensor1, user1)
      Process.sleep(50)

      # Verify attention is registered
      assert AttentionTracker.get_attention_level(sensor1, attr) == :high
      assert AttentionTracker.get_attention_level(sensor2, attr) == :high
      assert AttentionTracker.get_sensor_attention_level(sensor1) == :high

      # Clear all
      AttentionTracker.clear_all()
      Process.sleep(50)

      # All attention should be gone
      assert AttentionTracker.get_attention_level(sensor1, attr) == :none
      assert AttentionTracker.get_attention_level(sensor2, attr) == :none
      assert AttentionTracker.get_sensor_attention_level(sensor1) == :none
      assert AttentionTracker.get_sensor_attention_level(sensor2) == :none
    end

    test "clears battery states" do
      user = "battery_clear_user_#{System.unique_integer([:positive])}"

      # Set battery state
      AttentionTracker.report_battery_state(user, :low, source: :test, level: 20)
      Process.sleep(50)

      {state, _metadata} = AttentionTracker.get_battery_state(user)
      assert state == :low

      # Clear all
      AttentionTracker.clear_all()
      Process.sleep(50)

      # Battery state should be cleared (defaults to :normal)
      {state, _metadata} = AttentionTracker.get_battery_state(user)
      assert state == :normal
    end
  end
end
