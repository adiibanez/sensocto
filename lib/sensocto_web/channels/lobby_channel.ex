defmodule SensoctoWeb.LobbyChannel do
  @moduledoc """
  Read-only channel for the lobby — the global room list.

  Mobile clients join "lobby:{user_id}" to get the initial room list
  and receive live updates as rooms are created/deleted/changed.

  No mutations happen here — room create/join/leave stay where they are.

  ## Events pushed to client

  - `lobby_state` — initial hydration: `{my_rooms, public_rooms}`
  - `room_added` — a public room was created or user was invited to a room
  - `room_removed` — room deleted or user was removed
  - `room_updated` — room metadata changed
  - `membership_changed` — member join/leave in one of user's rooms
  """
  use Phoenix.Channel
  require Logger

  alias Sensocto.RoomStore

  @impl true
  def join("lobby:" <> user_id, _params, socket) do
    if socket.assigns.user_id == user_id do
      send(self(), :after_join)
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "rooms:lobby")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:#{user_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id
    my_rooms = RoomStore.list_user_rooms(user_id) |> Enum.map(&room_to_json/1)
    public_rooms = RoomStore.list_public_rooms() |> Enum.map(&room_to_json/1)

    push(socket, "lobby_state", %{my_rooms: my_rooms, public_rooms: public_rooms})
    {:noreply, socket}
  end

  # --- PubSub events from RoomStore ---

  @impl true
  def handle_info({:lobby_room_created, room}, socket) do
    push(socket, "room_added", room_to_json(room))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:lobby_room_deleted, room_id}, socket) do
    push(socket, "room_removed", %{room_id: room_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:lobby_room_updated, room}, socket) do
    push(socket, "room_updated", room_to_json(room))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:membership_changed, room_id, action, user_id}, socket) do
    push(socket, "membership_changed", %{
      room_id: room_id,
      action: to_string(action),
      user_id: user_id
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp room_to_json(room) do
    sensors = resolve_room_sensors(room)

    %{
      id: room.id,
      name: room.name,
      description: Map.get(room, :description),
      owner_id: room.owner_id,
      join_code: Map.get(room, :join_code),
      is_public: Map.get(room, :is_public, false),
      created_at: format_datetime(Map.get(room, :created_at)),
      sensors: sensors,
      member_count: room |> Map.get(:members, %{}) |> map_size()
    }
  end

  defp resolve_room_sensors(room) do
    sensor_ids =
      case Map.get(room, :sensor_ids) do
        %MapSet{} = set -> MapSet.to_list(set)
        list when is_list(list) -> list
        _ -> []
      end

    Enum.map(sensor_ids, &resolve_sensor/1)
  end

  defp resolve_sensor(sensor_id) do
    case Sensocto.SensorsDynamicSupervisor.get_sensor_state(sensor_id, :view, 1) do
      %{} = wrapper when map_size(wrapper) > 0 ->
        sensor_state = wrapper |> Map.values() |> List.first()
        sensor_to_json(sensor_state)

      _ ->
        %{
          sensor_id: to_string(sensor_id),
          sensor_name: "Unknown",
          sensor_type: "generic",
          connector_id: nil,
          connector_name: "Unknown",
          activity_status: "offline",
          attributes: []
        }
    end
  end

  defp sensor_to_json(sensor) do
    attrs = Map.get(sensor, :attributes, %{}) || %{}

    attributes_list =
      case attrs do
        m when is_map(m) and not is_struct(m) ->
          Enum.map(m, fn {attr_name, attr_data} ->
            %{
              id: Map.get(attr_data, :attribute_id) || attr_name,
              attribute_type: to_string(Map.get(attr_data, :attribute_type) || attr_name),
              attribute_name: attr_name,
              last_value: Map.get(attr_data, :lastvalue)
            }
          end)

        _ ->
          []
      end

    %{
      sensor_id: Map.get(sensor, :sensor_id) || Map.get(sensor, :id),
      sensor_name: Map.get(sensor, :sensor_name) || Map.get(sensor, :name) || "Unknown",
      sensor_type: to_string(Map.get(sensor, :sensor_type) || "generic"),
      connector_id: Map.get(sensor, :connector_id) || Map.get(sensor, :user_id),
      connector_name: Map.get(sensor, :connector_name) || "Unknown",
      activity_status: to_string(Map.get(sensor, :activity_status) || "unknown"),
      attributes: attributes_list
    }
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(_), do: nil
end
