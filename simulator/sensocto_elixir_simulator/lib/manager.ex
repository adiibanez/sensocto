defmodule Sensocto.Simulator.Manager do
  use GenServer
  require Logger

  defstruct [:connectors, :config_path]

  @type t :: %__MODULE__{
          # Map of connector_id => connector config
          connectors: map(),
          config_path: String.t()
        }

  # Client API
  def start_link(config_path) do
    GenServer.start_link(__MODULE__, config_path, name: __MODULE__)
  end

  def reload_config do
    GenServer.cast(__MODULE__, :reload_config)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks
  @impl true
  def init(config_path) do
    state = %__MODULE__{
      connectors: %{},
      config_path: config_path
    }

    {:ok, state, {:continue, :load_config}}
  end

  @impl true
  def handle_continue(:load_config, state) do
    new_state = load_config(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reload_config, state) do
    new_state = load_config(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Private Functions
  defp load_config(%__MODULE__{config_path: path} = state) do
    Logger.info("Loading config from #{path}")

    case YamlElixir.read_from_file(path) do
      {:ok, config} ->
        apply_config(state, config)

      {:error, reason} ->
        Logger.error("Failed to load config: #{inspect(reason)}")
        state
    end
  end

  defp apply_config(state, config) do
    # Stop removed connectors
    removed_connectors = Map.keys(state.connectors) -- Map.keys(config["connectors"] || %{})
    Enum.each(removed_connectors, &stop_connector/1)

    # Start/Update connectors
    new_connectors = config["connectors"] || %{}

    Enum.reduce(new_connectors, %{state | connectors: %{}}, fn {connector_id, connector_config},
                                                               acc ->
      connector_config = Map.put(connector_config, "connector_id", connector_id)
      start_or_update_connector(acc, connector_id, connector_config)
    end)
  end

  defp start_or_update_connector(state, connector_id, connector_config) do
    case DynamicSupervisor.start_child(
           Sensocto.Simulator.Manager.ManagerSupervisor,
           {Sensocto.Simulator.ConnectorGenServer, connector_config}
         ) do
      {:ok, _pid} ->
        %{state | connectors: Map.put(state.connectors, connector_id, connector_config)}

      {:error, {:already_started, _}} ->
        update_connector(state, connector_id, connector_config)

      {:error, reason} ->
        Logger.error("Failed to start connector #{connector_id}: #{inspect(reason)}")
        state
    end
  end

  defp update_connector(state, connector_id, connector_config) do
    # Update existing connector with new config
    GenServer.cast(via_tuple(connector_id), {:update_config, connector_config})
    %{state | connectors: Map.put(state.connectors, connector_id, connector_config)}
  end

  defp stop_connector(connector_id) do
    DynamicSupervisor.terminate_child(
      Sensocto.Simulator.Manager.ManagerSupervisor,
      via_tuple(connector_id)
    )
  end

  defp via_tuple(connector_id), do: {:via, Registry, {Sensocto.Registry, connector_id}}
end
