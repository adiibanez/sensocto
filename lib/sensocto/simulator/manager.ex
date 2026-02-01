defmodule Sensocto.Simulator.Manager do
  @moduledoc """
  Manages simulator connectors based on YAML configuration.
  Loads config on startup and supports hot-reloading.
  Supports multiple scenario configurations running simultaneously.
  """

  use GenServer
  require Logger

  alias Sensocto.Sensors.{SimulatorScenario, SimulatorConnector}

  @scenarios_dir "config/simulator_scenarios"
  # Delay hydration to allow HTTP server to start first (improves Fly.io routing)
  @hydration_delay_ms 5_000
  @sync_debounce_ms 500

  defstruct [:connectors, :config_path, :running_scenarios, :available_scenarios]

  @type t :: %__MODULE__{
          connectors: map(),
          config_path: String.t(),
          running_scenarios: map(),
          available_scenarios: list(map())
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

  @doc """
  Get list of available scenarios.
  """
  def list_scenarios do
    GenServer.call(__MODULE__, :list_scenarios)
  end

  @doc """
  Get the currently running scenarios.
  Returns a map of scenario_name => %{room_id: ..., connector_ids: [...]}
  """
  def get_running_scenarios do
    GenServer.call(__MODULE__, :get_running_scenarios)
  end

  @doc """
  Get a single running scenario name (for backwards compatibility).
  Returns the first running scenario or nil.
  """
  def get_current_scenario do
    case get_running_scenarios() do
      scenarios when map_size(scenarios) > 0 ->
        scenarios |> Map.keys() |> List.first()

      _ ->
        nil
    end
  end

  @doc """
  Start a scenario without stopping others.

  Options:
  - :room_id - assign all sensors to this room
  """
  def start_scenario(scenario_name, opts \\ []) do
    GenServer.call(__MODULE__, {:start_scenario, scenario_name, opts})
  end

  @doc """
  Stop a specific running scenario.
  """
  def stop_scenario(scenario_name) do
    GenServer.call(__MODULE__, {:stop_scenario, scenario_name})
  end

  @doc """
  Switch to a different scenario by name.
  Stops all current connectors and starts the new scenario.

  Options:
  - :room_id - assign all sensors to this room
  """
  def switch_scenario(scenario_name, opts \\ []) do
    GenServer.call(__MODULE__, {:switch_scenario, scenario_name, opts})
  end

  # Server Callbacks

  @impl true
  def init(config_path) do
    # Defer scenario discovery to avoid blocking startup with filesystem I/O
    state = %__MODULE__{
      connectors: %{},
      config_path: config_path,
      running_scenarios: %{},
      available_scenarios: []
    }

    # Schedule scenario discovery (filesystem I/O) after init
    Process.send_after(self(), :discover_scenarios, 1_000)

    # Schedule hydration from PostgreSQL after discovery completes
    Process.send_after(self(), :hydrate_from_postgres, @hydration_delay_ms)

    {:ok, state, {:continue, :load_config}}
  end

  @impl true
  def handle_continue(:load_config, state) do
    new_state = load_config(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:reload_config, _from, state) do
    Logger.info("Reloading simulator config and rediscovering scenarios")
    # Rediscover scenarios synchronously for reload (explicit user action)
    available_scenarios = do_discover_scenarios()
    new_state = load_config(%{state | available_scenarios: available_scenarios})
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

        {connector_id,
         %{
           name: config["connector_name"] || connector_id,
           status: status,
           sensors: sensors,
           scenario: config["scenario_name"],
           room_id: config["room_id"],
           room_name: get_room_name(config["room_id"])
         }}
      end)

    {:reply, connectors_with_status, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.connectors, state}
  end

  @impl true
  def handle_call(:list_scenarios, _from, state) do
    {:reply, state.available_scenarios, state}
  end

  @impl true
  def handle_call(:get_running_scenarios, _from, state) do
    {:reply, state.running_scenarios, state}
  end

  @impl true
  def handle_call({:start_scenario, scenario_name, opts}, _from, state) do
    # Check if scenario is already running
    if Map.has_key?(state.running_scenarios, scenario_name) do
      {:reply, {:error, :already_running}, state}
    else
      case Enum.find(state.available_scenarios, fn s -> s.name == scenario_name end) do
        nil ->
          {:reply, {:error, :scenario_not_found}, state}

        scenario ->
          case YamlElixir.read_from_file(scenario.path) do
            {:ok, config} ->
              room_id = Keyword.get(opts, :room_id)
              room_info = if room_id, do: " (room: #{room_id})", else: ""
              Logger.info("Starting scenario: #{scenario_name}#{room_info}")

              # Inject room_id and scenario_name into all connectors
              config =
                update_in(config, ["connectors"], fn connectors ->
                  Map.new(connectors || %{}, fn {id, connector} ->
                    connector = Map.put(connector, "scenario_name", scenario_name)

                    connector =
                      if room_id, do: Map.put(connector, "room_id", room_id), else: connector

                    {id, connector}
                  end)
                end)

              new_state = apply_scenario_config(state, scenario_name, room_id, config)

              # Async sync to PostgreSQL
              send(
                self(),
                {:sync_scenario_started, scenario_name, room_id, scenario.path,
                 config["connectors"] || %{}}
              )

              {:reply, :ok, new_state}

            {:error, reason} ->
              Logger.error("Failed to load scenario #{scenario_name}: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
      end
    end
  end

  @impl true
  def handle_call({:stop_scenario, scenario_name}, _from, state) do
    case Map.get(state.running_scenarios, scenario_name) do
      nil ->
        {:reply, {:error, :not_running}, state}

      scenario_info ->
        # Stop all connectors for this scenario
        Enum.each(scenario_info.connector_ids, &do_stop_connector/1)

        # Remove connectors from state
        new_connectors = Map.drop(state.connectors, scenario_info.connector_ids)
        new_running = Map.delete(state.running_scenarios, scenario_name)

        # Async sync to PostgreSQL
        send(self(), {:sync_scenario_stopped, scenario_name})

        Logger.info("Stopped scenario: #{scenario_name}")
        {:reply, :ok, %{state | connectors: new_connectors, running_scenarios: new_running}}
    end
  end

  @impl true
  def handle_call({:switch_scenario, scenario_name, opts}, _from, state) do
    # Find the scenario
    case Enum.find(state.available_scenarios, fn s -> s.name == scenario_name end) do
      nil ->
        {:reply, {:error, :scenario_not_found}, state}

      scenario ->
        # Stop all existing connectors and sync to PostgreSQL
        Enum.each(state.running_scenarios, fn {old_scenario_name, _info} ->
          send(self(), {:sync_scenario_stopped, old_scenario_name})
        end)

        Enum.each(state.connectors, fn {connector_id, _} ->
          do_stop_connector(connector_id)
        end)

        # Load the new scenario config
        case YamlElixir.read_from_file(scenario.path) do
          {:ok, config} ->
            room_id = Keyword.get(opts, :room_id)
            room_info = if room_id, do: " (room: #{room_id})", else: ""
            Logger.info("Switching to scenario: #{scenario_name}#{room_info}")

            # Inject room_id and scenario_name into all connectors
            config =
              update_in(config, ["connectors"], fn connectors ->
                Map.new(connectors || %{}, fn {id, connector} ->
                  connector = Map.put(connector, "scenario_name", scenario_name)

                  connector =
                    if room_id, do: Map.put(connector, "room_id", room_id), else: connector

                  {id, connector}
                end)
              end)

            new_state =
              apply_scenario_config(
                %{state | connectors: %{}, running_scenarios: %{}},
                scenario_name,
                room_id,
                config
              )

            # Async sync to PostgreSQL
            send(
              self(),
              {:sync_scenario_started, scenario_name, room_id, scenario.path,
               config["connectors"] || %{}}
            )

            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to load scenario #{scenario_name}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  # Handle async scenario discovery
  @impl true
  def handle_info(:discover_scenarios, state) do
    Logger.info("Discovering available simulator scenarios...")

    # Run filesystem I/O in a task to avoid blocking GenServer
    Task.Supervisor.start_child(
      Sensocto.Simulator.DbTaskSupervisor,
      fn ->
        scenarios = do_discover_scenarios()
        send(__MODULE__, {:scenarios_discovered, scenarios})
      end
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:scenarios_discovered, scenarios}, state) do
    Logger.info("Discovered #{length(scenarios)} available scenarios")
    {:noreply, %{state | available_scenarios: scenarios}}
  end

  @impl true
  def handle_info(:hydrate_from_postgres, state) do
    Logger.info("Hydrating simulator state from PostgreSQL...")

    # Run database query in a task to avoid blocking GenServer
    Task.Supervisor.start_child(
      Sensocto.Simulator.DbTaskSupervisor,
      fn ->
        result = load_running_scenarios_from_db()
        send(__MODULE__, {:hydration_result, result})
      end
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:hydration_result, {:ok, scenarios}}, state) when scenarios != [] do
    Logger.info("Found #{length(scenarios)} running scenarios to restore")
    new_state = restore_scenarios(state, scenarios)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hydration_result, {:ok, []}}, state) do
    Logger.debug("No running scenarios to restore from PostgreSQL")
    {:noreply, state}
  end

  @impl true
  def handle_info({:hydration_result, {:error, reason}}, state) do
    Logger.warning("Failed to hydrate from PostgreSQL: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:sync_scenario_started, scenario_name, room_id, config_path, connector_configs},
        state
      ) do
    Task.Supervisor.start_child(
      Sensocto.Simulator.DbTaskSupervisor,
      fn -> sync_scenario_to_postgres(scenario_name, room_id, config_path, connector_configs) end
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:sync_scenario_stopped, scenario_name}, state) do
    Task.Supervisor.start_child(
      Sensocto.Simulator.DbTaskSupervisor,
      fn -> stop_scenario_in_postgres(scenario_name) end
    )

    {:noreply, state}
  end

  # Private Functions

  defp load_config(%__MODULE__{config_path: path} = state) do
    # Try absolute path first, then relative to priv
    full_path =
      cond do
        File.exists?(path) ->
          path

        File.exists?(Path.join(:code.priv_dir(:sensocto), path)) ->
          Path.join(:code.priv_dir(:sensocto), path)

        File.exists?(Path.join(File.cwd!(), path)) ->
          Path.join(File.cwd!(), path)

        true ->
          path
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
      Enum.reduce(new_connectors_config, %{state | connectors: %{}}, fn {connector_id,
                                                                         connector_config},
                                                                        acc ->
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
      {sensor_id,
       %{
         name: sensor_config["sensor_name"] || sensor_id,
         attributes: sensor_config["attributes"] || %{}
       }}
    end)
  end

  defp get_room_name(nil), do: nil

  defp get_room_name(room_id) do
    case Sensocto.RoomStore.get_room(room_id) do
      {:ok, room} -> room.name
      _ -> nil
    end
  end

  defp apply_scenario_config(state, scenario_name, room_id, config) do
    new_connectors_config = config["connectors"] || %{}
    connector_ids = Map.keys(new_connectors_config)

    # Always auto-start connectors when a scenario is explicitly started
    # The global autostart setting only applies to initial config load (simulators.yaml),
    # not to explicit scenario starts via the UI
    new_state =
      Enum.reduce(new_connectors_config, state, fn {connector_id, connector_config}, acc ->
        connector_config = Map.put(connector_config, "connector_id", connector_id)
        start_or_update_connector(acc, connector_id, connector_config)
      end)

    # Track the running scenario
    scenario_info = %{
      room_id: room_id,
      room_name: get_room_name(room_id),
      connector_ids: connector_ids
    }

    %{
      new_state
      | running_scenarios: Map.put(new_state.running_scenarios, scenario_name, scenario_info)
    }
  end

  defp do_discover_scenarios do
    # Try multiple paths for scenarios directory (release vs dev)
    scenarios_path = find_scenarios_dir()

    if scenarios_path && File.exists?(scenarios_path) do
      scenarios_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yaml"))
      |> Enum.map(fn filename ->
        name = String.replace_suffix(filename, ".yaml", "")
        path = Path.join(scenarios_path, filename)

        # Read the file to get description and count sensors/attributes
        stats = get_scenario_stats(path)

        %{
          name: name,
          path: path,
          description: stats.description,
          sensor_count: stats.sensor_count,
          attribute_count: stats.attribute_count
        }
      end)
      |> Enum.sort_by(& &1.attribute_count)
    else
      Logger.warning("Scenarios directory not found: #{inspect(scenarios_path)}")
      []
    end
  end

  defp find_scenarios_dir do
    # Check multiple possible locations for scenarios directory
    possible_paths = [
      # Release: /app/config/simulator_scenarios
      Path.join(Application.app_dir(:sensocto), "../config/simulator_scenarios"),
      # Release alternative: relative to release root
      "/app/config/simulator_scenarios",
      # Development: config/simulator_scenarios relative to cwd
      Path.join(File.cwd!(), @scenarios_dir)
    ]

    Enum.find(possible_paths, fn path ->
      expanded = Path.expand(path)
      File.exists?(expanded) && File.dir?(expanded)
    end)
    |> case do
      nil -> nil
      path -> Path.expand(path)
    end
  end

  defp get_scenario_stats(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, config} ->
        connectors = config["connectors"] || %{}

        {sensor_count, attribute_count} =
          Enum.reduce(connectors, {0, 0}, fn {_id, connector}, {sensors, attrs} ->
            sensors_config = connector["sensors"] || %{}
            sensor_count = map_size(sensors_config)

            attr_count =
              Enum.reduce(sensors_config, 0, fn {_sid, sensor}, acc ->
                acc + map_size(sensor["attributes"] || %{})
              end)

            {sensors + sensor_count, attrs + attr_count}
          end)

        # Extract description from first line comment if available
        description =
          case File.read(path) do
            {:ok, content} ->
              content
              |> String.split("\n")
              |> Enum.find("", &String.starts_with?(&1, "#"))
              |> String.replace_prefix("# ", "")
              |> String.trim()

            _ ->
              ""
          end

        %{
          description: description,
          sensor_count: sensor_count,
          attribute_count: attribute_count
        }

      {:error, _} ->
        %{description: "", sensor_count: 0, attribute_count: 0}
    end
  end

  # PostgreSQL Persistence Functions

  defp load_running_scenarios_from_db do
    try do
      scenarios =
        SimulatorScenario
        |> Ash.Query.for_read(:running)
        |> Ash.read!()
        |> Ash.load!(:connectors)

      {:ok, scenarios}
    rescue
      e ->
        {:error, e}
    end
  end

  defp restore_scenarios(state, scenarios) do
    Enum.reduce(scenarios, state, fn scenario, acc ->
      Logger.info("Restoring scenario: #{scenario.name}")

      # Find matching available scenario to get the path
      available = Enum.find(acc.available_scenarios, fn s -> s.name == scenario.name end)

      if available do
        case YamlElixir.read_from_file(available.path) do
          {:ok, config} ->
            room_id = scenario.room_id

            # Inject room_id and scenario_name into all connectors
            config =
              update_in(config, ["connectors"], fn connectors ->
                Map.new(connectors || %{}, fn {id, connector} ->
                  connector = Map.put(connector, "scenario_name", scenario.name)

                  connector =
                    if room_id, do: Map.put(connector, "room_id", room_id), else: connector

                  {id, connector}
                end)
              end)

            apply_scenario_config(acc, scenario.name, room_id, config)

          {:error, reason} ->
            Logger.error("Failed to restore scenario #{scenario.name}: #{inspect(reason)}")
            acc
        end
      else
        Logger.warning(
          "Scenario #{scenario.name} not found in available scenarios, marking as stopped"
        )

        stop_scenario_in_postgres(scenario.name)
        acc
      end
    end)
  end

  defp sync_scenario_to_postgres(scenario_name, room_id, config_path, connector_configs) do
    room_name = get_room_name(room_id)

    # Debounce to avoid rapid writes
    Process.sleep(@sync_debounce_ms)

    try do
      # Check if scenario already exists
      case SimulatorScenario
           |> Ash.Query.for_read(:by_name, %{name: scenario_name})
           |> Ash.read_one() do
        {:ok, nil} ->
          # Create new scenario
          {:ok, scenario} =
            SimulatorScenario
            |> Ash.Changeset.for_create(:start, %{
              name: scenario_name,
              room_id: room_id,
              room_name: room_name,
              config_path: config_path
            })
            |> Ash.create()

          # Create connector records
          sync_connectors_to_postgres(scenario.id, connector_configs)
          Logger.debug("Synced new scenario #{scenario_name} to PostgreSQL")

        {:ok, existing} ->
          # Update existing scenario to running
          {:ok, _} =
            existing
            |> Ash.Changeset.for_update(:start, %{
              room_id: room_id,
              room_name: room_name
            })
            |> Ash.update()

          # Sync connectors
          sync_connectors_to_postgres(existing.id, connector_configs)
          Logger.debug("Updated scenario #{scenario_name} in PostgreSQL")

        {:error, reason} ->
          Logger.warning("Failed to sync scenario #{scenario_name}: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.warning("Exception syncing scenario to PostgreSQL: #{inspect(e)}")
    end
  end

  defp sync_connectors_to_postgres(scenario_id, connector_configs) do
    Enum.each(connector_configs, fn {connector_id, config} ->
      connector_name = config["connector_name"] || connector_id
      room_id = config["room_id"]
      sensors_config = config["sensors"] || %{}

      # Check if connector already exists
      case SimulatorConnector
           |> Ash.Query.for_read(:by_connector_id, %{connector_id: connector_id})
           |> Ash.read_one() do
        {:ok, nil} ->
          # Create new connector
          SimulatorConnector
          |> Ash.Changeset.for_create(:create, %{
            connector_id: connector_id,
            connector_name: connector_name,
            room_id: room_id,
            sensors_config: sensors_config,
            scenario_id: scenario_id
          })
          |> Ash.create()

        {:ok, _existing} ->
          # Connector exists, skip update for now
          :ok

        {:error, _} ->
          :ok
      end
    end)
  end

  defp stop_scenario_in_postgres(scenario_name) do
    try do
      case SimulatorScenario
           |> Ash.Query.for_read(:by_name, %{name: scenario_name})
           |> Ash.read_one() do
        {:ok, nil} ->
          Logger.debug("Scenario #{scenario_name} not found in PostgreSQL")

        {:ok, scenario} ->
          {:ok, _} =
            scenario
            |> Ash.Changeset.for_update(:stop, %{})
            |> Ash.update()

          Logger.debug("Marked scenario #{scenario_name} as stopped in PostgreSQL")

        {:error, reason} ->
          Logger.warning(
            "Failed to stop scenario #{scenario_name} in PostgreSQL: #{inspect(reason)}"
          )
      end
    rescue
      e ->
        Logger.warning("Exception stopping scenario in PostgreSQL: #{inspect(e)}")
    end
  end
end
