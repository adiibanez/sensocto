defmodule SensoctoWeb.SensorDataChannelTest do
  use SensoctoWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      SensoctoWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(SensoctoWeb.SensorDataChannel, "sensor_data:lobby")

    %{socket: socket}
  end

  # ref = push(socket, "ping", %{"hello" => "there"})
  # test "ping replies with status ok", %{socket: socket} do
  #  assert_reply ref, :ok, %{"hello" => "there"}
  # end

  # push(socket, "shout", %{"hello" => "all"})
  # test "shout broadcasts to sensor_data:lobby", %{socket: socket} do
  #  assert_broadcast "shout", %{"hello" => "all"}
  # end

  test "broadcasts are pushed to the client", %{socket: socket} do
    broadcast_from!(socket, "broadcast", %{"some" => "data"})
    assert_push "broadcast", %{"some" => "data"}
  end

  test "send measurment", %{socket: socket} do
    ref = push(socket, "ping", %{"measurement" => "1"})
    assert_reply ref, :ok, %{"measurement" => "1"}
  end
end
