defmodule Sensocto.EcoMonitor.HydroSupervisor do
  @moduledoc """
  Supervisor for HydroPoller processes.

  Reads all YAML configuration files from config/eco_monitor/ (or the path configured
  via `Application.get_env(:sensocto, :eco_monitor, config_dir: "config/eco_monitor")`),
  and starts one HydroPoller per file with `source: existenz_hydro`.

  Adding a new river: drop a new .yml file in config/eco_monitor/ and restart.
  """

  use Supervisor
  require Logger

  @default_config_dir "config/eco_monitor"

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    configs = load_hydro_configs()
    Logger.info("EcoMonitor.HydroSupervisor: starting #{length(configs)} poller(s)")

    children =
      Enum.map(configs, fn {name, config} ->
        Supervisor.child_spec(
          {Sensocto.EcoMonitor.HydroPoller, {name, config}},
          id: {:hydro_poller, name}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp load_hydro_configs do
    config_dir =
      :sensocto
      |> Application.get_env(:eco_monitor, [])
      |> Keyword.get(:config_dir, @default_config_dir)

    case File.ls(config_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".yml"))
        |> Enum.flat_map(fn file ->
          path = Path.join(config_dir, file)

          case YamlElixir.read_from_file(path) do
            {:ok, %{"source" => "existenz_hydro", "name" => name} = config} ->
              [{String.to_atom(name), config}]

            {:ok, _other} ->
              []

            {:error, reason} ->
              Logger.warning("EcoMonitor: failed to parse #{path}: #{inspect(reason)}")
              []
          end
        end)

      {:error, reason} ->
        Logger.warning(
          "EcoMonitor: config dir '#{config_dir}' not accessible: #{inspect(reason)}"
        )

        []
    end
  end
end
