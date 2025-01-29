defmodule Sensocto.SensorSimulatorGenServerTest do
  use ExUnit.Case
  alias Sensocto.SensorSimulatorGenServer
  alias Sensocto.BiosenseData
  require Logger
  import Mock

  # Mock PhoenixClient to avoid real connection
  defmodule PhoenixClient.Socket do
    def start_link(_opts), do: {:ok, :socket}
    def connected?(_socket), do: true
    def stop(_socket), do: :ok
  end

  defmodule PhoenixClient.Channel do
    def join(_socket, _topic, _meta), do: {:ok, :ok, :channel}
    def push_async(_channel, _event, _payload), do: :ok
  end

  # Mock BiosenseData to return dummy data
  defmodule MockBiosenseData do
    def fetch_sensor_data(_config),
      do:
        {:ok,
         [%{payload: "test payload 1", delay: 0.1}, %{payload: "test payload 2", delay: 0.3}]}

    def fetch_sensor_data_no_data(_config),
      do: {:ok, []}
  end

  setup do
    sensor_id = "test_sensor"

    config = %{
      sensor_id: sensor_id,
      device_name: "test_device",
      connector_id: "test_connector",
      connector_name: "test_connector",
      sampling_rate: 10,
      sensor_name: "test_sensor",
      sensor_type: "61d20a90-71a1-11ea-ab12-0800200c9a66",
      bearer_token: "fake"
    }

    {:ok, server} = SensorSimulatorGenServer.start_link(config)
    on_exit(fn -> GenServer.stop(server) end)
    {:ok, server: server, config: config, sensor_id: sensor_id}
  end

  test "init/1 initializes the state correctly", %{server: server} do
    assert GenServer.call(server, :get_data) != nil
  end

  test "handle_info(:connect_phoenix) connects to phoenix", %{server: server} do
    GenServer.cast(server, :connect_phoenix)
    Process.sleep(2000)
    # wait for the connect message
    assert GenServer.call(server, :allMappings) != nil

    assert GenServer.call(server, :isKnown, :channel) != nil
  end

  test "handle_info(:get_data) fetches new data and pushes it to queue", %{
    server: server,
    config: config
  } do
    # Replace BiosenseData with the mock
    with_mock(BiosenseData,
      fetch_sensor_data: fn _ -> MockBiosenseData.fetch_sensor_data(config) end
    ) do
      GenServer.cast(server, :get_data)
      Process.sleep(100)
      assert GenServer.call(server, :allMappings) != nil
      assert GenServer.call(server, :isKnown, :messages_queue) != nil
      assert Enum.count(GenServer.call(server, :messages_queue)) > 0
    end
  end

  test "handle_info(:process_queue) and messages handling", %{server: server, config: config} do
    with_mock(BiosenseData,
      fetch_sensor_data: fn _ -> MockBiosenseData.fetch_sensor_data(config) end
    ) do
      GenServer.cast(server, :connect_phoenix)
      Process.sleep(100)
      GenServer.cast(server, :get_data)
      Process.sleep(100)
      # wait for the get data to complete

      GenServer.cast(server, :process_queue)
      # assert that the queue has a message
      Process.sleep(1000)
      assert GenServer.call(server, :allMappings) != nil

      assert GenServer.call(server, :isKnown, :messages_queue) != nil

      assert Enum.count(GenServer.call(server, :messages_queue)) == 1
    end
  end

  test "handle_cast(:process_queue) empty queue handling", %{server: server, config: config} do
    with_mock(BiosenseData,
      fetch_sensor_data: fn _ -> MockBiosenseData.fetch_sensor_data_no_data(config) end
    ) do
      # Replace BiosenseData with the mock, fetch_sensor_data_no_data
      GenServer.cast(server, :connect_phoenix)
      Process.sleep(100)
      # wait for the connect message
      GenServer.cast(server, :get_data)
      Process.sleep(100)
      GenServer.cast(server, :process_queue)

      Process.sleep(1000)

      assert GenServer.call(server, :allMappings) != nil

      assert GenServer.call(server, :isKnown, :messages_queue) != nil

      assert Enum.count(GenServer.call(server, :messages_queue)) > 0
    end
  end
end
