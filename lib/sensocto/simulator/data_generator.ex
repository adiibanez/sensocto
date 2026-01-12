defmodule Sensocto.Simulator.DataGenerator do
  @moduledoc """
  Generates simulated sensor data.
  Supports Python script integration for complex waveforms and fake data fallback.

  For GPS/geolocation data, supports track-based simulation via TrackPlayer
  for realistic movement patterns (walking, cycling, driving, bird migration, etc.)
  """

  alias NimbleCSV.RFC4180, as: CSV
  alias Sensocto.Simulator.TrackPlayer
  require Logger

  @doc """
  Fetch sensor data based on configuration.
  Returns `{:ok, data}` or `{:error, reason}`.
  """
  def fetch_sensor_data(config) do
    try do
      sensor_type = config[:sensor_type] || "generic"

      # Battery uses special handling for structured payload
      # Geolocation uses track-based playback for realistic movement
      cond do
        sensor_type == "battery" ->
          {:ok, fetch_battery_data(config)}

        sensor_type == "geolocation" ->
          {:ok, fetch_geolocation_data(config)}

        true ->
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
      end
    rescue
      e ->
        Logger.error("Error fetching sensor data: #{inspect(e)}")
        {:ok, parse_csv_output(fetch_fake_sensor_data(config))}
    end
  end

  # Special handler for battery data that includes charging status in payload
  defp fetch_battery_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 0.1, 0.01)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    Enum.map(0..(batch_size - 1), fn i ->
      battery_data = Sensocto.Simulator.BatteryState.get_battery_data(sensor_id, config)
      timestamp = now + i * interval_ms
      # For batch_size 1, we still need the sampling_rate delay since each fetch is one sample
      delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

      %{
        timestamp: timestamp,
        delay: delay,
        payload: %{
          level: battery_data.level,
          charging: battery_data.charging
        }
      }
    end)
  end

  # Special handler for geolocation data using track-based playback
  defp fetch_geolocation_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 0.1, 0.01)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    # Ensure track playback is started for this sensor
    ensure_track_started(sensor_id, config)

    Enum.map(0..(batch_size - 1), fn i ->
      timestamp = now + i * interval_ms
      delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

      # Get position from track player (advances playback time)
      position = get_track_position(sensor_id)

      %{
        timestamp: timestamp,
        delay: delay,
        payload: position
      }
    end)
  end

  # Start track playback for a sensor if not already playing
  defp ensure_track_started(sensor_id, config) do
    case TrackPlayer.get_status(sensor_id) do
      {:ok, _status} ->
        # Already playing
        :ok

      {:error, :not_playing} ->
        # Start playback with configured or random track
        track_opts = build_track_opts(config)
        TrackPlayer.start_playback(sensor_id, track_opts)
    end
  end

  defp build_track_opts(config) do
    opts = []

    # Track selection priority: track_name > mode > random
    opts =
      cond do
        track_name = config[:track_name] ->
          [{:track_name, track_name} | opts]

        mode = config[:track_mode] ->
          mode_atom = if is_binary(mode), do: String.to_existing_atom(mode), else: mode
          [{:mode, mode_atom} | opts]

        config[:generate_track] ->
          mode = config[:track_mode] || :walk
          mode_atom = if is_binary(mode), do: String.to_existing_atom(mode), else: mode
          [{:generate, true}, {:mode, mode_atom} | opts]

        true ->
          # Random track
          opts
      end

    # Playback options
    opts = if speed = config[:playback_speed], do: [{:playback_speed, speed} | opts], else: opts
    opts = if config[:no_loop], do: [{:loop, false} | opts], else: [{:loop, true} | opts]
    opts = if config[:random_start], do: [{:random_start, true} | opts], else: opts

    # Generated track options
    opts = if lat = config[:start_lat], do: [{:start_lat, lat} | opts], else: opts
    opts = if lng = config[:start_lng], do: [{:start_lng, lng} | opts], else: opts
    opts = if dur = config[:track_duration], do: [{:duration_minutes, dur} | opts], else: opts

    opts
  end

  defp get_track_position(sensor_id) do
    case TrackPlayer.tick(sensor_id) do
      {:ok, position} ->
        position

      {:error, :not_playing} ->
        # Fallback to static position if track player not available
        %{
          latitude: 52.52,
          longitude: 13.405,
          altitude: 35.0,
          speed: 0.0,
          heading: 0.0,
          accuracy: 10.0
        }
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
        # For batch_size 1, we still need the sampling_rate delay since each fetch is one sample
        # Only skip delay for the first sample in multi-sample batches
        delay = if i == 0 and num_samples > 1, do: 0.0, else: 1.0 / sampling_rate
        value = generate_value(sensor_type, config, i, sampling_rate)
        "#{timestamp},#{delay},#{Float.round(value * 1.0, 2)}"
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

  # GPS/Geolocation - slowly drifting position (walking simulation)
  defp generate_value("geolocation_lat", config, i, _sampling_rate) do
    base_lat = config[:base_lat] || 52.52
    # Slow random walk for walking movement (~5m per step)
    drift = :math.sin(i * 0.02) * 0.0001 + (:rand.uniform() - 0.5) * 0.00005
    base_lat + drift + i * 0.000001
  end

  defp generate_value("geolocation_lng", config, i, _sampling_rate) do
    base_lng = config[:base_lng] || 13.405
    # Slow random walk for walking movement
    drift = :math.cos(i * 0.02) * 0.0001 + (:rand.uniform() - 0.5) * 0.00005
    base_lng + drift + i * 0.000001
  end

  defp generate_value("geolocation_alt", config, i, _sampling_rate) do
    base_alt = config[:base_alt] || 35.0
    # Small altitude variations (walking up/down slopes)
    variation = :math.sin(i * 0.05) * 2 + (:rand.uniform() - 0.5) * 0.5
    base_alt + variation
  end

  # Accelerometer - motion detection (m/s²)
  defp generate_value("accelerometer_x", _config, i, _sampling_rate) do
    # Walking motion with periodic steps
    step_cycle = :math.sin(i * 0.5) * 2.0
    noise = (:rand.uniform() - 0.5) * 0.5
    step_cycle + noise
  end

  defp generate_value("accelerometer_y", _config, i, _sampling_rate) do
    # Lateral sway while walking
    sway = :math.sin(i * 0.25) * 1.0
    noise = (:rand.uniform() - 0.5) * 0.3
    sway + noise
  end

  defp generate_value("accelerometer_z", _config, i, _sampling_rate) do
    # Gravity + vertical bounce while walking
    gravity = 9.81
    bounce = :math.sin(i * 0.5) * 0.5
    noise = (:rand.uniform() - 0.5) * 0.2
    gravity + bounce + noise
  end

  # Gyroscope - rotation rates (rad/s)
  defp generate_value("gyroscope_x", _config, i, _sampling_rate) do
    # Pitch rotation (nodding)
    rotation = :math.sin(i * 0.3) * 0.2
    noise = (:rand.uniform() - 0.5) * 0.1
    rotation + noise
  end

  defp generate_value("gyroscope_y", _config, i, _sampling_rate) do
    # Roll rotation (side-to-side tilt)
    rotation = :math.sin(i * 0.4) * 0.15
    noise = (:rand.uniform() - 0.5) * 0.08
    rotation + noise
  end

  defp generate_value("gyroscope_z", _config, i, _sampling_rate) do
    # Yaw rotation (turning)
    rotation = :math.sin(i * 0.1) * 0.3
    noise = (:rand.uniform() - 0.5) * 0.1
    rotation + noise
  end

  # Light sensor (lux)
  defp generate_value("light", config, i, _sampling_rate) do
    base = config[:base_lux] || 500
    # Slow variation (clouds passing, moving indoors/outdoors)
    variation = :math.sin(i * 0.02) * 200
    noise = (:rand.uniform() - 0.5) * 50
    max(0, base + variation + noise)
  end

  # Sound level (dB)
  defp generate_value("sound_level", config, i, _sampling_rate) do
    base = config[:base_db] || 45
    # Occasional spikes (conversations, vehicles)
    spike = if :rand.uniform() < 0.05, do: :rand.uniform() * 30, else: 0
    variation = :math.sin(i * 0.1) * 5
    noise = (:rand.uniform() - 0.5) * 3
    max(20, base + variation + noise + spike)
  end

  # Battery level (percentage) - uses stateful BatteryState for realistic simulation
  defp generate_value("battery", config, _i, _sampling_rate) do
    sensor_id = config[:sensor_id] || "unknown"

    # Get battery data from stateful manager (includes charging state)
    battery_data = Sensocto.Simulator.BatteryState.get_battery_data(sensor_id, config)

    # Return just the level - charging status is handled separately
    battery_data.level * 1.0
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
