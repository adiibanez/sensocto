defmodule SensoctoWeb.ViewerDataChannel do
  @moduledoc """
  Phoenix Channel that delivers high-frequency sensor data directly to browser viewers,
  bypassing the LobbyLive process mailbox entirely for all views.

  ## Data flow

  PriorityLens → PubSub (lens:priority:{socket_id}) → ViewerDataChannel → browser

  The browser joins this channel after receiving a signed viewer token from LobbyLive.
  The token encodes the LiveView socket ID so this channel can subscribe to the correct
  PriorityLens PubSub topic.

  ## Relationship with LobbyLive

  - LobbyLive registers with PriorityLens and manages quality/backpressure
  - ViewerDataChannel delivers the actual batch data for ALL views (composite, graph, sensors)
  - For the sensors grid, the JS SensorGridHook sends visible sensor IDs via
    `set_visible_sensors` — the channel only forwards data for those sensors
  """
  use SensoctoWeb, :channel
  require Logger

  @token_salt "viewer_data"
  @token_max_age_s 3_600

  @impl true
  def join("viewer:data:" <> token, _params, socket) do
    case Phoenix.Token.verify(SensoctoWeb.Endpoint, @token_salt, token, max_age: @token_max_age_s) do
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

  # Sensors grid: JS reports which sensor IDs are currently visible.
  # We store them as a MapSet so handle_info can filter batches before pushing.
  @impl true
  def handle_in("set_visible_sensors", %{"sensor_ids" => sensor_ids}, socket)
      when is_list(sensor_ids) do
    {:noreply, assign(socket, :visible_sensor_ids, MapSet.new(sensor_ids))}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  # Batch data from PriorityLens flush — relay to browser.
  # Format: %{sensor_id => %{attr_id => measurement_or_list_or_delta_encoded}}
  # For the sensors grid (visible_sensor_ids set), only forward visible sensors.
  @impl true
  def handle_info({:lens_batch, batch_data}, socket) do
    batch_to_push =
      case socket.assigns[:visible_sensor_ids] do
        nil ->
          # Composite/graph mode: push all sensors
          batch_data

        visible_ids ->
          # Sensors grid mode: filter to visible sensors only
          Map.filter(batch_data, fn {sensor_id, _} -> MapSet.member?(visible_ids, sensor_id) end)
      end

    if map_size(batch_to_push) > 0 do
      push(socket, "sensor_batch", %{batch: batch_to_push})
    end

    {:noreply, socket}
  end

  # Digest data from PriorityLens flush — relay to browser.
  # Format: %{sensor_id => %{attr_id => %{count, avg, min, max, latest}}}
  def handle_info({:lens_digest, digests}, socket) do
    digests_to_push =
      case socket.assigns[:visible_sensor_ids] do
        nil -> digests
        visible_ids -> Map.filter(digests, fn {id, _} -> MapSet.member?(visible_ids, id) end)
      end

    if map_size(digests_to_push) > 0 do
      push(socket, "sensor_digest", %{digests: digests_to_push})
    end

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
