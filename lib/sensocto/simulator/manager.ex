defmodule Sensocto.Simulator.Manager do
  @moduledoc """
  Manages simulator connectors based on YAML configuration.
  Loads config on startup and supports hot-reloading.
  """

  use GenServer
  require Logger

  defstruct [:connectors, :config_path]

  @type t :: %__MODULE__{
          connectors: map(),
          config_path: String.t()
        }

  # Client API

  def start_link(config_path) do
    GenServer.start_link(__MODULE__, config_path, name: __MODULE__)
  end

  @doc """
  Reload configuration from YAML file.
  """
  def reload_config do
    GenServer.call(__MODULE__, :reload_config)
  end

  @doc """
  Get current manager state.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Get list of active connector IDs.
  """
  def list_connectors do
    GenServer.call(__MODULE__, :list_connectors)
  end

  @doc """
  Get connectors with their status for UI display.
  """
  def get_connectors do
    GenServer.call(__MODULE__, :get_connectors)
  end

  @doc """
  Get raw config data.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Stop a specific connector.
  """
  def stop_connector(connector_id) do
    GenServer.call(__MODULE__, {:stop_connector, connector_id})
  end

  @doc """
  Start a specific connector from config.
  """
  def start_connector(connector_id) do
    GenServer.call(__MODULE__, {:start_connector, connector_id})
  end

  @doc """
  Start all configured connectors.
  """
  def start_all do
    GenServer.call(__MODULE__, :start_all)
  end

  @doc """
  Stop all running connectors.
  """
  def stop_all do
    GenServer.call(__MODULE__, :stop_all)
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
  def handle_call(:reload_config, _from, state) do
    Logger.info("Reloading simulator config")
    new_state = load_config(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:stop_connector, connector_id}, _from, state) do
    do_stop_connector(connector_id)
    new_connectors = Map.delete(state.connectors, connector_id)
    {:reply, :ok, %{state | connectors: new_connectors}}
  end

  @impl true
  def handle_call({:start_connector, connector_id}, _from, state) do
    case Map.get(state.connectors, connector_id) do
      nil ->
        Logger.warning("Connector #{connector_id} not found in config")
        {:reply, {:error, :not_found}, state}

      config ->
        new_state = start_or_update_connector(state, connector_id, config)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_all, _from, state) do
    new_state =
      Enum.reduce(state.connectors, state, fn {connector_id, config}, acc ->
        start_or_update_connector(acc, connector_id, config)
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stop_all, _from, state) do
    Enum.each(state.connectors, fn {connector_id, _} ->
      do_stop_connector(connector_id)
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:list_connectors, _from, state) do
    {:reply, Map.keys(state.connectors), state}
  end

  @impl true
  def handle_call(:get_connectors, _from, state) do
    connectors_with_status =
      Map.new(state.connectors, fn {connector_id, config} ->
        status = get_connector_status(connector_id)
        sensors = get_connector_sensors(config)
        {connector_id, %{
          name: config["connector_name"] || connector_id,
          status: status,
          sensors: sensors
        }}
      end)

    {:reply, connectors_with_status, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.connectors, state}
  end

  # Private Functions

  defp load_config(%__MODULE__{config_path: path} = state) do
    # Try absolute path first, then relative to priv
    full_path =
      cond do
        File.exists?(path) -> path
        File.exists?(Path.join(:code.priv_dir(:sensocto), path)) ->
          Path.join(:code.priv_dir(:sensocto), path)
        File.exists?(Path.join(File.cwd!(), path)) ->
          Path.join(File.cwd!(), path)
        true -> path
      end

    Logger.info("Loading simulator config from #{full_path}")

    case YamlElixir.read_from_file(full_path) do
      {:ok, config} ->
        apply_config(state, config)

      {:error, reason} ->
        Logger.error("Failed to load simulator config: #{inspect(reason)}")
        state
    end
  end

  defp apply_config(state, config) do
    new_connectors_config = config["connectors"] || %{}

    # Stop removed connectors
    removed_connectors = Map.keys(state.connectors) -- Map.keys(new_connectors_config)
    Enum.each(removed_connectors, &do_stop_connector/1)

    # Check if we should autostart connectors
    simulator_config = Application.get_env(:sensocto, :simulator, [])
    autostart = Keyword.get(simulator_config, :autostart, true)

    if autostart do
      # Start/Update connectors
      Enum.reduce(new_connectors_config, %{state | connectors: %{}}, fn {connector_id, connector_config}, acc ->
        connector_config = Map.put(connector_config, "connector_id", connector_id)
        start_or_update_connector(acc, connector_id, connector_config)
      end)
    else
      # Just store config without starting - connectors can be started manually
      Logger.info("Autostart disabled - connectors loaded but not started")
      new_connectors =
        Map.new(new_connectors_config, fn {connector_id, connector_config} ->
          {connector_id, Map.put(connector_config, "connector_id", connector_id)}
        end)
      %{state | connectors: new_connectors}
    end
  end

  defp start_or_update_connector(state, connector_id, connector_config) do
    case DynamicSupervisor.start_child(
           Sensocto.Simulator.ConnectorSupervisor,
           {Sensocto.Simulator.ConnectorServer, connector_config}
         ) do
      {:ok, _pid} ->
        Logger.info("Started simulator connector: #{connector_id}")
        %{state | connectors: Map.put(state.connectors, connector_id, connector_config)}

      {:error, {:already_started, _}} ->
        update_connector(state, connector_id, connector_config)

      {:error, reason} ->
        Logger.error("Failed to start connector #{connector_id}: #{inspect(reason)}")
        state
    end
  end

  defp update_connector(state, connector_id, connector_config) do
    GenServer.cast(via_tuple(connector_id), {:update_config, connector_config})
    %{state | connectors: Map.put(state.connectors, connector_id, connector_config)}
  end

  defp do_stop_connector(connector_id) do
    case Registry.lookup(Sensocto.Simulator.Registry, "connector_#{connector_id}") do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Sensocto.Simulator.ConnectorSupervisor, pid)
        Logger.info("Stopped simulator connector: #{connector_id}")

      [] ->
        Logger.debug("Connector #{connector_id} not found in registry")
    end
  end

  defp via_tuple(connector_id) do
    {:via, Registry, {Sensocto.Simulator.Registry, "connector_#{connector_id}"}}
  end

  defp get_connector_status(connector_id) do
    case Registry.lookup(Sensocto.Simulator.Registry, "connector_#{connector_id}") do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: :running, else: :stopped

      [] ->
        :stopped
    end
  end

  defp get_connector_sensors(config) do
    sensors_config = config["sensors"] || %{}

    Map.new(sensors_config, fn {sensor_id, sensor_config} ->
      {sensor_id, %{
        name: sensor_config["sensor_name"] || sensor_id,
        attributes: sensor_config["attributes"] || %{}
      }}
    end)
  end
end
