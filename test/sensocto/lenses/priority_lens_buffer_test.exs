defmodule Sensocto.Lenses.PriorityLensBufferTest do
  @moduledoc """
  Tests for PriorityLens buffer operations (hot data path).

  These tests verify the ETS-based buffering that Router uses to bypass
  the GenServer mailbox:
  - buffer_for_sensor/2 routes measurements to correct sockets
  - buffer_batch_for_sensor/2 handles batch measurements
  - get_sockets_for_sensor/1 returns reverse index correctly
  - buffer_measurement/5 handles high-frequency vs normal attributes
  - Flush timer delivers buffered data via PubSub
  - get_stats/0 returns correct aggregate statistics
  """

  use ExUnit.Case, async: false

  alias Sensocto.Lenses.PriorityLens

  @moduletag :priority_lens

  defp unique_socket_id, do: "buf_test_#{System.unique_integer([:positive])}"

  defp unique_sensor_id, do: "sensor_buf_#{System.unique_integer([:positive])}"

  defp make_measurement(attr_id, payload, opts \\ []) do
    %{
      sensor_id: Keyword.get(opts, :sensor_id, "sensor_1"),
      attribute_id: attr_id,
      payload: payload,
      timestamp: Keyword.get(opts, :timestamp, System.system_time(:millisecond))
    }
  end

  setup do
    socket_id = unique_socket_id()
    sensor_id = unique_sensor_id()

    on_exit(fn ->
      PriorityLens.unregister_socket(socket_id)
      Process.sleep(10)
    end)

    {:ok, socket_id: socket_id, sensor_id: sensor_id}
  end

  # ===========================================================================
  # get_sockets_for_sensor/1 (reverse index)
  # ===========================================================================

  describe "get_sockets_for_sensor/1" do
    test "returns empty list when no sockets registered for sensor" do
      assert PriorityLens.get_sockets_for_sensor("nonexistent_sensor") == []
    end

    test "returns socket ID after registration", %{socket_id: socket_id, sensor_id: sensor_id} do
      {:ok, _} = PriorityLens.register_socket(socket_id, [sensor_id])
      Process.sleep(10)

      sockets = PriorityLens.get_sockets_for_sensor(sensor_id)
      assert socket_id in sockets
    end

    test "returns multiple sockets for same sensor" do
      sensor_id = unique_sensor_id()
      socket1 = unique_socket_id()
      socket2 = unique_socket_id()

      {:ok, _} = PriorityLens.register_socket(socket1, [sensor_id])
      {:ok, _} = PriorityLens.register_socket(socket2, [sensor_id])
      Process.sleep(10)

      sockets = PriorityLens.get_sockets_for_sensor(sensor_id)
      assert socket1 in sockets
      assert socket2 in sockets

      PriorityLens.unregister_socket(socket1)
      PriorityLens.unregister_socket(socket2)
    end

    test "removes socket from reverse index on unregister", %{
      socket_id: socket_id,
      sensor_id: sensor_id
    } do
      {:ok, _} = PriorityLens.register_socket(socket_id, [sensor_id])
      Process.sleep(10)

      assert socket_id in PriorityLens.get_sockets_for_sensor(sensor_id)

      PriorityLens.unregister_socket(socket_id)
      Process.sleep(20)

      refute socket_id in PriorityLens.get_sockets_for_sensor(sensor_id)
    end

    test "updates reverse index when sensors change via set_sensors" do
      socket_id = unique_socket_id()
      sensor_a = unique_sensor_id()
      sensor_b = unique_sensor_id()

      {:ok, _} = PriorityLens.register_socket(socket_id, [sensor_a])
      Process.sleep(10)

      assert socket_id in PriorityLens.get_sockets_for_sensor(sensor_a)
      assert PriorityLens.get_sockets_for_sensor(sensor_b) == []

      # Switch sensors
      PriorityLens.set_sensors(socket_id, [sensor_b])
      Process.sleep(20)

      refute socket_id in PriorityLens.get_sockets_for_sensor(sensor_a)
      assert socket_id in PriorityLens.get_sockets_for_sensor(sensor_b)

      PriorityLens.unregister_socket(socket_id)
    end
  end

  # ===========================================================================
  # buffer_for_sensor/2
  # ===========================================================================

  describe "buffer_for_sensor/2" do
    test "buffers measurement for registered socket", %{
      socket_id: socket_id,
      sensor_id: sensor_id
    } do
      {:ok, topic} = PriorityLens.register_socket(socket_id, [sensor_id])
      Process.sleep(10)

      measurement = make_measurement("temperature", 25.0, sensor_id: sensor_id)
      assert :ok = PriorityLens.buffer_for_sensor(sensor_id, measurement)

      # Subscribe and wait for flush
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      assert_receive {:lens_batch, batch}, 500
      assert is_map(batch)
    end

    test "ignores measurement when no sockets registered" do
      measurement = make_measurement("temperature", 25.0, sensor_id: "orphan_sensor")
      assert :ok = PriorityLens.buffer_for_sensor("orphan_sensor", measurement)
    end

    test "routes measurement to multiple sockets" do
      sensor_id = unique_sensor_id()
      socket1 = unique_socket_id()
      socket2 = unique_socket_id()

      {:ok, topic1} = PriorityLens.register_socket(socket1, [sensor_id])
      {:ok, topic2} = PriorityLens.register_socket(socket2, [sensor_id])
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic1)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic2)

      measurement = make_measurement("temperature", 25.0, sensor_id: sensor_id)
      PriorityLens.buffer_for_sensor(sensor_id, measurement)

      # Both sockets should receive the flush
      assert_receive {:lens_batch, _batch1}, 500
      assert_receive {:lens_batch, _batch2}, 500

      PriorityLens.unregister_socket(socket1)
      PriorityLens.unregister_socket(socket2)
    end
  end

  # ===========================================================================
  # buffer_batch_for_sensor/2
  # ===========================================================================

  describe "buffer_batch_for_sensor/2" do
    test "buffers batch of measurements", %{socket_id: socket_id, sensor_id: sensor_id} do
      {:ok, topic} = PriorityLens.register_socket(socket_id, [sensor_id])
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      now = System.system_time(:millisecond)

      measurements = [
        make_measurement("temperature", 22.0, sensor_id: sensor_id, timestamp: now),
        make_measurement("temperature", 22.5, sensor_id: sensor_id, timestamp: now + 1),
        make_measurement("humidity", 65, sensor_id: sensor_id, timestamp: now + 2)
      ]

      PriorityLens.buffer_batch_for_sensor(sensor_id, measurements)

      assert_receive {:lens_batch, batch}, 500
      assert is_map(batch)
    end
  end

  # ===========================================================================
  # Paused mode skips buffering
  # ===========================================================================

  describe "paused mode" do
    test "paused socket does not receive any data", %{
      socket_id: socket_id,
      sensor_id: sensor_id
    } do
      {:ok, topic} = PriorityLens.register_socket(socket_id, [sensor_id], quality: :paused)
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

      measurement = make_measurement("temperature", 25.0, sensor_id: sensor_id)
      PriorityLens.buffer_for_sensor(sensor_id, measurement)

      refute_receive {:lens_batch, _}, 200
    end
  end

  # ===========================================================================
  # get_stats/0
  # ===========================================================================

  describe "get_stats/0" do
    test "returns stats with required keys" do
      stats = PriorityLens.get_stats()
      assert is_map(stats)

      assert Map.has_key?(stats, :socket_count)
      assert Map.has_key?(stats, :quality_distribution)
      assert Map.has_key?(stats, :healthy)
    end

    test "socket count reflects registrations" do
      socket_id = unique_socket_id()
      initial_stats = PriorityLens.get_stats()
      initial_count = initial_stats.socket_count

      {:ok, _} = PriorityLens.register_socket(socket_id, ["sensor_1"])
      Process.sleep(10)

      stats = PriorityLens.get_stats()
      assert stats.socket_count == initial_count + 1

      PriorityLens.unregister_socket(socket_id)
      Process.sleep(10)

      stats = PriorityLens.get_stats()
      assert stats.socket_count == initial_count
    end

    test "quality distribution tracks quality levels" do
      socket1 = unique_socket_id()
      socket2 = unique_socket_id()

      {:ok, _} = PriorityLens.register_socket(socket1, ["s1"], quality: :high)
      {:ok, _} = PriorityLens.register_socket(socket2, ["s1"], quality: :low)
      Process.sleep(10)

      stats = PriorityLens.get_stats()
      assert stats.quality_distribution.high >= 1
      assert stats.quality_distribution.low >= 1

      PriorityLens.unregister_socket(socket1)
      PriorityLens.unregister_socket(socket2)
    end

    test "healthy is true when no paused or degraded sockets" do
      # With no sockets, should be healthy
      stats = PriorityLens.get_stats()
      assert stats.healthy == true
    end
  end

  # ===========================================================================
  # Process monitoring (auto-cleanup on owner death)
  # ===========================================================================

  describe "auto-cleanup on process death" do
    test "socket is cleaned up when registering process dies" do
      sensor_id = unique_sensor_id()
      test_pid = self()

      # Spawn a process that registers and then exits
      pid =
        spawn(fn ->
          sid = unique_socket_id()
          {:ok, _topic} = PriorityLens.register_socket(sid, [sensor_id])
          send(test_pid, {:registered, sid})
          # Process exits after sending message
        end)

      socket_id =
        receive do
          {:registered, sid} -> sid
        after
          1000 -> flunk("Spawned process didn't register")
        end

      # Wait for the spawned process to exit and PriorityLens to process :DOWN
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        1000 -> :ok
      end

      # Give PriorityLens time to process the :DOWN message
      # The GenServer must receive and handle :DOWN, then clean up ETS
      Process.sleep(500)

      # Socket state should be cleaned up (GenServer handles :DOWN → cleanup_sockets_for_pid)
      assert PriorityLens.get_socket_state(socket_id) == nil
    end
  end
end
