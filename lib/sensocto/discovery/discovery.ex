defmodule Sensocto.Discovery do
  @moduledoc """
  Public API for distributed entity discovery.

  Provides fast, non-blocking access to cluster-wide entity lists.
  Uses local ETS cache for reads, with background sync for updates.

  ## Design Principles

  1. **Fast reads**: List operations read from local ETS cache
  2. **Non-blocking**: Never blocks on slow/dead nodes for listing
  3. **Staleness awareness**: Returns freshness indicators
  4. **Graceful degradation**: Returns cached data when remote calls fail

  ## Usage

      # List all sensors (fast, from local cache)
      sensors = Discovery.list_sensors()

      # Get specific sensor with freshness info
      case Discovery.get_sensor_state(sensor_id) do
        {:ok, state, :fresh} -> # Recent data
        {:ok, state, :stale} -> # Cached, but might be outdated
        {:error, :not_found} -> # Sensor not in cluster
      end

      # Subscribe to real-time updates
      Discovery.subscribe(:sensors)
  """

  alias Sensocto.Discovery.DiscoveryCache

  @doc """
  Lists all sensors in the cluster.

  Returns immediately from local cache. Does NOT block on remote nodes.

  ## Options

  - `:type` - Filter by sensor type
  - `:connector_id` - Filter by connector ID
  """
  def list_sensors(opts \\ []) do
    sensors = DiscoveryCache.list_sensors()

    sensors
    |> maybe_filter_by_type(opts[:type])
    |> maybe_filter_by_connector(opts[:connector_id])
  end

  @doc """
  Gets sensor state with staleness indicator.

  Tries local cache first. If stale or not found, attempts direct lookup
  with timeout to avoid blocking.

  ## Returns

  - `{:ok, state, :fresh}` - Recent data from cache
  - `{:ok, state, :stale}` - Cached data, may be outdated
  - `{:error, :not_found}` - Sensor not in cluster
  """
  def get_sensor_state(sensor_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2_000)

    case DiscoveryCache.get_sensor(sensor_id) do
      {:ok, data, :fresh} ->
        {:ok, data, :fresh}

      {:ok, data, :stale} ->
        # Stale data - try to refresh in background but return stale immediately
        spawn(fn -> refresh_sensor(sensor_id, timeout) end)
        {:ok, data, :stale}

      {:error, :not_found} ->
        # Try direct lookup with timeout
        try_direct_lookup(sensor_id, timeout)
    end
  end

  @doc """
  Lists all rooms in the cluster.

  For rooms, we use Horde registry directly since room state is relatively static.

  ## Options

  - `:public_only` - Only return public rooms
  - `:owner_id` - Filter by owner
  """
  def list_rooms(opts \\ []) do
    Sensocto.RoomsDynamicSupervisor.list_rooms_with_state()
    |> maybe_filter_public(opts[:public_only])
    |> maybe_filter_by_owner(opts[:owner_id])
  end

  @doc """
  Lists all online users using Presence.
  """
  def list_users do
    SensoctoWeb.Sensocto.Presence.list("presence:all")
  end

  @doc """
  Subscribe to discovery updates for a specific entity type.

  Available types: `:sensors`, `:rooms`
  """
  def subscribe(entity_type) when entity_type in [:sensors, :rooms] do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "discovery:#{entity_type}")
  end

  @doc """
  Unsubscribe from discovery updates.
  """
  def unsubscribe(entity_type) when entity_type in [:sensors, :rooms] do
    Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "discovery:#{entity_type}")
  end

  @doc """
  Get cluster health information for discovery.
  """
  def cluster_health do
    nodes = [node() | Node.list()]

    %{
      nodes: length(nodes),
      node_names: nodes,
      sensors: DiscoveryCache.sensor_count(),
      rooms: length(list_rooms()),
      users: map_size(list_users())
    }
  end

  @doc """
  Force a sync of the discovery cache.
  Useful for debugging or after node joins.
  """
  def force_sync do
    Sensocto.Discovery.SyncWorker.force_sync()
  end

  # Private helpers

  defp try_direct_lookup(sensor_id, timeout) do
    task =
      Task.async(fn ->
        try do
          state = Sensocto.SimpleSensor.get_view_state(sensor_id)

          view_state = %{
            sensor_id: sensor_id,
            sensor_name: Map.get(state, :sensor_name, sensor_id),
            sensor_type: Map.get(state, :sensor_type),
            connector_id: Map.get(state, :connector_id),
            connector_name: Map.get(state, :connector_name),
            node: node()
          }

          DiscoveryCache.put_sensor(sensor_id, view_state)
          {:ok, view_state}
        catch
          :exit, _ -> {:error, :not_found}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, state}} -> {:ok, state, :fresh}
      {:ok, {:error, :not_found}} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp refresh_sensor(sensor_id, _timeout) do
    try do
      state = Sensocto.SimpleSensor.get_view_state(sensor_id)

      view_state = %{
        sensor_id: sensor_id,
        sensor_name: Map.get(state, :sensor_name, sensor_id),
        sensor_type: Map.get(state, :sensor_type),
        connector_id: Map.get(state, :connector_id),
        connector_name: Map.get(state, :connector_name),
        node: node()
      }

      DiscoveryCache.put_sensor(sensor_id, view_state)
    catch
      :exit, _ -> :ok
    end
  end

  defp maybe_filter_by_type(sensors, nil), do: sensors

  defp maybe_filter_by_type(sensors, type) do
    Enum.filter(sensors, &(&1.sensor_type == type))
  end

  defp maybe_filter_by_connector(sensors, nil), do: sensors

  defp maybe_filter_by_connector(sensors, connector_id) do
    Enum.filter(sensors, &(&1.connector_id == connector_id))
  end

  defp maybe_filter_public(rooms, nil), do: rooms
  defp maybe_filter_public(rooms, false), do: rooms

  defp maybe_filter_public(rooms, true) do
    Enum.filter(rooms, & &1.is_public)
  end

  defp maybe_filter_by_owner(rooms, nil), do: rooms

  defp maybe_filter_by_owner(rooms, owner_id) do
    Enum.filter(rooms, &(&1.owner_id == owner_id))
  end
end
