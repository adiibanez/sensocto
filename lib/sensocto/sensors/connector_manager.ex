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
  1. The local Ash ETS resource stores the connector data
  2. The connector's handling process joins the `:connectors` pg group
  3. The manager broadcasts the registration to all nodes via PubSub

  When a node goes down:
  1. The pg group automatically removes processes from that node
  2. Other managers receive :nodedown and clean up ETS entries

  ## Usage

      # Register a connector (called by socket/channel)
      ConnectorManager.register(connector_id, name, type, user_id, self())

      # List all connectors cluster-wide
      ConnectorManager.list_all()

      # List connectors for a specific user
      ConnectorManager.list_for_user(user_id)

      # Unregister on disconnect
      ConnectorManager.unregister(connector_id)
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

  ## Parameters
  - `id` - Unique connector ID (usually socket ID)
  - `name` - Human-readable name
  - `connector_type` - One of :web, :native, :iot, :simulator
  - `user_id` - Optional user ID if authenticated
  - `pid` - The process handling this connector
  - `opts` - Additional options (configuration map)
  """
  @spec register(String.t(), String.t(), atom(), String.t() | nil, pid(), keyword()) ::
          {:ok, Connector.t()} | {:error, term()}
  def register(id, name, connector_type, user_id, pid, opts \\ []) do
    GenServer.call(__MODULE__, {:register, id, name, connector_type, user_id, pid, opts})
  end

  @doc """
  Unregister a connector when client disconnects.
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

    Logger.info("ConnectorManager started on #{node()}")

    {:ok, %{node: node()}}
  end

  @impl true
  def handle_call({:register, id, name, connector_type, user_id, pid, opts}, _from, state) do
    configuration = Keyword.get(opts, :configuration, %{})

    attrs = %{
      id: id,
      name: name,
      connector_type: connector_type,
      user_id: user_id,
      configuration: configuration,
      node: node(),
      pid: pid
    }

    case Connector
         |> Ash.Changeset.for_create(:register, attrs)
         |> Ash.create() do
      {:ok, connector} ->
        # Join the pid to pg group for cluster tracking
        :pg.join(@pg_group, pid)

        # Monitor the process for automatic cleanup
        Process.monitor(pid)

        # Broadcast to cluster
        broadcast_event(:connector_registered, connector)

        Logger.debug("Registered connector #{id} (#{connector_type}) on #{node()}")
        {:reply, {:ok, connector}, state}

      {:error, error} ->
        Logger.warning("Failed to register connector #{id}: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:unregister, id}, _from, state) do
    case get_connector(id) do
      {:ok, connector} ->
        # Leave pg group if pid is still alive
        if connector.pid && Process.alive?(connector.pid) do
          :pg.leave(@pg_group, connector.pid)
        end

        # Destroy from ETS
        case Ash.destroy(connector) do
          :ok ->
            broadcast_event(:connector_unregistered, %{id: id, node: node()})
            Logger.debug("Unregistered connector #{id}")
            {:reply, :ok, state}

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
    connectors = list_local_connectors()
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
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Process died, clean up its connector
    cleanup_connector_by_pid(pid)
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, down_node}, state) do
    Logger.info("Node #{down_node} went down, cleaning up connectors")
    cleanup_connectors_for_node(down_node)
    {:noreply, state}
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

  defp list_local_connectors do
    Connector
    |> Ash.read!()
  end

  defp cleanup_connector_by_pid(pid) do
    # Find and remove connector with this pid
    list_local_connectors()
    |> Enum.find(fn c -> c.pid == pid end)
    |> case do
      nil ->
        :ok

      connector ->
        Logger.debug("Cleaning up connector #{connector.id} (process died)")
        Ash.destroy(connector)
        broadcast_event(:connector_unregistered, %{id: connector.id, node: node()})
    end
  end

  defp cleanup_connectors_for_node(down_node) do
    # Remove all connectors that were on the down node
    list_local_connectors()
    |> Enum.filter(fn c -> c.node == down_node end)
    |> Enum.each(fn connector ->
      Logger.debug("Cleaning up connector #{connector.id} (node down: #{down_node})")
      Ash.destroy(connector)
    end)
  end

  defp broadcast_event(event, data) do
    Phoenix.PubSub.broadcast(@pubsub, @pubsub_topic, {:connector_event, event, data})
  end

  defp handle_remote_event(:connector_registered, connector, _state) do
    # Another node registered a connector - we might want to cache it locally
    # For now, just log it
    Logger.debug("Remote connector registered: #{connector.id} on #{connector.node}")
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
