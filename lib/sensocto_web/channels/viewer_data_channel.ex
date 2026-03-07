defmodule SensoctoWeb.ViewerDataChannel do
  @moduledoc """
  Phoenix Channel that delivers high-frequency sensor data directly to browser viewers,
  bypassing the LobbyLive process mailbox entirely for composite and graph views.

  ## Data flow

  PriorityLens → PubSub (lens:priority:{socket_id}) → ViewerDataChannel → browser

  The browser joins this channel after receiving a signed viewer token from LobbyLive.
  The token encodes the LiveView socket ID so this channel can subscribe to the correct
  PriorityLens PubSub topic.

  ## Relationship with LobbyLive

  - LobbyLive registers with PriorityLens and manages quality levels
  - ViewerDataChannel delivers the actual batch data for composite/graph views
  - LobbyLive still subscribes to lens:priority for the sensors grid view (needs send_update)
  """
  use SensoctoWeb, :channel
  require Logger

  @token_salt "viewer_data"
  @token_max_age_s 3_600

  @impl true
  def join("viewer:data:" <> token, _params, socket) do
    case Phoenix.Token.verify(SensoctoWeb.Endpoint, @token_salt, token,
           max_age: @token_max_age_s
         ) do
      {:ok, lv_socket_id} ->
        topic = Sensocto.Lenses.PriorityLens.topic_for_socket(lv_socket_id)
        Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

        socket = assign(socket, :lv_socket_id, lv_socket_id)
        Logger.debug("[ViewerDataChannel] joined for LV socket #{lv_socket_id}")
        {:ok, socket}

      {:error, reason} ->
        Logger.warning("[ViewerDataChannel] token verification failed: #{inspect(reason)}")
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join(topic, _params, _socket) do
    Logger.warning("[ViewerDataChannel] unexpected join topic: #{inspect(topic)}")
    {:error, %{reason: "invalid_topic"}}
  end

  # Batch data from PriorityLens flush — relay to browser
  # Format: %{sensor_id => %{attr_id => measurement_or_list_or_delta_encoded}}
  @impl true
  def handle_info({:lens_batch, batch_data}, socket) do
    push(socket, "sensor_batch", %{batch: batch_data})
    {:noreply, socket}
  end

  # Digest data from PriorityLens flush — relay to browser
  # Format: %{sensor_id => %{attr_id => %{count, avg, min, max, latest}}}
  def handle_info({:lens_digest, digests}, socket) do
    push(socket, "sensor_digest", %{digests: digests})
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(reason, socket) do
    Logger.debug(
      "[ViewerDataChannel] terminated: #{inspect(reason)}, lv_socket=#{socket.assigns[:lv_socket_id]}"
    )

    :ok
  end
end
