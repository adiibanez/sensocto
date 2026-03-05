defmodule Sensocto.EcoMonitor.HydroPoller do
  @moduledoc """
  GenServer that polls the existenz.ch hydrology API for river monitoring data
  and feeds it into SimpleSensor processes.

  Each poller instance manages one river configuration (e.g., Reuss). On startup it:
    1. Creates one SimpleSensor per station via SensorsDynamicSupervisor
    2. Polls GET /hydro/latest every poll_interval (default 5 minutes)
    3. Dispatches each {loc, par, val} measurement to the corresponding sensor
    4. Backs off exponentially on API errors; resets on success

  Data flows:
    existenz.ch → HydroPoller → SimpleSensor.put_batch_attributes → PubSub → LiveView

  Attribution: Data sourced from Swiss Federal Office for the Environment (FOEN/BAFU).
  """

  use GenServer
  require Logger

  alias Sensocto.SensorsDynamicSupervisor

  @default_api_base "https://api.existenz.ch/apiv1/hydro"
  @http_timeout_ms 15_000
  @max_backoff_ms 600_000
  @backoff_multiplier 1.5

  def start_link({name, config}) do
    GenServer.start_link(__MODULE__, {name, config},
      name: {:via, Registry, {Sensocto.EcoMonitor.Registry, {__MODULE__, name}}}
    )
  end

  @impl true
  def init({name, config}) do
    poll_interval = (config["poll_interval_seconds"] || 300) * 1_000

    state = %{
      name: name,
      api_base: config["api_base"] || @default_api_base,
      app_id: config["app_identifier"] || "sensocto",
      poll_interval: poll_interval,
      stations_config: config["stations"] || [],
      # station_id (string) => sensor_id (string)
      stations: %{},
      # station_id (string) => [parameter strings]
      parameters_by_station: %{},
      backoff_failures: 0,
      last_poll: nil
    }

    {:ok, state, {:continue, :start_sensors}}
  end

  @impl true
  def handle_continue(:start_sensors, state) do
    {stations, parameters_by_station} =
      setup_sensors(state.name, state.stations_config)

    send(self(), :poll)

    {:noreply, %{state | stations: stations, parameters_by_station: parameters_by_station}}
  end

  @impl true
  def handle_info(:poll, state) do
    {:noreply, do_poll(state)}
  end

  # Private

  defp setup_sensors(river_name, stations_config) do
    Enum.reduce(stations_config, {%{}, %{}}, fn station, {stations_acc, params_acc} ->
      station_id = station["id"]
      station_name = station["name"]
      parameters = station["parameters"] || []

      sensor_id = build_sensor_id(river_name, station_id, station_name)

      sensor_config = %{
        sensor_id: sensor_id,
        sensor_name: station_name,
        sensor_type: "hydro",
        connector_id: "eco_monitor_#{river_name}",
        connector_name: "#{river_name} River Monitoring",
        sampling_rate: 1,
        batch_size: 1,
        attributes: %{}
      }

      case SensorsDynamicSupervisor.add_sensor(sensor_id, sensor_config) do
        {:ok, _} ->
          Logger.info("EcoMonitor #{river_name}: started sensor #{sensor_id}")

          {
            Map.put(stations_acc, station_id, sensor_id),
            Map.put(params_acc, station_id, parameters)
          }

        {:error, reason} ->
          Logger.error(
            "EcoMonitor #{river_name}: failed to start sensor #{sensor_id}: #{inspect(reason)}"
          )

          {stations_acc, Map.put(params_acc, station_id, parameters)}
      end
    end)
  end

  defp do_poll(%{stations_config: [], name: name} = state) do
    Logger.warning("EcoMonitor #{name}: no stations configured, skipping poll")
    state
  end

  defp do_poll(state) do
    locations =
      state.stations_config
      |> Enum.map(& &1["id"])
      |> Enum.join(",")

    parameters =
      state.parameters_by_station
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.join(",")

    url = "#{state.api_base}/latest"

    query_params = [
      locations: locations,
      parameters: parameters,
      app: state.app_id
    ]

    Logger.debug("EcoMonitor #{state.name}: polling #{url}")

    case Req.get(url, params: query_params, receive_timeout: @http_timeout_ms) do
      {:ok, %{status: 200, body: %{"payload" => payload}}} when is_list(payload) ->
        push_measurements(state, payload)
        schedule_poll(state.poll_interval)
        %{state | backoff_failures: 0, last_poll: DateTime.utc_now()}

      {:ok, %{status: 200, body: body}} ->
        Logger.warning("EcoMonitor #{state.name}: unexpected response body: #{inspect(body)}")

        schedule_poll(state.poll_interval)
        %{state | backoff_failures: 0, last_poll: DateTime.utc_now()}

      {:ok, %{status: status}} ->
        Logger.warning("EcoMonitor #{state.name}: API returned HTTP #{status}")
        apply_backoff(state)

      {:error, reason} ->
        Logger.warning("EcoMonitor #{state.name}: HTTP error: #{inspect(reason)}")
        apply_backoff(state)
    end
  end

  defp push_measurements(state, payload) do
    by_station = Enum.group_by(payload, & &1["loc"])

    Enum.each(by_station, fn {station_id, measurements} ->
      case Map.get(state.stations, station_id) do
        nil ->
          Logger.debug("EcoMonitor: received data for unknown station #{station_id}, skipping")

        sensor_id ->
          attributes =
            Enum.map(measurements, fn %{"par" => par, "val" => val, "timestamp" => ts} ->
              %{
                attribute_id: par,
                payload: val,
                # API provides Unix seconds, SimpleSensor expects milliseconds
                timestamp: ts * 1_000
              }
            end)

          Sensocto.SimpleSensor.put_batch_attributes(sensor_id, attributes)
      end
    end)
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  defp apply_backoff(%{backoff_failures: failures, poll_interval: base_interval} = state) do
    interval =
      base_interval
      |> Kernel.*(:math.pow(@backoff_multiplier, failures))
      |> round()
      |> min(@max_backoff_ms)

    Logger.info(
      "EcoMonitor #{state.name}: next poll in #{div(interval, 1_000)}s (failure ##{failures + 1})"
    )

    schedule_poll(interval)
    %{state | backoff_failures: failures + 1}
  end

  defp build_sensor_id(river_name, station_id, station_name) do
    slug = station_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
    "#{river_name}-#{station_id}-#{slug}"
  end
end
