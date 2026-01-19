defmodule SensoctoWeb.BridgeChannel do
  @moduledoc """
  Bridge channel for the iroh-bridge sidecar.

  This channel allows the iroh-bridge to:
  - Subscribe to Phoenix topics and receive messages
  - Publish messages from iroh P2P to Phoenix subscribers
  - Manage topic subscriptions

  Message format (externally tagged):
  ```json
  {
    "version": 1,
    "message_id": "uuid",
    "timestamp": 1234567890,
    "source": {"Phoenix": {"user_id": "..."}},
    "payload": {"SensorReading": {"user_id": "...", ...}}
  }
  ```
  """
  use SensoctoWeb, :channel

  alias Phoenix.PubSub

  @impl true
  def join("bridge:control", _payload, socket) do
    # Control channel for managing subscriptions
    {:ok, socket}
  end

  @impl true
  def join("bridge:topic:" <> topic, _payload, socket) do
    # Subscribe to Phoenix PubSub for this topic
    PubSub.subscribe(Sensocto.PubSub, topic)

    socket =
      socket
      |> assign(:topic, topic)
      |> assign(:subscribed_topics, [topic | socket.assigns[:subscribed_topics] || []])

    {:ok, socket}
  end

  @impl true
  def handle_in("publish", %{"envelope" => envelope}, socket) do
    topic = socket.assigns[:topic]

    if topic do
      # Broadcast to all Phoenix subscribers
      PubSub.broadcast(Sensocto.PubSub, topic, {:bridge_message, envelope})

      # Also broadcast to room channel subscribers if this is a room topic
      case parse_topic(topic) do
        {:room, room_id} ->
          broadcast_to_room(room_id, envelope)

        _ ->
          :ok
      end
    end

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("subscribe", %{"topic" => topic}, socket) do
    PubSub.subscribe(Sensocto.PubSub, topic)

    subscribed = [topic | socket.assigns[:subscribed_topics] || []]
    socket = assign(socket, :subscribed_topics, Enum.uniq(subscribed))

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("unsubscribe", %{"topic" => topic}, socket) do
    PubSub.unsubscribe(Sensocto.PubSub, topic)

    subscribed = List.delete(socket.assigns[:subscribed_topics] || [], topic)
    socket = assign(socket, :subscribed_topics, subscribed)

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("heartbeat", _payload, socket) do
    {:reply, {:ok, %{status: "ok"}}, socket}
  end

  # Handle PubSub messages from other Phoenix channels
  @impl true
  def handle_info({:bridge_message, envelope}, socket) do
    # Forward to bridge (which will send to iroh)
    push(socket, "message", %{envelope: envelope})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sensor_reading, reading}, socket) do
    # Convert internal format to bridge envelope
    envelope = build_sensor_envelope(reading)
    push(socket, "message", %{envelope: envelope})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:presence_update, presence}, socket) do
    envelope = build_presence_envelope(presence)
    push(socket, "message", %{envelope: envelope})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helpers

  defp parse_topic("sensocto:room:" <> room_id), do: {:room, room_id}
  defp parse_topic("sensocto:sensor:" <> user_id), do: {:sensor, user_id}
  defp parse_topic("sensocto:presence:" <> user_id), do: {:presence, user_id}
  defp parse_topic(_), do: :unknown

  defp broadcast_to_room(room_id, envelope) do
    # Broadcast to the room's Phoenix channel
    SensoctoWeb.Endpoint.broadcast("sensocto:room:#{room_id}", "bridge_message", %{
      envelope: envelope
    })
  end

  defp build_sensor_envelope(reading) do
    %{
      "version" => 1,
      "message_id" => UUID.uuid4(),
      "timestamp" => System.system_time(:millisecond),
      "source" => %{"Phoenix" => %{"user_id" => reading.user_id}},
      "payload" => %{
        "SensorReading" => %{
          "user_id" => reading.user_id,
          "sensor_id" => reading.sensor_id,
          "heart_rate" => reading.heart_rate,
          "rr_intervals" => reading.rr_intervals || [],
          "battery" => reading.battery
        }
      }
    }
  end

  defp build_presence_envelope(presence) do
    %{
      "version" => 1,
      "message_id" => UUID.uuid4(),
      "timestamp" => System.system_time(:millisecond),
      "source" => %{"Phoenix" => %{"user_id" => presence.user_id}},
      "payload" => %{
        "Presence" => %{
          "user_id" => presence.user_id,
          "online" => presence.online,
          "display_name" => presence.display_name,
          "sensor_count" => presence.sensor_count || 0
        }
      }
    }
  end
end
