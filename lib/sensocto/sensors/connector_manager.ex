defmodule Sensocto.Sensors.ConnectorManager do
  @moduledoc """
  Distributed connector coordination using :pg process groups.

  This GenServer manages connector state across the Erlang cluster:
  - Registers connector processes in :pg groups for cluster-wide discovery
  - Broadcasts connector status changes to all nodes
  - Handles node up/down events to clean up stale connectors
  - Provides cluster-wide connector queries

  ## Architecture

  Each node runs one ConnectorManager process. When a connector registers:
  1. The Ash Postgres resource stores the connector data persistently
  2. Runtime state (pid, node) is tracked in GenServer state (not in DB)
  3. The connector's handling process joins the `:connectors` pg group
  4. The manager broadcasts the registration to all nodes via PubSub

  When a client disconnects:
  1. The connector is soft-unregistered (status set to :offline)
  2. The pid/node entry is removed from GenServer state
  3. The connector persists in DB for the user's "My Devices" view

  On startup:
  1. All connectors on this node are marked :offline (stale cleanup)
  """

  use GenServer
  require Logger

  alias Sensocto.Sensors.Connector

  @pg_group :connectors
  @pubsub Sensocto.PubSub
  @pubsub_topic "connector:events"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new connector when a client connects.

  Creates (or re-onlines) a persistent connector record and tracks the
  runtime pid/node in GenServer state.

  ## Parameters
  - `id` - Unique connector ID (usually socket ID). If nil, a new UUID is generated.
  - `name` - Human-readable name
  - `connector_type` - One of :web, :native, :iot, :simulator
  - `user_id` - Optional user ID if authenticated
  - `pid` - The process handling this connector
  - `opts` - Additional options (configuration map)
  """
  @spec register(String.t() | nil, String.t(), atom(), String.t() | nil, pid(), keyword()) ::
          {:ok, Connector.t()} | {:error, term()}
  def register(id, name, connector_type, user_id, pid, opts \\ []) do
    GenServer.call(__MODULE__, {:register, id, name, connector_type, user_id, pid, opts})
  end

  @doc """
  Soft-unregister a connector when client disconnects.
  Sets status to :offline but keeps the record for "My Devices".
  """
  @spec unregister(String.t()) :: :ok | {:error, term()}
  def unregister(id) do
    GenServer.call(__MODULE__, {:unregister, id})
  end

  @doc """
  Update connector's last_seen_at (heartbeat).
  """
  @spec heartbeat(String.t()) :: :ok | {:error, term()}
  def heartbeat(id) do
    GenServer.cast(__MODULE__, {:heartbeat, id})
  end

  @doc """
  Set connector status.
  """
  @spec set_status(String.t(), :online | :offline | :idle) :: :ok | {:error, term()}
  def set_status(id, status) do
    GenServer.call(__MODULE__, {:set_status, id, status})
  end

  @doc """
  List all connectors across the cluster.
  """
  @spec list_all() :: [Connector.t()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  List connectors for a specific user across the cluster.
  """
  @spec list_for_user(String.t()) :: [Connector.t()]
  def list_for_user(user_id) do
    GenServer.call(__MODULE__, {:list_for_user, user_id})
  end

  @doc """
  List online connectors across the cluster.
  """
  @spec list_online() :: [Connector.t()]
  def list_online do
    GenServer.call(__MODULE__, :list_online)
  end

  @doc """
  Get a connector by ID.
  """
  @spec get(String.t()) :: {:ok, Connector.t()} | {:error, :not_found}
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @doc """
  Get the runtime pid for a connector (from GenServer state, not DB).
  """
  @spec get_pid(String.t()) :: pid() | nil
  def get_pid(id) do
    GenServer.call(__MODULE__, {:get_pid, id})
  end

  @doc """
  Get the runtime node for a connector (from GenServer state, not DB).
  """
  @spec get_node(String.t()) :: node() | nil
  def get_node(id) do
    GenServer.call(__MODULE__, {:get_node, id})
  end

  @doc """
  Get connector count for a user.
  """
  @spec count_for_user(String.t()) :: non_neg_integer()
  def count_for_user(user_id) do
    user_id
    |> list_for_user()
    |> length()
  end

  @doc """
  Get all connector pids in the cluster (via :pg).
  """
  @spec get_cluster_pids() :: [pid()]
  def get_cluster_pids do
    :pg.get_members(@pg_group)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to cluster events
    :net_kernel.monitor_nodes(true)

    # Subscribe to connector events via PubSub
    Phoenix.PubSub.subscribe(@pubsub, @pubsub_topic)

    # Ensure pg group exists
    :pg.start_link()
    :pg.join(@pg_group, self())

    # Mark all connectors as offline on startup (stale cleanup)
    send(self(), :mark_stale_connectors)

    Logger.info("ConnectorManager started on #{node()}")

    # runtime_state: %{connector_id => %{pid: pid, node: node, monitor_ref: ref}}
    {:ok, %{node: node(), runtime_state: %{}}}
  end

  @impl true
  def handle_call({:register, id, name, connector_type, user_id, pid, opts}, _from, state) do
    configuration = Keyword.get(opts, :configuration, %{})

    result =
      if id do
        # Try to find existing connector and re-online it
        case get_connector(id) do
          {:ok, connector} ->
            connector
            |> Ash.Changeset.for_update(:set_online, %{})
            |> Ash.update()

          {:error, :not_found} ->
            # Create new with specific ID
            attrs = %{
              name: name,
              connector_type: connector_type,
              user_id: user_id,
              configuration: configuration
            }

            Connector
            |> Ash.Changeset.for_create(:register, attrs)
            |> Ash.Changeset.force_change_attribute(:id, id)
            |> Ash.create()
        end
      else
        attrs = %{
          name: name,
          connector_type: connector_type,
          user_id: user_id,
          configuration: configuration
        }

        Connector
        |> Ash.Changeset.for_create(:register, attrs)
        |> Ash.create()
      end

    case result do
      {:ok, connector} ->
        # Track runtime state
        monitor_ref = Process.monitor(pid)

        runtime_entry = %{pid: pid, node: node(), monitor_ref: monitor_ref}

        new_runtime =
          Map.put(state.runtime_state, to_string(connector.id), runtime_entry)

        # Join the pid to pg group for cluster tracking
        :pg.join(@pg_group, pid)

        # Broadcast to cluster
        broadcast_event(:connector_registered, connector)

        # Broadcast user-scoped event
        if user_id do
          broadcast_user_event(user_id, :connector_online, %{
            id: connector.id,
            name: connector.name,
            connector_type: connector.connector_type
          })
        end

        Logger.debug("Registered connector #{connector.id} (#{connector_type}) on #{node()}")
        {:reply, {:ok, connector}, %{state | runtime_state: new_runtime}}

      {:error, error} ->
        Logger.warning("Failed to register connector: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:unregister, id}, _from, state) do
    id_str = to_string(id)

    case get_connector(id) do
      {:ok, connector} ->
        # Leave pg group if pid is still alive
        case Map.get(state.runtime_state, id_str) do
          %{pid: pid, monitor_ref: ref} ->
            Process.demonitor(ref, [:flush])

            if Process.alive?(pid) do
              :pg.leave(@pg_group, pid)
            end

          _ ->
            :ok
        end

        # Soft-unregister: set offline instead of destroying
        case connector
             |> Ash.Changeset.for_update(:set_offline, %{})
             |> Ash.update() do
          {:ok, _updated} ->
            new_runtime = Map.delete(state.runtime_state, id_str)

            broadcast_event(:connector_unregistered, %{id: id, node: node()})

            if connector.user_id do
              broadcast_user_event(connector.user_id, :connector_offline, %{
                id: connector.id,
                name: connector.name
              })
            end

            Logger.debug("Soft-unregistered connector #{id}")
            {:reply, :ok, %{state | runtime_state: new_runtime}}

          {:error, error} ->
            {:reply, {:error, error}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:set_status, id, status}, _from, state) do
    action =
      case status do
        :online -> :set_online
        :offline -> :set_offline
        :idle -> :set_idle
      end

    case get_connector(id) do
      {:ok, connector} ->
        case connector
             |> Ash.Changeset.for_update(action, %{})
             |> Ash.update() do
          {:ok, updated} ->
            broadcast_event(:connector_status_changed, %{id: id, status: status, node: node()})
            {:reply, {:ok, updated}, state}

          {:error, error} ->
            {:reply, {:error, error}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    connectors = list_connectors()
    {:reply, connectors, state}
  end

  @impl true
  def handle_call({:list_for_user, user_id}, _from, state) do
    connectors =
      Connector
      |> Ash.Query.for_read(:list_for_user, %{user_id: user_id})
      |> Ash.read!()

    {:reply, connectors, state}
  end

  @impl true
  def handle_call(:list_online, _from, state) do
    connectors =
      Connector
      |> Ash.Query.for_read(:list_online, %{})
      |> Ash.read!()

    {:reply, connectors, state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    {:reply, get_connector(id), state}
  end

  @impl true
  def handle_call({:get_pid, id}, _from, state) do
    pid =
      case Map.get(state.runtime_state, to_string(id)) do
        %{pid: pid} -> pid
        _ -> nil
      end

    {:reply, pid, state}
  end

  @impl true
  def handle_call({:get_node, id}, _from, state) do
    node_val =
      case Map.get(state.runtime_state, to_string(id)) do
        %{node: n} -> n
        _ -> nil
      end

    {:reply, node_val, state}
  end

  @impl true
  def handle_cast({:heartbeat, id}, state) do
    case get_connector(id) do
      {:ok, connector} ->
        connector
        |> Ash.Changeset.for_update(:heartbeat, %{})
        |> Ash.update()

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:mark_stale_connectors, state) do
    # On startup, mark all connectors as offline since we lost runtime state
    case Connector |> Ash.Query.for_read(:list_online, %{}) |> Ash.read() do
      {:ok, online_connectors} ->
        Enum.each(online_connectors, fn connector ->
          connector
          |> Ash.Changeset.for_update(:set_offline, %{})
          |> Ash.update()
        end)

        if length(online_connectors) > 0 do
          Logger.info(
            "Marked #{length(online_connectors)} stale connectors as offline on startup"
          )
        end

      {:error, error} ->
        Logger.warning("Failed to mark stale connectors: #{inspect(error)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # Process died, clean up its connector
    case find_connector_by_ref(state.runtime_state, ref) do
      {id, _entry} ->
        Logger.debug("Cleaning up connector #{id} (process died)")

        case get_connector(id) do
          {:ok, connector} ->
            connector
            |> Ash.Changeset.for_update(:set_offline, %{})
            |> Ash.update()

            if connector.user_id do
              broadcast_user_event(connector.user_id, :connector_offline, %{
                id: connector.id,
                name: connector.name
              })
            end

          _ ->
            :ok
        end

        :pg.leave(@pg_group, pid)
        broadcast_event(:connector_unregistered, %{id: id, node: node()})
        {:noreply, %{state | runtime_state: Map.delete(state.runtime_state, id)}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:nodedown, down_node}, state) do
    Logger.info("Node #{down_node} went down, cleaning up connectors")

    # Remove runtime entries for the down node
    {removed, kept} =
      Enum.split_with(state.runtime_state, fn {_id, entry} -> entry.node == down_node end)

    Enum.each(removed, fn {id, _entry} ->
      case get_connector(id) do
        {:ok, connector} ->
          connector
          |> Ash.Changeset.for_update(:set_offline, %{})
          |> Ash.update()

        _ ->
          :ok
      end
    end)

    {:noreply, %{state | runtime_state: Map.new(kept)}}
  end

  @impl true
  def handle_info({:nodeup, up_node}, state) do
    Logger.info("Node #{up_node} joined the cluster")
    {:noreply, state}
  end

  @impl true
  def handle_info({:connector_event, event, data}, state) do
    # Handle events from other nodes
    handle_remote_event(event, data, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Helpers

  defp get_connector(id) do
    case Connector
         |> Ash.Query.for_read(:get_by_id, %{id: id})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, connector} -> {:ok, connector}
      {:error, error} -> {:error, error}
    end
  end

  defp list_connectors do
    Connector |> Ash.read!()
  end

  defp find_connector_by_ref(runtime_state, ref) do
    Enum.find(runtime_state, fn {_id, entry} -> entry.monitor_ref == ref end)
  end

  defp broadcast_event(event, data) do
    Phoenix.PubSub.broadcast(@pubsub, @pubsub_topic, {:connector_event, event, data})
  end

  @doc false
  def broadcast_user_event(user_id, event, data) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "user:#{user_id}:connectors",
      {:connector_event, event, data}
    )
  end

  defp handle_remote_event(:connector_registered, connector, _state) do
    Logger.debug("Remote connector registered: #{connector.id}")
  end

  defp handle_remote_event(:connector_unregistered, %{id: id, node: remote_node}, _state) do
    Logger.debug("Remote connector unregistered: #{id} on #{remote_node}")
  end

  defp handle_remote_event(
         :connector_status_changed,
         %{id: id, status: status, node: remote_node},
         _state
       ) do
    Logger.debug("Remote connector #{id} status changed to #{status} on #{remote_node}")
  end

  defp handle_remote_event(_event, _data, _state), do: :ok
end
