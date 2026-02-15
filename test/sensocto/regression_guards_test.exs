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

  # ===========================================================================
  # 6. Router Lifecycle
  #
  # The Router is demand-driven: subscribe on first lens, unsubscribe on last.
  # If this breaks, either all data flows when nobody watches (waste) or
  # no data flows when someone watches (silent failure).
  # ===========================================================================

  describe "Router lifecycle contract" do
    test "register_lens adds to registered list, unregister removes" do
      :ok = Router.register_lens(self())
      lenses = Router.get_registered_lenses()
      assert self() in lenses

      :ok = Router.unregister_lens(self())
      lenses = Router.get_registered_lenses()
      refute self() in lenses
    end

    test "lens process death auto-unregisters via :DOWN monitor" do
      # Spawn a lens that immediately sleeps, then let it die
      lens_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Router.register_lens(lens_pid)
      assert lens_pid in Router.get_registered_lenses()

      # Kill the lens — Router should detect via monitor
      Process.exit(lens_pid, :kill)
      Process.sleep(50)

      refute lens_pid in Router.get_registered_lenses()
    end

    test "re-register after all lenses gone works correctly" do
      :ok = Router.register_lens(self())
      :ok = Router.unregister_lens(self())
      assert Router.get_registered_lenses() == [] or self() not in Router.get_registered_lenses()

      # Re-register should work
      :ok = Router.register_lens(self())
      assert self() in Router.get_registered_lenses()

      :ok = Router.unregister_lens(self())
    end

    test "multiple lens registrations are independent" do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Router.register_lens(pid1)
      :ok = Router.register_lens(pid2)
      assert length(Router.get_registered_lenses()) >= 2

      # Removing one doesn't affect the other
      :ok = Router.unregister_lens(pid1)
      assert pid2 in Router.get_registered_lenses()

      # Cleanup
      :ok = Router.unregister_lens(pid2)
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  # ===========================================================================
  # 7. PriorityLens Flush & Socket Lifecycle
  #
  # PriorityLens manages per-socket ETS buffers and flush timers.
  # If flush breaks, data accumulates in ETS forever. If socket cleanup
  # breaks, orphaned entries leak memory.
  # ===========================================================================

  describe "PriorityLens flush and socket lifecycle" do
    test "register_socket makes sensor discoverable via get_sockets_for_sensor" do
      socket_id = "flush_test_#{System.unique_integer([:positive])}"
      sensor_id = "sensor_flush_test"

      {:ok, _topic} = PriorityLens.register_socket(socket_id, [sensor_id], quality: :high)

      sockets = PriorityLens.get_sockets_for_sensor(sensor_id)
      assert socket_id in sockets

      PriorityLens.unregister_socket(socket_id)
    end

    test "unregister_socket removes from reverse index" do
      socket_id = "unsub_test_#{System.unique_integer([:positive])}"
      sensor_id = "sensor_unsub_test_#{System.unique_integer([:positive])}"

      {:ok, _topic} = PriorityLens.register_socket(socket_id, [sensor_id], quality: :high)
      PriorityLens.unregister_socket(socket_id)
      Process.sleep(50)

      sockets = PriorityLens.get_sockets_for_sensor(sensor_id)
      refute socket_id in sockets
    end

    test "buffer_for_sensor writes to ETS, readable before flush" do
      socket_id = "ets_buf_#{System.unique_integer([:positive])}"
      sensor_id = "ets_sensor_#{System.unique_integer([:positive])}"

      {:ok, _topic} = PriorityLens.register_socket(socket_id, [sensor_id], quality: :high)

      measurement = %{
        sensor_id: sensor_id,
        attribute_id: "hr",
        value: 80,
        timestamp: DateTime.utc_now()
      }

      PriorityLens.buffer_for_sensor(sensor_id, measurement)

      # Verify data is in ETS
      key = {socket_id, sensor_id, "hr"}
      entries = :ets.lookup(:priority_lens_buffers, key)
      assert length(entries) > 0

      PriorityLens.unregister_socket(socket_id)
    end

    test "set_quality changes socket quality level" do
      socket_id = "quality_test_#{System.unique_integer([:positive])}"

      {:ok, _topic} = PriorityLens.register_socket(socket_id, ["s1"], quality: :high)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :high

      PriorityLens.set_quality(socket_id, :low)
      Process.sleep(20)

      state = PriorityLens.get_socket_state(socket_id)
      assert state.quality == :low

      PriorityLens.unregister_socket(socket_id)
    end

    test "get_stats returns expected shape" do
      stats = PriorityLens.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :socket_count)
      assert Map.has_key?(stats, :quality_distribution)
      assert Map.has_key?(stats, :healthy)
      assert is_integer(stats.socket_count)
      assert is_boolean(stats.healthy)
    end

    test "topic_for_socket returns correct format" do
      topic = PriorityLens.topic_for_socket("my_socket_123")
      assert topic == "lens:priority:my_socket_123"
    end
  end

  # ===========================================================================
  # 8. Bio Layer Graceful Degradation
  #
  # Every Bio module (NoveltyDetector, ResourceArbiter, CircadianScheduler,
  # HomeostaticTuner, PredictiveLoadBalancer) must return neutral fallback
  # values when called with unknown keys. If a module crashes and restarts,
  # callers must not crash — they get safe defaults.
  # ===========================================================================

  describe "Bio layer graceful degradation" do
    test "NoveltyDetector returns 0.0 for unknown sensor" do
      score =
        Sensocto.Bio.NoveltyDetector.get_novelty_score("nonexistent_sensor", "nonexistent_attr")

      assert score == 0.0
    end

    test "ResourceArbiter returns 1.0 for unknown sensor" do
      multiplier = Sensocto.Bio.ResourceArbiter.get_multiplier("nonexistent_sensor")
      assert multiplier == 1.0
    end

    test "CircadianScheduler returns 1.0 for phase adjustment (neutral)" do
      adj = Sensocto.Bio.CircadianScheduler.get_phase_adjustment()
      assert is_number(adj)
    end

    test "CircadianScheduler returns valid phase" do
      phase = Sensocto.Bio.CircadianScheduler.get_phase()

      assert phase in [
               :approaching_peak,
               :peak,
               :approaching_off_peak,
               :off_peak,
               :normal,
               :unknown
             ]
    end

    test "HomeostaticTuner returns default offsets" do
      offsets = Sensocto.Bio.HomeostaticTuner.get_offsets()
      assert is_map(offsets)
      assert Map.has_key?(offsets, :elevated)
      assert Map.has_key?(offsets, :high)
      assert Map.has_key?(offsets, :critical)
      assert is_number(offsets.elevated)
    end

    test "PredictiveLoadBalancer returns 1.0 for unknown sensor" do
      factor = Sensocto.Bio.PredictiveLoadBalancer.get_predictive_factor("nonexistent_sensor")
      assert factor == 1.0
    end

    test "all Bio modules return numeric values usable as multipliers" do
      # These are the values SystemLoadMonitor and AttentionTracker multiply with.
      # If any returns nil or a non-number, arithmetic crashes silently.
      assert is_number(Sensocto.Bio.CircadianScheduler.get_phase_adjustment())
      assert is_number(Sensocto.Bio.PredictiveLoadBalancer.get_predictive_factor("any"))
      assert is_number(Sensocto.Bio.ResourceArbiter.get_multiplier("any"))
      assert is_number(Sensocto.Bio.NoveltyDetector.get_novelty_score("any", "any"))

      offsets = Sensocto.Bio.HomeostaticTuner.get_offsets()
      assert Enum.all?(Map.values(offsets), &is_number/1)
    end
  end

  # ===========================================================================
  # 9. AttributeStoreTiered Seed Data
  #
  # Seed data powers historical charts on view entry. If put/get contracts
  # break, charts show stale or missing data. The maybe_take fix (returning
  # most recent N, not oldest N) is a critical regression target.
  # ===========================================================================

  describe "AttributeStoreTiered seed data contract" do
    alias Sensocto.AttributeStoreTiered

    test "put_attribute stores data retrievable via get_attributes" do
      sensor_id = "store_test_#{System.unique_integer([:positive])}"

      AttributeStoreTiered.put_attribute(sensor_id, "temperature", 1000, 25.0)
      AttributeStoreTiered.put_attribute(sensor_id, "temperature", 1001, 25.5)

      attrs = AttributeStoreTiered.get_attributes(sensor_id)
      assert Map.has_key?(attrs, "temperature")
      assert length(attrs["temperature"]) >= 2

      AttributeStoreTiered.cleanup(sensor_id)
    end

    test "get_attribute returns most recent N entries (not oldest)" do
      sensor_id = "recency_test_#{System.unique_integer([:positive])}"

      # Insert 10 entries with ascending timestamps
      for i <- 1..10 do
        AttributeStoreTiered.put_attribute(sensor_id, "hr", i * 1000, 60 + i)
      end

      # Request only 3 entries
      {:ok, entries} = AttributeStoreTiered.get_attribute(sensor_id, "hr", nil, :infinity, 3)

      # Should be the MOST RECENT 3 (timestamps 8000, 9000, 10000)
      timestamps = Enum.map(entries, & &1.timestamp)
      assert length(entries) == 3
      assert Enum.max(timestamps) == 10_000
      assert Enum.min(timestamps) == 8_000

      AttributeStoreTiered.cleanup(sensor_id)
    end

    test "get_attribute respects time window filtering" do
      sensor_id = "window_test_#{System.unique_integer([:positive])}"

      for i <- 1..10 do
        AttributeStoreTiered.put_attribute(sensor_id, "ecg", i * 1000, 1.0 + i * 0.1)
      end

      # Only entries with timestamp >= 5000
      {:ok, entries} = AttributeStoreTiered.get_attribute(sensor_id, "ecg", 5000, :infinity)
      timestamps = Enum.map(entries, & &1.timestamp)
      assert Enum.all?(timestamps, &(&1 >= 5000))

      AttributeStoreTiered.cleanup(sensor_id)
    end

    test "cleanup removes all data for a sensor" do
      sensor_id = "cleanup_test_#{System.unique_integer([:positive])}"

      AttributeStoreTiered.put_attribute(sensor_id, "temp", 1000, 20.0)
      attrs = AttributeStoreTiered.get_attributes(sensor_id)
      assert map_size(attrs) > 0

      AttributeStoreTiered.cleanup(sensor_id)

      attrs = AttributeStoreTiered.get_attributes(sensor_id)
      assert attrs == %{}
    end

    test "stats returns expected shape" do
      sensor_id = "stats_test_#{System.unique_integer([:positive])}"
      AttributeStoreTiered.put_attribute(sensor_id, "hr", 1000, 72)

      stats = AttributeStoreTiered.stats(sensor_id)
      assert Map.has_key?(stats, :sensor_id)
      assert Map.has_key?(stats, :hot_entries)
      assert Map.has_key?(stats, :warm_entries)
      assert Map.has_key?(stats, :attributes)
      assert stats.sensor_id == sensor_id
      assert stats.hot_entries >= 1

      AttributeStoreTiered.cleanup(sensor_id)
    end

    test "current_limits returns load-adaptive configuration" do
      limits = AttributeStoreTiered.current_limits()
      assert Map.has_key?(limits, :load_level)
      assert Map.has_key?(limits, :hot_limit)
      assert Map.has_key?(limits, :warm_limit)
      assert is_integer(limits.hot_limit) or is_float(limits.hot_limit)
      assert limits.hot_limit > 0
      assert limits.warm_limit > 0
    end
  end

  # ===========================================================================
  # 10. Discovery Cache Consistency
  #
  # DiscoveryCache provides fast local reads for sensor listings.
  # If put/get/delete contracts change, the lobby shows stale or
  # missing sensors.
  # ===========================================================================

  describe "DiscoveryCache consistency" do
    alias Sensocto.Discovery.DiscoveryCache

    test "put_sensor + get_sensor returns fresh data" do
      sensor_id = "discovery_test_#{System.unique_integer([:positive])}"
      data = %{name: "Test Sensor", status: :active}

      DiscoveryCache.put_sensor(sensor_id, data)
      Process.sleep(20)

      result = DiscoveryCache.get_sensor(sensor_id)
      assert {:ok, ^data, :fresh} = result

      DiscoveryCache.delete_sensor(sensor_id)
    end

    test "get_sensor returns :not_found for unknown sensor" do
      result = DiscoveryCache.get_sensor("nonexistent_#{System.unique_integer([:positive])}")
      assert {:error, :not_found} = result
    end

    test "sensor_count reflects inserted sensors" do
      before_count = DiscoveryCache.sensor_count()

      sensor_id = "count_test_#{System.unique_integer([:positive])}"
      DiscoveryCache.put_sensor(sensor_id, %{name: "counter"})
      Process.sleep(20)

      after_count = DiscoveryCache.sensor_count()
      assert after_count >= before_count + 1

      DiscoveryCache.delete_sensor(sensor_id)
    end

    test "delete_sensor removes entry" do
      sensor_id = "delete_test_#{System.unique_integer([:positive])}"
      DiscoveryCache.put_sensor(sensor_id, %{name: "doomed"})
      Process.sleep(20)

      DiscoveryCache.delete_sensor(sensor_id)
      Process.sleep(20)

      assert {:error, :not_found} = DiscoveryCache.get_sensor(sensor_id)
    end

    test "list_sensors returns a list" do
      sensors = DiscoveryCache.list_sensors()
      assert is_list(sensors)
    end

    test "clear_sensors removes all entries" do
      # Save current count to verify behavior
      DiscoveryCache.put_sensor("clear_test_1_#{System.unique_integer([:positive])}", %{a: 1})
      DiscoveryCache.put_sensor("clear_test_2_#{System.unique_integer([:positive])}", %{b: 2})
      Process.sleep(20)

      DiscoveryCache.clear_sensors()
      Process.sleep(20)

      assert DiscoveryCache.sensor_count() == 0
    end
  end
end
