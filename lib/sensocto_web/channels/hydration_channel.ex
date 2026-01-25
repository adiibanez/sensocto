defmodule SensoctoWeb.HydrationChannel do
  @moduledoc """
  Phoenix Channel for client-side room snapshot storage.

  This channel enables browsers to participate in room state persistence:

  ## Client → Server Events

  - `snapshot:offer` - Client announces available snapshots
    ```json
    {"room_id": "uuid", "version": 123456, "checksum": "sha256hex"}
    ```

  - `snapshot:data` - Client provides requested snapshot data
    ```json
    {"request_id": "reqid", "snapshot": {...}}
    ```

  ## Server → Client Events

  - `snapshot:request` - Server requests snapshot from client
    ```json
    {"room_id": "uuid", "request_id": "reqid"}
    ```

  - `snapshot:store` - Server pushes snapshot to client for storage
    ```json
    {"room_id": "uuid", "snapshot": {...}}
    ```

  - `snapshot:delete` - Server requests client delete a snapshot
    ```json
    {"room_id": "uuid"}
    ```

  ## Topic Format

  Clients join topic `hydration:room:*` where `*` is a wildcard or specific room_id.
  """

  use Phoenix.Channel
  require Logger

  alias Sensocto.Storage.Backends.LocalStorageBackend

  @impl true
  def join("hydration:room:" <> room_pattern, payload, socket) do
    client_id = generate_client_id()

    # Register this client
    LocalStorageBackend.client_connected(client_id)

    # Subscribe to hydration commands
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "hydration:commands")

    socket =
      socket
      |> assign(:client_id, client_id)
      |> assign(:room_pattern, room_pattern)
      |> assign(:offered_rooms, MapSet.new())

    # If client sent initial offers, process them
    if offers = payload["offers"] do
      process_initial_offers(offers, socket)
    end

    Logger.debug("[HydrationChannel] Client #{client_id} joined hydration:room:#{room_pattern}")
    {:ok, %{client_id: client_id}, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    client_id = socket.assigns[:client_id]

    if client_id do
      LocalStorageBackend.client_disconnected(client_id)
      Logger.debug("[HydrationChannel] Client #{client_id} disconnected")
    end

    :ok
  end

  # ============================================================================
  # Incoming Events from Client
  # ============================================================================

  @impl true
  def handle_in("snapshot:offer", payload, socket) do
    room_id = payload["room_id"]
    version = payload["version"]
    checksum = payload["checksum"]

    if room_id && version do
      LocalStorageBackend.client_offers_snapshot(room_id, version, checksum)

      socket = update_in(socket.assigns[:offered_rooms], &MapSet.put(&1, room_id))

      Logger.debug(
        "[HydrationChannel] Client #{socket.assigns.client_id} offers snapshot for #{room_id}"
      )

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "missing room_id or version"}}, socket}
    end
  end

  @impl true
  def handle_in("snapshot:data", payload, socket) do
    request_id = payload["request_id"]
    snapshot_data = payload["snapshot"]

    if request_id && snapshot_data do
      snapshot = parse_snapshot(snapshot_data)
      LocalStorageBackend.client_provides_snapshot(request_id, snapshot)

      Logger.debug(
        "[HydrationChannel] Client #{socket.assigns.client_id} provided snapshot for request #{request_id}"
      )

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "missing request_id or snapshot"}}, socket}
    end
  end

  @impl true
  def handle_in("snapshot:batch_offer", payload, socket) do
    offers = payload["offers"] || []

    Enum.each(offers, fn offer ->
      room_id = offer["room_id"]
      version = offer["version"]
      checksum = offer["checksum"]

      if room_id && version do
        LocalStorageBackend.client_offers_snapshot(room_id, version, checksum)
      end
    end)

    room_ids = Enum.map(offers, & &1["room_id"]) |> Enum.reject(&is_nil/1) |> MapSet.new()
    socket = update_in(socket.assigns[:offered_rooms], &MapSet.union(&1, room_ids))

    {:reply, {:ok, %{accepted: MapSet.size(room_ids)}}, socket}
  end

  @impl true
  def handle_in("snapshot:stored", payload, socket) do
    room_id = payload["room_id"]

    Logger.debug(
      "[HydrationChannel] Client #{socket.assigns.client_id} confirmed storage of #{room_id}"
    )

    {:noreply, socket}
  end

  # ============================================================================
  # Incoming Events from PubSub (server-side commands)
  # ============================================================================

  @impl true
  def handle_info({:store_snapshot, room_id, snapshot}, socket) do
    if matches_pattern?(room_id, socket.assigns.room_pattern) do
      push(socket, "snapshot:store", %{
        room_id: room_id,
        snapshot: serialize_snapshot(snapshot)
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:request_snapshot, room_id, request_id}, socket) do
    # Only request from clients that have offered this room
    if MapSet.member?(socket.assigns.offered_rooms, room_id) do
      push(socket, "snapshot:request", %{
        room_id: room_id,
        request_id: request_id
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:delete_snapshot, room_id}, socket) do
    if matches_pattern?(room_id, socket.assigns.room_pattern) do
      push(socket, "snapshot:delete", %{room_id: room_id})

      socket = update_in(socket.assigns[:offered_rooms], &MapSet.delete(&1, room_id))
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_client_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp process_initial_offers(offers, _socket) when is_list(offers) do
    Enum.each(offers, fn offer ->
      room_id = offer["room_id"]
      version = offer["version"]
      checksum = offer["checksum"]

      if room_id && version do
        LocalStorageBackend.client_offers_snapshot(room_id, version, checksum)
      end
    end)
  end

  defp process_initial_offers(_, _socket), do: :ok

  defp matches_pattern?(_room_id, "*"), do: true
  defp matches_pattern?(room_id, pattern), do: room_id == pattern

  defp parse_snapshot(data) when is_map(data) do
    %{
      room_id: data["room_id"],
      data: parse_room_data(data["data"] || data),
      version: data["version"] || 0,
      timestamp: parse_timestamp(data["timestamp"]),
      checksum: data["checksum"]
    }
  end

  defp parse_room_data(data) when is_map(data) do
    # Convert sensor_ids to MapSet
    sensor_ids =
      case data["sensor_ids"] do
        list when is_list(list) -> MapSet.new(list)
        _ -> MapSet.new()
      end

    # Normalize members
    members =
      (data["members"] || %{})
      |> Map.new(fn {user_id, role} ->
        {user_id, normalize_role(role)}
      end)

    %{
      id: data["id"],
      name: data["name"],
      description: data["description"],
      owner_id: data["owner_id"],
      join_code: data["join_code"],
      is_public: data["is_public"],
      calls_enabled: data["calls_enabled"],
      media_playback_enabled: data["media_playback_enabled"],
      object_3d_enabled: data["object_3d_enabled"],
      configuration: data["configuration"] || %{},
      members: members,
      sensor_ids: sensor_ids,
      created_at: parse_timestamp(data["created_at"]),
      updated_at: parse_timestamp(data["updated_at"])
    }
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(%DateTime{} = dt), do: dt
  defp parse_timestamp(_), do: DateTime.utc_now()

  defp normalize_role("owner"), do: :owner
  defp normalize_role("admin"), do: :admin
  defp normalize_role("member"), do: :member
  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role(_), do: :member

  defp serialize_snapshot(snapshot) do
    %{
      room_id: snapshot.room_id,
      data: serialize_room_data(snapshot.data),
      version: snapshot.version,
      timestamp: DateTime.to_iso8601(snapshot.timestamp),
      checksum: snapshot.checksum
    }
  end

  defp serialize_room_data(data) do
    data
    |> Map.update(:sensor_ids, [], fn
      %MapSet{} = set -> MapSet.to_list(set)
      list when is_list(list) -> list
      _ -> []
    end)
    |> Map.update(:members, %{}, fn members ->
      Map.new(members, fn {user_id, role} ->
        {user_id, Atom.to_string(role)}
      end)
    end)
    |> Map.update(:created_at, nil, &datetime_to_string/1)
    |> Map.update(:updated_at, nil, &datetime_to_string/1)
  end

  defp datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_to_string(other), do: other
end
