defmodule Sensocto.ButtonSignalReliabilityTest do
  @moduledoc """
  Tests for button signal reliability — ensuring button press/release events
  are always delivered through the attention-sharded PubSub pipeline and
  accumulated (not overwritten) in PriorityLens.

  These tests guard against regressions in the priority signal path.
  """
  use Sensocto.DataCase, async: false

  alias Sensocto.SimpleSensor
  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.Lenses.PriorityLens

  @moduletag :integration

  defp create_button_sensor(suffix) do
    sensor_id = "btn_test_#{suffix}_#{System.unique_integer([:positive])}"

    configuration = %{
      sensor_id: sensor_id,
      sensor_name: "Button Test #{suffix}",
      sensor_type: "html5",
      connector_id: "test_connector",
      connector_name: "Test Connector",
      batch_size: 1,
      sampling_rate: 1,
      attributes: %{
        "button" => %{
          attribute_type: "button",
          sampling_rate: 1
        }
      }
    }

    {:ok, _pid} = SensorsDynamicSupervisor.add_sensor(sensor_id, configuration)
    Process.sleep(100)

    on_exit(fn ->
      SensorsDynamicSupervisor.remove_sensor(sensor_id)
    end)

    {sensor_id, configuration}
  end

  defp button_measurement(button_id, event) do
    %{
      attribute_id: "button",
      payload: button_id,
      timestamp: System.system_time(:millisecond),
      event: event
    }
  end

  # ── SimpleSensor: Priority broadcast ────────────────────────────────

  describe "button events broadcast on attention:high even with no viewers" do
    test "button measurement reaches data:attention:high when attention_level is :none" do
      {sensor_id, _} = create_button_sensor("broadcast_none")

      # Verify the sensor has attention_level :none (no viewers)
      state = :sys.get_state(SimpleSensor.via_tuple(sensor_id))
      assert state.attention_level == :none

      # Subscribe to the high-attention topic
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      # Send a button press
      SimpleSensor.put_attribute(sensor_id, button_measurement(1, "press"))

      # Should receive on data:attention:high despite :none attention level
      assert_receive {:measurement, %{attribute_id: "button", sensor_id: ^sensor_id}}, 500
    end

    test "button measurement reaches data:attention:high when attention_level is :low" do
      {sensor_id, _} = create_button_sensor("broadcast_low")

      # Set attention to :low
      pid = GenServer.whereis(SimpleSensor.via_tuple(sensor_id))
      send(pid, {:attention_changed, %{sensor_id: sensor_id, level: :low}})
      Process.sleep(50)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:low")

      SimpleSensor.put_attribute(sensor_id, button_measurement(1, "press"))

      # When attention is :low, button still broadcasts on the sensor's actual level
      assert_receive {:measurement, %{attribute_id: "button", sensor_id: ^sensor_id}}, 500
    end

    test "non-button measurement does NOT broadcast when attention_level is :none" do
      {sensor_id, _} = create_button_sensor("no_broadcast")

      state = :sys.get_state(SimpleSensor.via_tuple(sensor_id))
      assert state.attention_level == :none

      # Subscribe to all attention topics
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:low")

      # Send a non-button measurement
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "temperature",
        payload: %{value: 36.5},
        timestamp: System.system_time(:millisecond)
      })

      # Should NOT receive on any attention topic
      refute_receive {:measurement, _}, 200
    end

    test "button events always reach per-sensor topic regardless of attention" do
      {sensor_id, _} = create_button_sensor("per_sensor")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      SimpleSensor.put_attribute(sensor_id, button_measurement(3, "press"))

      assert_receive {:measurement, %{attribute_id: "button", payload: 3}}, 500
    end
  end

  # ── SimpleSensor: Batch priority broadcast ──────────────────────────

  describe "button events in batch broadcasts" do
    test "batch containing button attribute broadcasts on attention:high when :none" do
      {sensor_id, _} = create_button_sensor("batch_priority")

      state = :sys.get_state(SimpleSensor.via_tuple(sensor_id))
      assert state.attention_level == :none

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")

      # Send batch with a button event
      SimpleSensor.put_batch_attributes(sensor_id, [
        button_measurement(1, "press")
      ])

      assert_receive {:measurements_batch, {^sensor_id, _}}, 500
    end

    test "batch without button attribute does NOT broadcast when :none" do
      {sensor_id, _} = create_button_sensor("batch_no_priority")

      state = :sys.get_state(SimpleSensor.via_tuple(sensor_id))
      assert state.attention_level == :none

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:low")

      SimpleSensor.put_batch_attributes(sensor_id, [
        %{
          attribute_id: "temperature",
          payload: %{value: 36.5},
          timestamp: System.system_time(:millisecond)
        }
      ])

      refute_receive {:measurements_batch, _}, 200
    end
  end

  # ── PriorityLens: Button event accumulation ─────────────────────────

  describe "PriorityLens accumulates button events instead of overwriting" do
    setup do
      socket_id = "test_socket_#{System.unique_integer([:positive])}"
      {sensor_id, _} = create_button_sensor("lens_accum")

      PriorityLens.register_socket(socket_id, [sensor_id])
      Process.sleep(50)

      on_exit(fn ->
        PriorityLens.unregister_socket(socket_id)
      end)

      %{socket_id: socket_id, sensor_id: sensor_id}
    end

    test "rapid press+release both survive in the buffer",
         %{socket_id: socket_id, sensor_id: sensor_id} do
      press = %{
        sensor_id: sensor_id,
        attribute_id: "button",
        payload: 1,
        timestamp: System.system_time(:millisecond),
        event: "press"
      }

      release = %{
        sensor_id: sensor_id,
        attribute_id: "button",
        payload: 1,
        timestamp: System.system_time(:millisecond) + 5,
        event: "release"
      }

      # Buffer both events rapidly (simulating < 32ms gap)
      socket_state = PriorityLens.get_socket_state(socket_id)
      PriorityLens.buffer_measurement(socket_id, socket_state, sensor_id, "button", press)
      PriorityLens.buffer_measurement(socket_id, socket_state, sensor_id, "button", release)

      # Read the buffer directly to verify accumulation
      key = {socket_id, sensor_id, "button"}

      case :ets.lookup(:priority_lens_buffers, key) do
        [{^key, entries}] when is_list(entries) ->
          assert length(entries) >= 2
          events = Enum.map(entries, & &1.event)
          assert "press" in events
          assert "release" in events

        other ->
          flunk("Expected accumulated list, got: #{inspect(other)}")
      end
    end

    test "non-button attributes still use keep-latest-only",
         %{socket_id: socket_id, sensor_id: sensor_id} do
      first = %{
        sensor_id: sensor_id,
        attribute_id: "temperature",
        payload: %{value: 36.5},
        timestamp: System.system_time(:millisecond)
      }

      second = %{
        sensor_id: sensor_id,
        attribute_id: "temperature",
        payload: %{value: 37.0},
        timestamp: System.system_time(:millisecond) + 5
      }

      socket_state = PriorityLens.get_socket_state(socket_id)
      PriorityLens.buffer_measurement(socket_id, socket_state, sensor_id, "temperature", first)
      PriorityLens.buffer_measurement(socket_id, socket_state, sensor_id, "temperature", second)

      key = {socket_id, sensor_id, "temperature"}

      case :ets.lookup(:priority_lens_buffers, key) do
        [{^key, entry}] when is_map(entry) ->
          # Only the latest measurement survives
          assert entry.payload == %{value: 37.0}

        other ->
          flunk("Expected single map (keep-latest), got: #{inspect(other)}")
      end
    end
  end
end
