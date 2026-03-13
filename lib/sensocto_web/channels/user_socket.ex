defmodule SensoctoWeb.UserSocket do
  use Phoenix.Socket

  ## Channels

  channel("sensocto:*", SensoctoWeb.SensorDataChannel)
  channel("room:*", SensoctoWeb.RoomChannel)
  channel("call:*", SensoctoWeb.CallChannel)
  channel("hydration:room:*", SensoctoWeb.HydrationChannel)
  channel("viewer:*", SensoctoWeb.ViewerDataChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(socket, "user_socket", token, max_age: 86_400) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _reason} ->
        # Log but still allow connection during migration period
        require Logger
        Logger.warning("UserSocket: invalid token, allowing anonymous connection")
        {:ok, assign(socket, :user_id, "anonymous")}
    end
  end

  def connect(_params, socket, _connect_info) do
    # Allow connections without token during migration period (with warning)
    require Logger
    Logger.warning("UserSocket: no token provided, allowing anonymous connection")
    {:ok, assign(socket, :user_id, "anonymous")}
  end

  @impl true
  def id(socket) do
    case socket.assigns[:user_id] do
      "anonymous" -> nil
      user_id -> "user_socket:#{user_id}"
    end
  end
end
