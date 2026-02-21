defmodule Sensocto.SimpleSensorThrottleTest do
  @moduledoc """
  Tests for SimpleSensor source-side batch throttling under load.

  Verifies that:
  - Under :normal load, broadcasts are immediate (zero latency)
  - Under :elevated/:high/:critical load, measurements are buffered
  - Buffer is flushed as a batch on timer expiry
  - Buffer is flushed immediately when load drops to :normal
  - Both put_attribute and put_batch_attributes paths are throttled
  - Attention-gated sensors (attention_level: :none) don't broadcast regardless of load
  - Priority attributes (button) are always broadcast even when attention is :none
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.SimpleSensor
  alias Sensocto.SensorsDynamicSupervisor

  @moduletag :integration

  setup do
    sensor_id = "throttle_test_#{System.unique_integer([:positive])}"

    configuration = %{
      sensor_id: sensor_id,
      sensor_name: "Throttle Test Sensor",
      sensor_type: "test_type",
      connector_id: "test_connector",
      connector_name: "Test Connector",
      batch_size: 10,
      sampling_rate: 100,
      attributes: %{
        "temperature" => %{attribute_type: "numeric", sampling_rate: 100},
        "button" => %{attribute_type: "button", sampling_rate: 10}
      }
    }

    {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
    Process.sleep(150)

    on_exit(fn ->
      # Restore load level to :normal
      set_load_level(:normal)
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end)

    {:ok, sensor_id: sensor_id}
  end

  # ===========================================================================
  # Normal load: immediate broadcasts
  # ===========================================================================

  describe "normal load (immediate broadcast)" do
    test "put_attribute broadcasts immediately on per-sensor topic", %{sensor_id: sensor_id} do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.0,
        timestamp: System.system_time(:millisecond)
      })

      assert_receive {:measurement, measurement}, 500
      assert measurement.sensor_id == sensor_id
      assert measurement.payload == 25.0
    end

    test "put_batch_attributes broadcasts immediately on per-sensor topic", %{
      sensor_id: sensor_id
    } do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      now = System.system_time(:millisecond)

      SimpleSensor.put_batch_attributes(sensor_id, [
        %{attribute_id: "temperature", payload: 22.0, timestamp: now},
        %{attribute_id: "temperature", payload: 22.5, timestamp: now + 1}
      ])

      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) == 2
    end

    test "put_attribute broadcasts on attention topic when sensor has viewers", %{
      sensor_id: sensor_id
    } do
      # Set attention level to :high (sensor has active viewers)
      set_attention(sensor_id, :high)
      Process.sleep(50)

      # Subscribe to attention topic
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.0,
        timestamp: System.system_time(:millisecond)
      })

      assert_receive {:measurement, measurement}, 500
      assert measurement.sensor_id == sensor_id
    end
  end

  # ===========================================================================
  # Elevated+ load: buffered broadcasts
  # ===========================================================================

  describe "elevated load (buffered broadcast)" do
    test "put_attribute buffers under elevated load and flushes as batch", %{
      sensor_id: sensor_id
    } do
      # Set attention so broadcasts happen on attention topic
      set_attention(sensor_id, :medium)
      Process.sleep(50)

      # Subscribe to attention topic to receive the flushed batch
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")

      # Simulate elevated load
      set_load_level(:elevated)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(50)

      # Send a measurement — should be buffered, not immediately broadcast on attention topic
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 30.0,
        timestamp: System.system_time(:millisecond)
      })

      # Per-sensor topic should still receive it immediately
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      # But the attention topic should get a batch after the flush interval (32ms for elevated+medium)
      # Wait for the batch flush (32ms interval + some margin)
      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) >= 1

      first = List.first(measurements)
      assert first.payload == 30.0
    end

    test "multiple put_attribute calls are batched together under load", %{sensor_id: sensor_id} do
      set_attention(sensor_id, :high)
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      set_load_level(:elevated)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(50)

      now = System.system_time(:millisecond)

      # Send 3 rapid measurements — should all be batched
      for i <- 1..3 do
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          payload: 20.0 + i,
          timestamp: now + i
        })
      end

      # Wait for flush (16ms for elevated+high + margin)
      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) >= 2
    end

    test "put_batch_attributes buffers under elevated load", %{sensor_id: sensor_id} do
      set_attention(sensor_id, :medium)
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")

      set_load_level(:high)
      notify_load_change(sensor_id, :high)
      Process.sleep(50)

      now = System.system_time(:millisecond)

      SimpleSensor.put_batch_attributes(sensor_id, [
        %{attribute_id: "temperature", payload: 22.0, timestamp: now},
        %{attribute_id: "temperature", payload: 22.5, timestamp: now + 1}
      ])

      # Should receive a flushed batch (64ms for high+medium)
      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) >= 2
    end
  end

  # ===========================================================================
  # Load transitions
  # ===========================================================================

  describe "load level transitions" do
    test "buffer is flushed immediately when load drops to :normal", %{sensor_id: sensor_id} do
      set_attention(sensor_id, :high)
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      # Start at elevated load
      set_load_level(:elevated)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(50)

      # Send measurement (gets buffered)
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 99.0,
        timestamp: System.system_time(:millisecond)
      })

      # Don't wait for timer — immediately drop load to normal
      Process.sleep(10)
      set_load_level(:normal)
      notify_load_change(sensor_id, :normal)

      # Buffer should be flushed immediately as a batch
      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert Enum.any?(measurements, &(&1.payload == 99.0))
    end

    test "sensor resumes immediate broadcasts after load returns to normal", %{
      sensor_id: sensor_id
    } do
      set_attention(sensor_id, :high)
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      # Go through elevated and back to normal
      set_load_level(:elevated)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(50)

      set_load_level(:normal)
      notify_load_change(sensor_id, :normal)
      Process.sleep(50)

      # Flush any pending batch messages
      flush_messages()

      # Now send a measurement — should be immediate (not batched)
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 42.0,
        timestamp: System.system_time(:millisecond)
      })

      # Should receive as individual :measurement, not :measurements_batch
      assert_receive {:measurement, measurement}, 500
      assert measurement.payload == 42.0
    end
  end

  # ===========================================================================
  # Attention gating
  # ===========================================================================

  describe "attention gating with throttling" do
    test "no attention-topic broadcast when attention is :none (regardless of load)", %{
      sensor_id: sensor_id
    } do
      # Default attention is :none — sensor has no viewers
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:low")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: 25.0,
        timestamp: System.system_time(:millisecond)
      })

      # Should NOT receive on any attention topic (gated by :none)
      refute_receive {:measurement, _}, 200
      refute_receive {:measurements_batch, _}, 100
    end

    test "priority attributes (button) broadcast even when attention is :none", %{
      sensor_id: sensor_id
    } do
      # Button is a priority attribute — should always broadcast on :high
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "1",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      assert_receive {:measurement, measurement}, 500
      assert measurement.attribute_id == "button"
    end

    test "priority attributes (button) broadcast even under elevated load with :none attention",
         %{sensor_id: sensor_id} do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      set_load_level(:elevated)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(50)

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "1",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      # Button with :none attention uses interval 0 (from @broadcast_intervals {:elevated, :none} => 0)
      # But attention_topic_for checks priority and returns "data:attention:high"
      # The interval lookup uses {load_level, attention_level} where attention is :none
      # {:elevated, :none} => 0, so it should be immediate
      assert_receive {:measurement, measurement}, 500
      assert measurement.attribute_id == "button"
    end
  end

  # ===========================================================================
  # System load subscription
  # ===========================================================================

  describe "system load subscription" do
    test "sensor subscribes to system:load topic and processes level changes", %{
      sensor_id: sensor_id
    } do
      # Notify of load change — sensor should handle without crashing
      notify_load_change(sensor_id, :critical)
      Process.sleep(50)

      # Sensor should still be alive
      assert SimpleSensor.alive?(sensor_id)

      # Notify back to normal
      notify_load_change(sensor_id, :normal)
      Process.sleep(50)

      assert SimpleSensor.alive?(sensor_id)
    end

    test "duplicate load level notification is ignored (no crash)", %{sensor_id: sensor_id} do
      notify_load_change(sensor_id, :elevated)
      Process.sleep(20)
      notify_load_change(sensor_id, :elevated)
      Process.sleep(20)

      assert SimpleSensor.alive?(sensor_id)
    end

    test "memory protection changed message is handled without crash", %{sensor_id: sensor_id} do
      pid = GenServer.whereis(SimpleSensor.via_tuple(sensor_id))
      send(pid, {:memory_protection_changed, %{active: true}})
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  # ===========================================================================
  # Flush timer behavior
  # ===========================================================================

  describe "flush timer" do
    test "flush_broadcast_buffer message is handled when no buffer exists", %{
      sensor_id: sensor_id
    } do
      pid = GenServer.whereis(SimpleSensor.via_tuple(sensor_id))
      send(pid, :flush_broadcast_buffer)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "buffer contents are delivered in chronological order", %{sensor_id: sensor_id} do
      set_attention(sensor_id, :high)
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      set_load_level(:critical)
      notify_load_change(sensor_id, :critical)
      Process.sleep(50)

      now = System.system_time(:millisecond)

      # Send measurements in order
      for i <- 1..5 do
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "temperature",
          payload: Float.round(20.0 + i * 0.1, 1),
          timestamp: now + i * 10
        })

        Process.sleep(5)
      end

      # Wait for flush (64ms for critical+high)
      assert_receive {:measurements_batch, {^sensor_id, measurements}}, 500
      assert length(measurements) >= 2

      # Verify chronological order (timestamps should be ascending)
      timestamps = Enum.map(measurements, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp set_load_level(level) do
    # Write directly to the ETS table used by SystemLoadMonitor
    if :ets.info(:system_load_cache) != :undefined do
      :ets.insert(:system_load_cache, {:load_level, level})
    end
  end

  defp notify_load_change(sensor_id, level) do
    # Send the load change message directly to the sensor process
    # (simulates what SystemLoadMonitor broadcasts on "system:load")
    pid = GenServer.whereis(SimpleSensor.via_tuple(sensor_id))

    if pid do
      send(pid, {:system_load_changed, %{level: level}})
    end
  end

  defp set_attention(sensor_id, :high) do
    # register_focus raises attention to :high
    Sensocto.AttentionTracker.register_focus(sensor_id, "temperature", "test_user")
  end

  defp set_attention(sensor_id, :medium) do
    # register_view raises attention to :medium
    Sensocto.AttentionTracker.register_view(sensor_id, "temperature", "test_user")
  end

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
