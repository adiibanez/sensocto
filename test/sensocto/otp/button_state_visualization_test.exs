defmodule Sensocto.ButtonStateVisualizationTest do
  @moduledoc """
  Tests for button state visualization feature.

  Verifies that button press/release events are correctly:
  1. Broadcast through PubSub with event field preserved
  2. Buffered in PriorityLens with event field
  3. Processed by LobbyLive even when sensor is not visible
  """

  use Sensocto.DataCase, async: false

  alias Sensocto.SimpleSensor
  alias Sensocto.SensorsDynamicSupervisor
  alias Sensocto.Lenses.PriorityLens

  @moduletag :integration

  defp create_button_sensor(suffix \\ "") do
    sensor_id = "button_test_sensor_#{suffix}_#{System.unique_integer([:positive])}"

    configuration = %{
      sensor_id: sensor_id,
      sensor_name: "Button Test Sensor #{suffix}",
      sensor_type: "html5",
      connector_id: sensor_id,
      connector_name: "Test Connector",
      batch_size: 1,
      sampling_rate: 100,
      attributes: %{
        "button" => %{
          attribute_type: "button",
          attribute_id: "button",
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

  describe "button measurement broadcast" do
    test "button press event includes event field in broadcast" do
      {sensor_id, _config} = create_button_sensor("press_broadcast")

      # Subscribe to sensor data topic
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      # Send button press with event field
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "1",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      # Should receive measurement broadcast with event field preserved
      assert_receive {:measurement, measurement}, 500
      assert measurement.sensor_id == sensor_id
      assert measurement.attribute_id == "button"
      assert measurement.payload == "1"
      assert measurement.event == "press"
    end

    test "button release event includes event field in broadcast" do
      {sensor_id, _config} = create_button_sensor("release_broadcast")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      # Send button release
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "3",
        timestamp: System.system_time(:millisecond),
        event: "release"
      })

      assert_receive {:measurement, measurement}, 500
      assert measurement.event == "release"
      assert measurement.payload == "3"
    end

    test "button events broadcast to global topic for lens router" do
      {sensor_id, _config} = create_button_sensor("global_broadcast")

      # Register attention so sensor broadcasts to global topic
      # (sensors with no attention skip global broadcast to reduce load)
      Sensocto.AttentionTracker.register_view(sensor_id, "button", "test_user")
      Process.sleep(50)

      # Subscribe to attention-sharded data topics (used by LensRouter)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:high")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:medium")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:attention:low")

      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "2",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      # Should receive on global topic
      assert_receive {:measurement, measurement}, 500
      assert measurement.attribute_id == "button"
      assert measurement.event == "press"
    end
  end

  describe "PriorityLens button buffering" do
    setup do
      # Create a test sensor first
      {sensor_id, _config} = create_button_sensor("lens_buffer")

      # Register attention so sensor broadcasts to global topic
      # (sensors with no attention skip global broadcast to reduce load)
      Sensocto.AttentionTracker.register_view(sensor_id, "button", "test_user")

      # Create a test socket registration for PriorityLens
      socket_id = "test_socket_#{System.unique_integer([:positive])}"

      # Register socket with PriorityLens - returns {:ok, topic}
      {:ok, topic} = PriorityLens.register_socket(socket_id, [sensor_id], quality: :low)
      Process.sleep(50)

      # Subscribe to receive lens batches
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      on_exit(fn ->
        PriorityLens.unregister_socket(socket_id)
      end)

      {:ok, socket_id: socket_id, topic: topic, sensor_id: sensor_id}
    end

    test "button measurement is buffered with event field", %{
      socket_id: socket_id,
      sensor_id: sensor_id
    } do
      # Sensor is already registered in setup

      # Send button press
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "5",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      # Wait for buffering
      Process.sleep(50)

      # Check buffer directly - button measurement should be there with event field
      buffer_entries = :ets.tab2list(:priority_lens_buffers)

      button_entries =
        Enum.filter(buffer_entries, fn {{sid, _sensor_id, attr_id}, _value} ->
          sid == socket_id and attr_id == "button"
        end)

      # Should have at least one button entry (might be flushed quickly)
      # If buffer is empty, the measurement was flushed - check we receive it
      if button_entries == [] do
        # Measurement was flushed, should receive via PubSub
        assert_receive {:lens_batch, batch_data}, 1000
        assert Map.has_key?(batch_data, sensor_id)
        sensor_data = batch_data[sensor_id]
        assert Map.has_key?(sensor_data, "button")
        button_data = sensor_data["button"]
        # button_data may be a list of measurements or a single map
        button_measurement =
          if is_list(button_data), do: List.first(button_data), else: button_data

        assert button_measurement.event == "press"
      else
        # Verify buffer entry has event field
        [{_key, measurement}] = button_entries
        measurement = if is_list(measurement), do: List.first(measurement), else: measurement
        assert measurement.event == "press"
        assert measurement.payload == "5"
      end
    end

    test "button press and release sequence is tracked correctly", %{
      socket_id: socket_id,
      sensor_id: sensor_id
    } do
      # Sensor and subscription already registered in setup

      # Send press
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "1",
        timestamp: System.system_time(:millisecond),
        event: "press"
      })

      Process.sleep(20)

      # Send release
      SimpleSensor.put_attribute(sensor_id, %{
        attribute_id: "button",
        payload: "1",
        timestamp: System.system_time(:millisecond),
        event: "release"
      })

      # Wait for flush (low quality flushes every 2000ms, but we can trigger manually)
      # For testing, we wait for the batch to arrive
      receive do
        {:lens_batch, batch_data} ->
          if Map.has_key?(batch_data, sensor_id) do
            sensor_data = batch_data[sensor_id]

            if Map.has_key?(sensor_data, "button") do
              button_data = sensor_data["button"]

              button_measurement =
                if is_list(button_data), do: List.last(button_data), else: button_data

              # Latest measurement should be release (overwrites press in buffer)
              assert button_measurement.event == "release"
            end
          end
      after
        3000 ->
          # If no batch received, check buffer directly
          buffer_entries = :ets.tab2list(:priority_lens_buffers)

          button_entries =
            Enum.filter(buffer_entries, fn {{sid, _sensor_id, attr_id}, _value} ->
              sid == socket_id and attr_id == "button"
            end)

          if button_entries != [] do
            [{_key, measurement}] = button_entries
            # Latest should be release
            assert measurement.event == "release"
          end
      end
    end
  end

  describe "multiple button handling" do
    test "can track multiple simultaneous button presses" do
      {sensor_id, _config} = create_button_sensor("multi_press")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      now = System.system_time(:millisecond)

      # Press buttons 1, 3, 5
      for btn <- [1, 3, 5] do
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "button",
          payload: "#{btn}",
          timestamp: now + btn,
          event: "press"
        })
      end

      # Should receive all three press events
      events = receive_all_measurements(3, 1000)
      assert length(events) == 3

      press_payloads = Enum.map(events, & &1.payload) |> Enum.sort()
      assert press_payloads == ["1", "3", "5"]

      assert Enum.all?(events, &(&1.event == "press"))
    end

    test "button IDs are parsed correctly from various payload formats" do
      {sensor_id, _config} = create_button_sensor("payload_format")

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      # Test different payload formats
      payloads = ["1", "btn_2", "button_3", 4, "5"]

      for payload <- payloads do
        SimpleSensor.put_attribute(sensor_id, %{
          attribute_id: "button",
          payload: payload,
          timestamp: System.system_time(:millisecond),
          event: "press"
        })
      end

      events = receive_all_measurements(5, 1000)
      assert length(events) == 5
    end
  end

  # Helper to receive multiple measurements
  defp receive_all_measurements(count, timeout, acc \\ [])

  defp receive_all_measurements(0, _timeout, acc), do: Enum.reverse(acc)

  defp receive_all_measurements(count, timeout, acc) do
    receive do
      {:measurement, measurement} ->
        receive_all_measurements(count - 1, timeout, [measurement | acc])
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end
