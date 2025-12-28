defmodule Sensocto.Simulator.DataGenerator do
  @moduledoc """
  Generates simulated sensor data.
  Supports Python script integration for complex waveforms and fake data fallback.
  """

  alias NimbleCSV.RFC4180, as: CSV
  require Logger

  @doc """
  Fetch sensor data based on configuration.
  Returns `{:ok, data}` or `{:error, reason}`.
  """
  def fetch_sensor_data(config) do
    try do
      result =
        case config[:dummy_data] do
          true -> {:ok, fetch_fake_sensor_data(config)}
          _ -> fetch_python_data(config)
        end

      case result do
        {:ok, csv_output} ->
          data = parse_csv_output(csv_output)
          {:ok, data}

        {:error, reason} ->
          Logger.warning("Python data fetch failed, using fake data: #{inspect(reason)}")
          {:ok, parse_csv_output(fetch_fake_sensor_data(config))}
      end
    rescue
      e ->
        Logger.error("Error fetching sensor data: #{inspect(e)}")
        {:ok, parse_csv_output(fetch_fake_sensor_data(config))}
    end
  end

  defp fetch_python_data(config) do
    # Path to Python script - check multiple locations
    script_paths = [
      Path.join(File.cwd!(), "simulator/sensocto-simulator.py"),
      Path.join(File.cwd!(), "simulator/sensocto_elixir_simulator/sensocto-simulator.py"),
      Path.join(:code.priv_dir(:sensocto), "simulator/sensocto-simulator.py")
    ]

    script_path = Enum.find(script_paths, &File.exists?/1)

    if script_path do
      args = [
        script_path,
        "--mode", "csv",
        "--sensor_id", "#{config[:sensor_id] || "sim"}",
        "--sensor_type", "#{config[:sensor_type] || "heartrate"}",
        "--duration", "#{config[:duration] || 30}",
        "--sampling_rate", "#{config[:sampling_rate] || 1}",
        "--heart_rate", "#{config[:heart_rate] || 75}",
        "--respiratory_rate", "#{config[:respiratory_rate] || 15}",
        "--scr_number", "#{config[:scr_number] || 5}",
        "--burst_number", "#{config[:burst_number] || 5}"
      ]

      case System.cmd("python3", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, code} -> {:error, "Python exited with code #{code}: #{output}"}
      end
    else
      Logger.warning("Python script not found, using fake data")
      {:error, :script_not_found}
    end
  end

  defp fetch_fake_sensor_data(config) do
    duration = config[:duration] || 30
    sampling_rate = config[:sampling_rate] || 1
    num_samples = duration * sampling_rate

    # Generate fake heartrate-like data
    base_value = config[:heart_rate] || 75
    now = :os.system_time(:millisecond)

    # Generate CSV-like output
    header = "timestamp,delay,payload"

    data_lines =
      Enum.map(0..(num_samples - 1), fn i ->
        timestamp = now + i * round(1000 / sampling_rate)
        delay = if i == 0, do: 0.0, else: 1.0 / sampling_rate
        # Add some variation to make it look realistic
        variation = :rand.uniform() * 10 - 5
        value = base_value + variation + :math.sin(i * 0.1) * 5
        "#{timestamp},#{delay},#{Float.round(value, 1)}"
      end)

    [header | data_lines] |> Enum.join("\n")
  end

  defp parse_csv_output(csv_string) do
    csv_string
    |> String.trim()
    |> CSV.parse_string(skip_headers: true)
    |> Enum.map(fn [timestamp_str, delay_str, payload_str] ->
      %{
        timestamp: parse_integer(timestamp_str),
        delay: parse_float(delay_str),
        payload: parse_float(payload_str)
      }
    end)
  end

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
