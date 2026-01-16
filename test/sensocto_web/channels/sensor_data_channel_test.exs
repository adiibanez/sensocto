defmodule SensoctoWeb.SensorDataChannelTest do
  use SensoctoWeb.ChannelCase

  @test_connector_id "test_connector_#{:erlang.unique_integer([:positive])}"

  setup do
    # Use the sensocto:lvntest topic which has a simple join handler
    {:ok, _, socket} =
      SensoctoWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(
        SensoctoWeb.SensorDataChannel,
        "sensocto:lvntest:#{@test_connector_id}"
      )

    %{socket: socket}
  end

  test "broadcasts are pushed to the client", %{socket: socket} do
    broadcast_from!(socket, "broadcast", %{"some" => "data"})
    assert_push("broadcast", %{"some" => "data"})
  end

  test "ping replies with payload", %{socket: socket} do
    ref = push(socket, "ping", %{"measurement" => "1"})
    assert_reply(ref, :ok, %{"measurement" => "1"})
  end
end
