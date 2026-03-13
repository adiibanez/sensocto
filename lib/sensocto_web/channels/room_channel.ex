defmodule SensoctoWeb.RoomChannel do
  @moduledoc """
  Channel for real-time room updates (sensor add/remove, member changes).

  Mobile clients join "room:{room_id}" to receive live updates.
  """
  use Phoenix.Channel
  require Logger

  alias Sensocto.RoomStore

  @impl true
  def join("room:" <> room_id, _params, socket) do
    case Ecto.UUID.cast(room_id) do
      {:ok, room_id} ->
        user_id = socket.assigns[:user_id]

        if authorized_for_room?(room_id, user_id) do
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")
          send(self(), :after_join)
          {:ok, assign(socket, :room_id, room_id)}
        else
          {:error, %{reason: "unauthorized"}}
        end

      :error ->
        {:error, %{reason: "invalid room id"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id

    case RoomStore.get_room(room_id) do
      {:ok, room} when not is_nil(room) ->
        sensors = resolve_room_sensors(room)
        members = room |> Map.get(:members, %{}) |> map_size()

        push(socket, "room_state", %{
          room_id: room_id,
          sensors: sensors,
          member_count: members
        })

      _ ->
        Logger.warning("Room #{room_id} not found for channel")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_update, event}, socket) do
    room_id = socket.assigns.room_id

    case event do
      {:sensor_added, sensor_id} ->
        sensor = resolve_sensor(sensor_id)
        push(socket, "sensor_added", %{room_id: room_id, sensor: sensor})

      {:sensor_removed, sensor_id} ->
        push(socket, "sensor_removed", %{room_id: room_id, sensor_id: to_string(sensor_id)})

      {:member_joined, user_id, role} ->
        push(socket, "member_joined", %{room_id: room_id, user_id: user_id, role: role})

      {:member_left, user_id} ->
        push(socket, "member_left", %{room_id: room_id, user_id: user_id})

      {:sensor_measurement, _sensor_id} ->
        :ok

      :room_closed ->
        push(socket, "room_closed", %{room_id: room_id})

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp authorized_for_room?(room_id, user_id) do
    case RoomStore.get_room(room_id) do
      {:ok, room} when not is_nil(room) ->
        Map.get(room, :is_public, false) or RoomStore.is_member?(room_id, user_id)

      _ ->
        # Room not found in store — allow join (room may be loading)
        true
    end
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

  defp resolve_room_sensors(room) do
    sensor_ids =
      case Map.get(room, :sensor_ids) do
        %MapSet{} = set -> MapSet.to_list(set)
        list when is_list(list) -> list
        _ -> []
      end

    Enum.map(sensor_ids, &resolve_sensor/1)
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
end
