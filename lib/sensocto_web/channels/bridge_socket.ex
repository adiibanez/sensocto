defmodule SensoctoWeb.BridgeSocket do
  use Phoenix.Socket

  # Channel for the iroh bridge to connect to
  channel("bridge:*", SensoctoWeb.BridgeChannel)

  @impl true
  def connect(params, socket, _connect_info) do
    # Optionally verify a shared secret or token
    case Map.get(params, "token") do
      nil ->
        # Allow connection without token for development
        {:ok, socket}

      token ->
        # In production, verify the token against a configured secret
        if valid_bridge_token?(token) do
          {:ok, socket}
        else
          {:error, :unauthorized}
        end
    end
  end

  @impl true
  def id(_socket), do: "bridge:sidecar"

  defp valid_bridge_token?(token) do
    # Compare against configured bridge token
    configured_token = Application.get_env(:sensocto, :bridge_token)

    case configured_token do
      # Allow any token if not configured
      nil -> true
      expected -> Plug.Crypto.secure_compare(token, expected)
    end
  end
end
