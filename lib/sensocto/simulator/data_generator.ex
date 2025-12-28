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
    sampling_rate = max(config[:sampling_rate] || 1, 0.01)
    batch_size = config[:batch_size] || 10
    sensor_type = config[:sensor_type] || "generic"

    # For duration 0 (continuous), generate batch_size samples
    num_samples = if duration == 0, do: batch_size, else: max(1, trunc(duration * sampling_rate))

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    # Generate CSV-like output
    header = "timestamp,delay,payload"

    data_lines =
      Enum.map(0..(num_samples - 1), fn i ->
        timestamp = now + i * interval_ms
        delay = if i == 0, do: 0.0, else: 1.0 / sampling_rate
        value = generate_value(sensor_type, config, i, sampling_rate)
        "#{timestamp},#{delay},#{Float.round(value, 2)}"
      end)

    [header | data_lines] |> Enum.join("\n")
  end

  # Generate ECG-like waveform
  defp generate_value("ecg", config, i, sampling_rate) do
    heart_rate = config[:heart_rate] || 72
    # Samples per beat at current sampling rate
    samples_per_beat = sampling_rate * 60 / heart_rate
    # Position within the current beat cycle (0 to 1)
    phase = rem(i, trunc(samples_per_beat)) / samples_per_beat

    # Generate PQRST complex
    ecg_value = generate_ecg_waveform(phase)
    # Add small noise
    noise = (:rand.uniform() - 0.5) * 0.05
    ecg_value + noise
  end

  # Generate heartrate with slow drift
  defp generate_value("heartrate", config, i, _sampling_rate) do
    base = config[:heart_rate] || 75
    # Slow breathing-related variation
    breathing_effect = :math.sin(i * 0.05) * 3
    # Random walk component
    noise = (:rand.uniform() - 0.5) * 2
    base + breathing_effect + noise
  end

  # Generic sensor with min/max range
  defp generate_value(_sensor_type, config, i, _sampling_rate) do
    {base_value, variation_range} =
      case {config[:min_value], config[:max_value]} do
        {min, max} when is_number(min) and is_number(max) ->
          mid = (min + max) / 2
          range = (max - min) / 2
          {mid, range}
        _ ->
          {config[:heart_rate] || 75, 5}
      end

    variation = :rand.uniform() * variation_range * 2 - variation_range
    base_value + variation + :math.sin(i * 0.1) * (variation_range * 0.3)
  end

  # Simplified ECG PQRST waveform generator
  defp generate_ecg_waveform(phase) do
    cond do
      # P wave (atrial depolarization) - small bump
      phase >= 0.0 and phase < 0.1 ->
        p_phase = (phase - 0.0) / 0.1
        0.15 * :math.sin(p_phase * :math.pi())

      # PR segment (flat)
      phase >= 0.1 and phase < 0.15 ->
        0.0

      # Q wave (small negative dip)
      phase >= 0.15 and phase < 0.18 ->
        q_phase = (phase - 0.15) / 0.03
        -0.1 * :math.sin(q_phase * :math.pi())

      # R wave (tall positive spike)
      phase >= 0.18 and phase < 0.22 ->
        r_phase = (phase - 0.18) / 0.04
        1.0 * :math.sin(r_phase * :math.pi())

      # S wave (negative dip after R)
      phase >= 0.22 and phase < 0.26 ->
        s_phase = (phase - 0.22) / 0.04
        -0.25 * :math.sin(s_phase * :math.pi())

      # ST segment (slightly elevated)
      phase >= 0.26 and phase < 0.35 ->
        0.02

      # T wave (repolarization)
      phase >= 0.35 and phase < 0.50 ->
        t_phase = (phase - 0.35) / 0.15
        0.3 * :math.sin(t_phase * :math.pi())

      # Baseline
      true ->
        0.0
    end
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
