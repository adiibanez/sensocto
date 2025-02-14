defmodule Sensocto.AttributeGenServerTest do
  use ExUnit.Case
  require Logger

  alias Sensocto.AttributeGenServer

  setup do
    # Start the Registry for the tests
    {:ok, _} = Registry.start_link(keys: :unique, name: Sensocto.Registry)
    {:ok, _} = Registry.start_link(keys: :unique, name: SensorSimulatorRegistry)

    test_config = %{
      attribute_id: "test_sensor:heartrate",
      connector_id: "test_connector",
      sensor_type: "heartrate",
      sampling_rate: 10,
      duration: 30,
      batch_size: 5,
      batch_window: 1000,
      connector_pid: self()
    }

    {:ok, config: test_config}
  end

  describe "AttributeGenServer" do
    test "starts correctly with config", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)
      assert Process.alive?(pid)

      state = AttributeGenServer.get_state(config.attribute_id)
      assert state.attribute_id == config.attribute_id
      assert state.connector_id == config.connector_id
      assert state.paused == false
      assert state.messages_queue == []
      assert state.batch_push_messages == []
    end

    test "processes messages queue correctly", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)

      # Send test messages
      test_messages = [
        %{payload: "test1", delay: 0.1},
        %{payload: "test2", delay: 0.2},
        %{payload: "test3", delay: 0.3}
      ]

      :sys.replace_state(pid, fn state ->
        %{state | messages_queue: test_messages}
      end)

      # Trigger queue processing
      GenServer.cast(pid, :process_queue)

      # Wait for processing
      Process.sleep(500)

      state = AttributeGenServer.get_state(config.attribute_id)
      assert length(state.messages_queue) < length(test_messages)
    end

    test "handles batch processing correctly", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)

      # Generate batch_size + 1 messages
      messages = Enum.map(1..6, fn i ->
        %{payload: "test#{i}", delay: 0.1}
      end)

      # Send messages one by one
      Enum.each(messages, fn msg ->
        GenServer.cast(pid, {:push_message, msg})
      end)

      # Wait for batch processing
      Process.sleep(200)

      # Verify batch was sent
      assert_received {:push_batch, pushed_messages}
      assert length(pushed_messages) >= config.batch_size
    end

    test "handles batch window timeout", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)

      # Send fewer messages than batch_size
      messages = Enum.map(1..3, fn i ->
        %{payload: "test#{i}", delay: 0.1}
      end)

      Enum.each(messages, fn msg ->
        GenServer.cast(pid, {:push_message, msg})
      end)

      # Wait for batch window timeout
      Process.sleep(config.batch_window + 100)

      # Verify messages were sent
      assert_received {:push_batch, pushed_messages}
      assert length(pushed_messages) == length(messages)
    end

    test "handles configuration updates", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)

      # Update configuration
      send(pid, {:set_config, :sampling_rate, 20})
      Process.sleep(100)

      state = AttributeGenServer.get_state(config.attribute_id)
      assert state.sampling_rate == 20
    end

    test "pauses message processing when paused", %{config: config} do
      {:ok, pid} = AttributeGenServer.start_link(config)

      # Pause the server
      send(pid, {:set_config, :paused, true})
      Process.sleep(100)

      # Send test message
      message = %{payload: "test", delay: 0.1}
      GenServer.cast(pid, {:push_message, message})

      Process.sleep(200)

      # Verify no messages were sent
      refute_received {:push_batch, _}
    end
  end
end
