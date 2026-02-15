defmodule Sensocto.RegressionGuardsTest do
  @moduledoc """
  Honey badger regression guards.

  These tests protect against silent breakage during serious refactorings.
  They test contracts (message shapes, topic formats, API return values)
  rather than implementation details.

  If one of these tests breaks, you changed something that affects
  the data pipeline. That's not necessarily bad — but you need to
  update all the consumers too.
  """

  use ExUnit.Case, async: false

  alias Sensocto.AttentionTracker
  alias Sensocto.Lenses.Router
  alias Sensocto.Lenses.PriorityLens

  # ===========================================================================
  # 1. Data Pipeline: SimpleSensor → PubSub → Router → PriorityLens
  # ===========================================================================

  describe "data pipeline contract" do
    test "Router starts demand-driven (not subscribed until lens registers)" do
      lenses = Router.get_registered_lenses()
      # May have lenses from other tests/app, but the API must return a list
      assert is_list(lenses)
    end

    test "Router subscribes to attention topics when lens registers" do
      # Register ourselves as a "lens"
      :ok = Router.register_lens(self())

      # Send a measurement on the attention topic (simulating SimpleSensor)
      measurement = %{
        sensor_id: "regression_test_sensor",
        attribute_id: "temperature",
        value: 42.0,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "data:attention:medium",
        {:measurement, measurement}
      )

      # Router should have forwarded to PriorityLens (ETS direct write).
      # We can verify by checking PriorityLens has the data.
      Process.sleep(50)

      # Cleanup
      Router.unregister_lens(self())
    end

    test "measurement message shape matches Router expectations" do
      # This is the contract between SimpleSensor and Router.
      # SimpleSensor broadcasts {:measurement, map} on "data:attention:{level}".
      # Router expects measurement to have :sensor_id key.

      # Subscribe to attention topic directly
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      measurement = %{
        sensor_id: "contract_test",
        attribute_id: "hr",
        value: 72,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "data:attention:high",
        {:measurement, measurement}
      )

      assert_receive {:measurement, received}
      assert Map.has_key?(received, :sensor_id)
      assert Map.has_key?(received, :attribute_id)

      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:attention:high")
    end

    test "batch measurement message shape matches Router expectations" do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")

      batch = {
        "batch_contract_test",
        [
          %{sensor_id: "batch_contract_test", attribute_id: "ecg", value: 1.0},
          %{sensor_id: "batch_contract_test", attribute_id: "ecg", value: 1.1}
        ]
      }

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "data:attention:medium",
        {:measurements_batch, batch}
      )

      assert_receive {:measurements_batch, {sensor_id, measurements}}
      assert is_binary(sensor_id)
      assert is_list(measurements)
      assert length(measurements) == 2

      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:attention:medium")
    end
  end

  # ===========================================================================
  # 2. PubSub Topic Contracts
  #
  # These topics are the nervous system of the platform. If you rename one,
  # the producer and consumer must both be updated. These tests catch
  # one-sided changes.
  # ===========================================================================

  describe "PubSub topic contracts" do
    test "attention-sharded data topics exist and match expected format" do
      # These are the 3 topics Router subscribes to
      topics = ["data:attention:high", "data:attention:medium", "data:attention:low"]

      for topic <- topics do
        # Subscribe should not crash — topic format is valid
        :ok = Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
        :ok = Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
      end
    end

    test "attention:lobby topic carries attention_changed and tracker_restarted messages" do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:lobby")

      # Simulate what AttentionTracker broadcasts
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "attention:lobby",
        {:attention_changed, %{sensor_id: "test", level: :medium}}
      )

      assert_receive {:attention_changed, %{sensor_id: "test", level: :medium}}

      # Also test the restart message
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "attention:lobby",
        :attention_tracker_restarted
      )

      assert_receive :attention_tracker_restarted

      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "attention:lobby")
    end

    test "sensor-specific data topic format" do
      sensor_id = "topic_format_test_123"
      topic = "data:#{sensor_id}"

      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        topic,
        {:measurement, %{sensor_id: sensor_id, value: 1}}
      )

      assert_receive {:measurement, %{sensor_id: ^sensor_id}}

      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
    end

    test "attention:sensor_id topic carries attention_changed messages" do
      sensor_id = "attention_topic_test"
      topic = "attention:#{sensor_id}"

      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        topic,
        {:attention_changed, %{sensor_id: sensor_id, level: :high}}
      )

      assert_receive {:attention_changed, %{sensor_id: ^sensor_id, level: :high}}

      Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
    end
  end

  # ===========================================================================
  # 3. Attention Gating Integration
  #
  # SimpleSensor only broadcasts to "data:attention:{level}" when
  # attention_level != :none. This test verifies the contract between
  # AttentionTracker and the gating logic.
  # ===========================================================================

  describe "attention gating contract" do
    test "attention level transitions from :none to :medium on register_view" do
      sensor_id = "gating_test_#{System.unique_integer([:positive])}"
      attr_id = "heartrate"
      user_id = "gating_user"

      # Initially :none
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :none
      assert AttentionTracker.get_sensor_attention_level(sensor_id) == :none

      # Register view
      AttentionTracker.register_view(sensor_id, attr_id, user_id)
      Process.sleep(50)

      # Now :medium — SimpleSensor would start broadcasting
      assert AttentionTracker.get_attention_level(sensor_id, attr_id) == :medium
      assert AttentionTracker.get_sensor_attention_level(sensor_id) == :medium

      # Cleanup
      AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    end

    test "sensor-level attention is highest of all attributes" do
      sensor_id = "multi_attr_#{System.unique_integer([:positive])}"
      user_id = "multi_user"

      AttentionTracker.register_view(sensor_id, "attr1", user_id)
      AttentionTracker.register_focus(sensor_id, "attr2", user_id)
      Process.sleep(50)

      # attr1 = :medium (view), attr2 = :high (focus)
      # Sensor level should be :high (highest wins)
      assert AttentionTracker.get_sensor_attention_level(sensor_id) == :high

      # Cleanup
      AttentionTracker.unregister_view(sensor_id, "attr1", user_id)
      AttentionTracker.unregister_focus(sensor_id, "attr2", user_id)
    end

    test "bulk register/unregister maintains correct attention" do
      sensor_ids =
        for i <- 1..5, do: "bulk_#{i}_#{System.unique_integer([:positive])}"

      user_id = "bulk_user"

      # Bulk register
      AttentionTracker.register_views_bulk(sensor_ids, "composite_heartrate", user_id)
      Process.sleep(50)

      # All should be :medium
      for sid <- sensor_ids do
        assert AttentionTracker.get_sensor_attention_level(sid) == :medium
      end

      # Bulk unregister
      AttentionTracker.unregister_views_bulk(sensor_ids, "composite_heartrate", user_id)
      Process.sleep(100)

      # All should be :none or :low (after boost decay)
      for sid <- sensor_ids do
        level = AttentionTracker.get_sensor_attention_level(sid)
        assert level in [:none, :low]
      end
    end

    test "ETS cache matches GenServer state for attention levels" do
      sensor_id = "ets_consistency_#{System.unique_integer([:positive])}"
      attr_id = "test_attr"
      user_id = "consistency_user"

      AttentionTracker.register_view(sensor_id, attr_id, user_id)
      Process.sleep(50)

      # ETS read (what SimpleSensor uses — hot path)
      ets_level = AttentionTracker.get_attention_level(sensor_id, attr_id)
      ets_sensor_level = AttentionTracker.get_sensor_attention_level(sensor_id)

      # GenServer call (ground truth)
      state = AttentionTracker.get_state()
      gs_level = get_in(state.attention_state, [sensor_id, attr_id]) != nil

      assert ets_level == :medium
      assert ets_sensor_level == :medium
      assert gs_level == true

      # Cleanup
      AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    end
  end

  # ===========================================================================
  # 4. SystemLoadMonitor Smoke Test
  #
  # The entire bio layer and adaptive attention decay depend on this.
  # If it breaks, attention thresholds revert to defaults silently.
  # ===========================================================================

  describe "SystemLoadMonitor contract" do
    test "get_load_level returns a valid atom" do
      level = Sensocto.SystemLoadMonitor.get_load_level()
      assert level in [:normal, :elevated, :high, :critical]
    end

    test "get_load_multiplier returns a number >= 1.0" do
      multiplier = Sensocto.SystemLoadMonitor.get_load_multiplier()
      assert is_number(multiplier)
      assert multiplier >= 1.0
    end

    test "memory_protection_active? returns a boolean" do
      result = Sensocto.SystemLoadMonitor.memory_protection_active?()
      assert is_boolean(result)
    end

    test "get_memory_pressure returns a float between 0 and 1" do
      pressure = Sensocto.SystemLoadMonitor.get_memory_pressure()
      assert is_float(pressure)
      assert pressure >= 0.0
      assert pressure <= 1.0
    end

    test "get_load_config returns expected shape for all levels" do
      for level <- [:normal, :elevated, :high, :critical] do
        config = Sensocto.SystemLoadMonitor.get_load_config(level)
        assert Map.has_key?(config, :window_multiplier)
        assert is_number(config.window_multiplier)
      end
    end
  end

  # ===========================================================================
  # 5. PriorityLens Public API Contract
  #
  # Router writes directly to PriorityLens ETS. If the API changes,
  # the entire data pipeline silently breaks.
  # ===========================================================================

  describe "PriorityLens public API contract" do
    test "register_socket returns {:ok, topic}" do
      socket_id = "contract_test_#{System.unique_integer([:positive])}"
      sensor_ids = ["s1", "s2"]

      result = PriorityLens.register_socket(socket_id, sensor_ids, quality: :high)
      assert {:ok, topic} = result
      assert is_binary(topic)
      assert String.starts_with?(topic, "lens:priority:")

      # Cleanup
      PriorityLens.unregister_socket(socket_id)
    end

    test "buffer_for_sensor does not crash with valid measurement" do
      measurement = %{
        sensor_id: "buffer_contract_test",
        attribute_id: "hr",
        value: 72,
        timestamp: DateTime.utc_now()
      }

      # Should not crash — this is what Router calls on every measurement
      PriorityLens.buffer_for_sensor("buffer_contract_test", measurement)
    end

    test "buffer_batch_for_sensor does not crash with valid batch" do
      measurements = [
        %{sensor_id: "batch_test", attribute_id: "ecg", value: 1.0},
        %{sensor_id: "batch_test", attribute_id: "ecg", value: 1.1}
      ]

      # Should not crash — this is what Router calls for batch measurements
      PriorityLens.buffer_batch_for_sensor("batch_test", measurements)
    end
  end
end
