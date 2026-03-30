defmodule Sensocto.Simulator.DataGenerator do
  @moduledoc """
  Generates simulated sensor data.
  Supports Python script integration for complex waveforms and fake data fallback.

  For GPS/geolocation data, supports track-based simulation via TrackPlayer
  for realistic movement patterns (walking, cycling, driving, bird migration, etc.)
  """

  alias NimbleCSV.RFC4180, as: CSV
  alias Sensocto.Simulator.TrackPlayer
  alias Sensocto.Simulator.MotionKeyframes
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
      # Skeleton uses motion capture style animation
      cond do
        sensor_type == "battery" ->
          {:ok, fetch_battery_data(config)}

        sensor_type == "geolocation" ->
          {:ok, fetch_geolocation_data(config)}

        sensor_type in ["skeleton", "pose", "pose_skeleton"] ->
          {:ok, fetch_skeleton_data(config)}

        sensor_type == "respiration" ->
          {:ok, fetch_respiration_data(config)}

        sensor_type == "hrv" ->
          {:ok, fetch_hrv_data(config)}

        sensor_type == "eye_gaze" ->
          {:ok, fetch_eye_gaze_data(config)}

        sensor_type == "eye_aperture" ->
          {:ok, fetch_eye_aperture_data(config)}

        sensor_type == "hydro_api" ->
          {:ok, fetch_hydro_api_data(config)}

        sensor_type in ["imu", "accelerometer", "gyroscope", "motion"] ->
          {:ok, fetch_imu_data(config)}

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

  # Special handler for IMU data that generates structured map payloads
  # with accelerometer and gyroscope sub-maps instead of CSV strings.
  defp fetch_imu_data(config) do
    batch_size = config[:batch_size] || 5
    sampling_rate = max(config[:sampling_rate] || 110, 0.01)
    activity = config[:activity_level] || 0.5
    delay = if sampling_rate > 0, do: 1.0 / sampling_rate, else: 0.1

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    # sample_offset keeps waveform phase continuous across batch boundaries
    sample_offset = config[:sample_offset] || 0

    Enum.map(0..(batch_size - 1), fn i ->
      idx = i + sample_offset

      %{
        timestamp: now + i * interval_ms,
        delay: if(i == 0 and batch_size > 1, do: 0.0, else: delay),
        payload: %{
          accelerometer: %{
            x: generate_imu_accel_x(activity, idx),
            y: generate_imu_accel_y(activity, idx),
            z: generate_imu_accel_z(activity, idx)
          },
          gyroscope: %{
            x: generate_imu_gyro_x(activity, idx),
            y: generate_imu_gyro_y(activity, idx),
            z: generate_imu_gyro_z(activity, idx)
          }
        }
      }
    end)
  end

  defp generate_imu_accel_x(activity, i) do
    a = activity * 12.0
    step = :math.sin(i * 0.5) * a * 0.5
    swing = :math.sin(i * 0.17 + 1.2) * a * 0.3
    burst = if rem(trunc(i), 200) < 20, do: :math.sin(i * 1.5) * a * 0.8, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.2
    Float.round(step + swing + burst + noise, 4)
  end

  defp generate_imu_accel_y(activity, i) do
    a = activity * 10.0
    sway = :math.sin(i * 0.25 + 0.7) * a * 0.4
    drift = :math.sin(i * 0.03) * a * 0.6
    jolt = if rem(trunc(i), 300) < 10, do: (:rand.uniform() - 0.5) * a * 1.5, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    Float.round(sway + drift + jolt + noise, 4)
  end

  defp generate_imu_accel_z(activity, i) do
    a = activity * 8.0
    gravity = 9.81
    bounce = :math.sin(i * 0.5 + 2.1) * a * 0.4
    breathing = :math.sin(i * 0.08) * a * 0.2
    noise = (:rand.uniform() - 0.5) * a * 0.15
    Float.round(gravity + bounce + breathing + noise, 4)
  end

  defp generate_imu_gyro_x(activity, i) do
    a = activity * 6.0
    nod = :math.sin(i * 0.15 + 0.5) * a * 0.5
    micro = :math.sin(i * 0.8) * a * 0.2
    head_turn = if rem(trunc(i), 250) < 30, do: :math.sin(i * 0.6) * a * 0.8, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    Float.round(nod + micro + head_turn + noise, 4)
  end

  defp generate_imu_gyro_y(activity, i) do
    a = activity * 5.0
    roll = :math.sin(i * 0.2 + 1.8) * a * 0.4
    wobble = :math.sin(i * 0.55 + 3.0) * a * 0.3
    noise = (:rand.uniform() - 0.5) * a * 0.12
    Float.round(roll + wobble + noise, 4)
  end

  defp generate_imu_gyro_z(activity, i) do
    a = activity * 8.0
    scan = :math.sin(i * 0.06) * a * 0.5
    turn = if rem(trunc(i), 180) < 25, do: :math.sin(i * 0.4 + 0.3) * a * 1.0, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    Float.round(scan + turn + noise, 4)
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

  # Special handler for skeleton/pose data with motion capture style animation
  defp fetch_skeleton_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 10, 0.1)

    # Convert motion_type from string to atom if needed
    # Valid motion types: idle, walking, waving, jumping, dancing, exercise
    motion_type =
      case config[:motion_type] || config["motion_type"] do
        nil -> :idle
        type when is_atom(type) -> type
        "idle" -> :idle
        "walking" -> :walking
        "waving" -> :waving
        "jumping" -> :jumping
        "dancing" -> :dancing
        "exercise" -> :exercise
        _ -> :idle
      end

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    # Get or initialize skeleton state for this sensor
    skeleton_state = get_skeleton_state(sensor_id, motion_type)

    Enum.map(0..(batch_size - 1), fn i ->
      timestamp = now + i * interval_ms
      delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

      # Generate skeleton landmarks based on motion type and time
      frame_time = timestamp / 1000.0
      landmarks = generate_skeleton_landmarks(skeleton_state, frame_time, motion_type)

      %{
        timestamp: timestamp,
        delay: delay,
        payload: %{landmarks: landmarks}
      }
    end)
  end

  # Store skeleton state per sensor for continuity
  @skeleton_states_table :skeleton_sim_states
  @respiration_buffers_table :respiration_sim_buffers
  @hrv_buffers_table :hrv_sim_buffers
  @gaze_states_table :gaze_sim_states

  # Safely create a named ETS table, handling the race condition where
  # multiple DataServer workers try to create the same table concurrently.
  defp ensure_ets_table(name) do
    try do
      :ets.new(name, [:named_table, :public, :set])
    rescue
      ArgumentError -> :ok
    end
  end

  defp get_skeleton_state(sensor_id, motion_type) do
    try do
      case :ets.lookup(@skeleton_states_table, sensor_id) do
        [{^sensor_id, state}] -> state
        [] -> init_skeleton_state(sensor_id, motion_type)
      end
    rescue
      ArgumentError ->
        ensure_ets_table(@skeleton_states_table)
        init_skeleton_state(sensor_id, motion_type)
    end
  end

  defp init_skeleton_state(sensor_id, motion_type) do
    state = %{
      motion_type: motion_type,
      phase: :rand.uniform() * 2 * :math.pi(),
      speed_factor: 0.8 + :rand.uniform() * 0.4
    }

    :ets.insert(@skeleton_states_table, {sensor_id, state})
    state
  end

  # Generate 33 MediaPipe pose landmarks with realistic motion using keyframe interpolation
  # Landmarks: 0-10 face, 11-12 shoulders, 13-14 elbows, 15-16 wrists,
  # 17-22 hands, 23-24 hips, 25-26 knees, 27-28 ankles, 29-32 feet
  defp generate_skeleton_landmarks(state, time, motion_type) do
    phase = state.phase
    speed = state.speed_factor

    # Get keyframes and cycle duration for this motion type
    keyframes = MotionKeyframes.get_keyframes(motion_type)
    cycle_duration = MotionKeyframes.cycle_duration(motion_type)

    # Calculate position in animation cycle (0.0 to 1.0)
    # Phase offset provides variation between different sensors
    cycle_time = time * speed + phase
    normalized_time = :math.fmod(cycle_time, cycle_duration) / cycle_duration

    # Ensure normalized_time is positive
    normalized_time = if normalized_time < 0, do: normalized_time + 1.0, else: normalized_time

    # Interpolate between keyframes
    animated_pose = interpolate_keyframes(keyframes, normalized_time)

    # Add slight noise for realism
    add_tracking_noise(animated_pose)
  end

  # Interpolate between keyframes based on normalized time (0.0 to 1.0)
  defp interpolate_keyframes(keyframes, normalized_time) do
    # Find the two keyframes to interpolate between
    {prev_frame, next_frame, blend_factor} = find_keyframe_pair(keyframes, normalized_time)

    # Interpolate each landmark
    Enum.zip(prev_frame.landmarks, next_frame.landmarks)
    |> Enum.map(fn {prev_lm, next_lm} ->
      %{
        x: lerp(prev_lm.x, next_lm.x, blend_factor),
        y: lerp(prev_lm.y, next_lm.y, blend_factor),
        v: lerp(prev_lm.v, next_lm.v, blend_factor)
      }
    end)
  end

  # Find the two keyframes surrounding the current time and calculate blend factor
  defp find_keyframe_pair(keyframes, normalized_time) do
    # Find the keyframe just before or at normalized_time
    prev_idx =
      keyframes
      |> Enum.with_index()
      |> Enum.filter(fn {kf, _idx} -> kf.time <= normalized_time end)
      |> Enum.max_by(fn {kf, _idx} -> kf.time end, fn -> {hd(keyframes), 0} end)
      |> elem(1)

    # Next keyframe (wraps around to first)
    next_idx = rem(prev_idx + 1, length(keyframes))

    prev_frame = Enum.at(keyframes, prev_idx)
    next_frame = Enum.at(keyframes, next_idx)

    # Calculate time span between keyframes (handling wrap-around)
    time_span =
      if next_idx == 0 do
        # Wrapping from last keyframe to first
        1.0 - prev_frame.time + next_frame.time
      else
        next_frame.time - prev_frame.time
      end

    # Calculate how far we are between the two keyframes
    time_since_prev =
      if next_idx == 0 and normalized_time < prev_frame.time do
        normalized_time + (1.0 - prev_frame.time)
      else
        normalized_time - prev_frame.time
      end

    # Blend factor (0.0 = prev_frame, 1.0 = next_frame)
    blend_factor = if time_span > 0, do: time_since_prev / time_span, else: 0.0
    blend_factor = max(0.0, min(1.0, blend_factor))

    # Apply smoothstep for smoother animation (ease in/out)
    blend_factor = smoothstep(blend_factor)

    {prev_frame, next_frame, blend_factor}
  end

  # Linear interpolation
  defp lerp(a, b, t), do: a + (b - a) * t

  # Smoothstep function for easing
  defp smoothstep(t), do: t * t * (3 - 2 * t)

  # Add slight tracking noise for realism
  defp add_tracking_noise(pose) do
    Enum.map(pose, fn lm ->
      noise_x = (:rand.uniform() - 0.5) * 0.003
      noise_y = (:rand.uniform() - 0.5) * 0.003
      # Visibility jitter
      noise_v = (:rand.uniform() - 0.5) * 0.02

      %{
        x: Float.round(lm.x + noise_x, 4),
        y: Float.round(lm.y + noise_y, 4),
        v: Float.round(min(1.0, max(0.5, lm.v + noise_v)), 2)
      }
    end)
  end

  # Respiration data using pre-generated NeuroKit2 buffers via Pythonx
  # Each sensor gets a unique 120s waveform cached in ETS for zero per-tick Python overhead
  defp fetch_respiration_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 10, 0.1)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    buffer = get_respiration_buffer(sensor_id, config)

    results =
      Enum.map(0..(batch_size - 1), fn i ->
        timestamp = now + i * interval_ms
        delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

        index = rem(buffer.index + i, buffer.total)
        value = elem(buffer.data, index)

        %{
          timestamp: timestamp,
          delay: delay,
          payload: Float.round(value * 1.0, 2)
        }
      end)

    # Advance buffer index
    new_index = rem(buffer.index + batch_size, buffer.total)
    :ets.insert(@respiration_buffers_table, {sensor_id, %{buffer | index: new_index}})

    results
  end

  defp get_respiration_buffer(sensor_id, config) do
    try do
      case :ets.lookup(@respiration_buffers_table, sensor_id) do
        [{^sensor_id, buffer}] -> buffer
        [] -> init_respiration_buffer(sensor_id, config)
      end
    rescue
      ArgumentError ->
        ensure_ets_table(@respiration_buffers_table)
        init_respiration_buffer(sensor_id, config)
    end
  end

  defp init_respiration_buffer(sensor_id, config) do
    sampling_rate = max(config[:sampling_rate] || 10, 0.1)
    brpm = config[:breaths_per_minute] || 15
    duration = 120

    samples = generate_neurokit2_buffer(sampling_rate, brpm, duration)

    buffer = %{
      data: List.to_tuple(samples),
      index: 0,
      total: length(samples)
    }

    :ets.insert(@respiration_buffers_table, {sensor_id, buffer})

    Logger.info(
      "Initialized respiration buffer for #{sensor_id}: #{buffer.total} samples (#{duration}s at #{sampling_rate}Hz, #{brpm} brpm)"
    )

    buffer
  end

  defp generate_neurokit2_buffer(sampling_rate, brpm, duration) do
    sr = round(sampling_rate)

    python_code = """
    import neurokit2 as nk
    import numpy as np

    rsp = nk.rsp_simulate(
        duration=#{duration},
        sampling_rate=#{sr},
        respiratory_rate=#{brpm},
        method="breathmetrics"
    )
    rsp_arr = np.array(rsp).flatten()
    rsp_min = float(np.min(rsp_arr))
    rsp_max = float(np.max(rsp_arr))
    if rsp_max > rsp_min:
        rsp_normalized = (rsp_arr - rsp_min) / (rsp_max - rsp_min)
    else:
        rsp_normalized = np.zeros_like(rsp_arr)
    rsp_scaled = 50.0 + 50.0 * rsp_normalized
    rsp_scaled.tolist()
    """

    {result, _globals} = Pythonx.eval(python_code, %{})
    Pythonx.decode(result)
  rescue
    e ->
      Logger.warning("NeuroKit2 buffer generation failed: #{inspect(e)}, using sine fallback")
      generate_fallback_respiration_buffer(sampling_rate, brpm, duration)
  end

  defp generate_fallback_respiration_buffer(sampling_rate, brpm, duration) do
    total_samples = trunc(duration * sampling_rate)
    freq = brpm / 60.0
    phase_offset = :rand.uniform() * 2 * :math.pi()

    Enum.map(0..(total_samples - 1), fn i ->
      t = i / sampling_rate
      value = 75.0 + 25.0 * :math.sin(2 * :math.pi() * freq * t + phase_offset)
      Float.round(value, 2)
    end)
  end

  # HRV data using pre-generated physiological RMSSD model cached in ETS.
  # Payload: %{"rmssd" => ms, "sdnn" => ms} matching ECGSensor.validate_payload/2.
  defp fetch_hrv_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 0.2, 0.01)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    buffer = get_hrv_buffer(sensor_id, config)

    results =
      Enum.map(0..(batch_size - 1), fn i ->
        timestamp = now + i * interval_ms
        delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

        index = rem(buffer.index + i, buffer.total)
        rmssd = Float.round(elem(buffer.data, index) * 1.0, 2)

        # SDNN correlates with RMSSD but is typically 1.2–1.8× higher
        sdnn_ratio = 1.3 + :rand.uniform() * 0.4
        sdnn = Float.round(rmssd * sdnn_ratio + (:rand.uniform() - 0.5) * 3.0, 2)
        sdnn = max(5.0, min(200.0, sdnn))

        %{
          timestamp: timestamp,
          delay: delay,
          payload: %{"rmssd" => rmssd, "sdnn" => sdnn}
        }
      end)

    new_index = rem(buffer.index + batch_size, buffer.total)
    :ets.insert(@hrv_buffers_table, {sensor_id, %{buffer | index: new_index}})

    results
  end

  defp get_hrv_buffer(sensor_id, config) do
    try do
      case :ets.lookup(@hrv_buffers_table, sensor_id) do
        [{^sensor_id, buffer}] -> buffer
        [] -> init_hrv_buffer(sensor_id, config)
      end
    rescue
      ArgumentError ->
        ensure_ets_table(@hrv_buffers_table)
        init_hrv_buffer(sensor_id, config)
    end
  end

  defp init_hrv_buffer(sensor_id, config) do
    heart_rate = config[:heart_rate] || 70
    # 30 minutes of unique data at 0.2 Hz = 360 samples before looping
    duration = 1800

    samples = generate_physiological_hrv_buffer(sensor_id, heart_rate, duration)

    buffer = %{
      data: List.to_tuple(samples),
      index: 0,
      total: length(samples)
    }

    :ets.insert(@hrv_buffers_table, {sensor_id, buffer})

    Logger.info(
      "Initialized HRV buffer for #{sensor_id}: #{buffer.total} RMSSD samples " <>
        "(#{duration}s physiological model, HR=#{heart_rate} bpm, " <>
        "range #{buffer.data |> Tuple.to_list() |> Enum.min() |> Float.round(1)}" <>
        "–#{buffer.data |> Tuple.to_list() |> Enum.max() |> Float.round(1)} ms)"
    )

    buffer
  end

  # Physiological HRV model: generates realistic RMSSD (ms) time series.
  #
  # RMSSD is built as a sum of known physiological oscillations:
  #   RSA  — Respiratory Sinus Arrhythmia    (HF: 0.15–0.40 Hz, ~12–18 breaths/min)
  #   LF   — Mayer waves / baroreflex        (LF: 0.07–0.12 Hz)
  #   VLF  — Thermoregulation / hormonal     (VLF: 0.02–0.04 Hz)
  #   Drift — Ultra-slow non-stationarity    (<0.01 Hz, circadian-like)
  #   Noise — Measurement / estimation noise
  #
  # Baseline anti-correlates with HR (high HR → lower HRV).
  # All parameters are seeded from sensor_id so each person is unique but
  # deterministic across restarts. Values are clipped to 5–150 ms.
  defp generate_physiological_hrv_buffer(sensor_id, heart_rate, duration) do
    python_code = """
    import numpy as np

    # --- Per-person deterministic seed ---
    seed = abs(hash('#{sensor_id}')) % (2**31)
    rng = np.random.default_rng(seed)

    hr = float(#{heart_rate})
    n = int(#{duration} * 0.2)
    t = np.linspace(0.0, float(#{duration}), n)

    # ── Baseline RMSSD (anti-correlates with HR) ──
    # HR 50→~55ms, HR 80→~38ms, HR 100→~22ms
    hr_factor = float(np.clip((hr - 40.0) / 70.0, 0.0, 1.0))
    baseline = rng.uniform(48.0, 65.0) - hr_factor * rng.uniform(28.0, 38.0)

    # ── State transitions: baseline shifts over minutes ──
    # Simulate autonomic state changes (relax/moderate/stressed periods)
    # Use 2-3 slow random walk steps smoothed with a wide Gaussian
    n_states = rng.integers(2, 5)
    state_times = np.sort(rng.uniform(0, float(#{duration}), n_states))
    state_shifts = rng.normal(0, 8.0, n_states)  # ±8ms baseline shifts
    state_signal = np.zeros(n)
    for st, sv in zip(state_times, state_shifts):
        state_signal += sv * np.exp(-0.5 * ((t - st) / 90.0) ** 2)  # 90s Gaussian width

    # ── Respiratory Sinus Arrhythmia (HF band) ──
    # Breathing rate drifts slowly (±1 brpm over minutes)
    resp_rate_base = rng.uniform(12.0, 18.0)  # breaths/min
    resp_drift = np.cumsum(rng.normal(0, 0.003, n))  # slow random walk
    resp_drift = resp_drift - np.mean(resp_drift)
    resp_freq = (resp_rate_base + resp_drift * 2.0) / 60.0  # Hz, time-varying
    resp_freq = np.clip(resp_freq, 0.12, 0.40)  # keep in physiological HF band

    resp_amp_base = rng.uniform(9.0, 17.0)
    # Amplitude modulation: breathing depth varies (e.g. sighs, talking)
    resp_am = 1.0 + 0.3 * np.sin(2.0 * np.pi * rng.uniform(0.002, 0.008) * t + rng.uniform(0, 6.28))
    resp_phase = rng.uniform(0.0, 2.0 * np.pi)
    resp_signal = resp_amp_base * resp_am * np.sin(
        2.0 * np.pi * np.cumsum(resp_freq) / 0.2 + resp_phase
    )

    # ── Mayer waves / baroreflex (LF band) ──
    mayer_freq = rng.uniform(0.07, 0.12)
    mayer_amp_base = rng.uniform(4.0, 9.0)
    # Amplitude modulation: blood pressure regulation varies
    mayer_am = 1.0 + 0.4 * np.sin(2.0 * np.pi * rng.uniform(0.001, 0.005) * t)
    mayer_phase = rng.uniform(0.0, 2.0 * np.pi)
    mayer_signal = mayer_amp_base * mayer_am * np.sin(
        2.0 * np.pi * mayer_freq * t + mayer_phase
    )

    # ── VLF component (thermoregulation, hormonal) ──
    vlf_freq = rng.uniform(0.020, 0.040)
    vlf_amp = rng.uniform(2.5, 6.0)
    vlf_phase = rng.uniform(0.0, 2.0 * np.pi)
    vlf_signal = vlf_amp * np.sin(2.0 * np.pi * vlf_freq * t + vlf_phase)

    # ── Ultra-slow drift (posture, alertness, circadian) ──
    drift_freq = rng.uniform(0.003, 0.010)
    drift_amp = rng.uniform(4.0, 11.0)
    drift_phase = rng.uniform(0.0, 2.0 * np.pi)
    drift_signal = drift_amp * np.sin(2.0 * np.pi * drift_freq * t + drift_phase)

    # ── Shared environment coupling ──
    # All people in the same room experience a common slow signal
    # (e.g. shared task, instructor pacing, room temperature)
    # Use a deterministic "room seed" (same for all sensors)
    room_rng = np.random.default_rng(42)
    room_freq = room_rng.uniform(0.004, 0.012)
    room_amp = room_rng.uniform(3.0, 7.0)
    coupling_strength = rng.uniform(0.2, 0.6)  # per-person susceptibility
    room_signal = coupling_strength * room_amp * np.sin(
        2.0 * np.pi * room_freq * t + room_rng.uniform(0.0, 6.28)
    )

    # ── Measurement noise (1/f pink-ish + white) ──
    white_sigma = rng.uniform(1.0, 2.5)
    white_noise = rng.normal(0.0, white_sigma, n)
    # Simple 1/f approximation via cumulative-sum filtering
    pink_raw = np.cumsum(rng.normal(0, 0.3, n))
    pink_raw = pink_raw - np.linspace(pink_raw[0], pink_raw[-1], n)  # detrend
    pink_noise = pink_raw * rng.uniform(0.5, 1.5)

    # ── Combine all components ──
    rmssd = (
        baseline
        + state_signal
        + resp_signal
        + mayer_signal
        + vlf_signal
        + drift_signal
        + room_signal
        + white_noise
        + pink_noise
    )

    # Physiological bounds
    rmssd = np.clip(rmssd, 5.0, 150.0)
    list(np.round(rmssd, 2))
    """

    {result, _globals} = Pythonx.eval(python_code, %{})
    Pythonx.decode(result)
  rescue
    e ->
      Logger.warning(
        "Physiological HRV buffer generation failed: #{inspect(e)}, using Elixir fallback"
      )

      generate_fallback_hrv_buffer(sensor_id, heart_rate, duration)
  end

  # Pure-Elixir fallback with the same physiological structure.
  # Simplified version: has amplitude modulation, state transitions, and room coupling
  # but omits frequency wobble (requires cumulative sum which is expensive in Enum.map).
  defp generate_fallback_hrv_buffer(sensor_id, heart_rate, duration) do
    seed = :erlang.phash2(sensor_id, 999_983)
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    pi2 = 2.0 * :math.pi()
    hr_factor = min(max((heart_rate - 40) / 70.0, 0.0), 1.0)
    baseline = 50.0 + :rand.uniform() * 14.0 - hr_factor * 30.0

    # Respiratory component with amplitude modulation
    resp_freq = (12.0 + :rand.uniform() * 6.0) / 60.0
    resp_amp = 9.0 + :rand.uniform() * 8.0
    resp_phase = :rand.uniform() * pi2
    resp_am_freq = 0.002 + :rand.uniform() * 0.006

    # Mayer waves with amplitude modulation
    mayer_freq = 0.07 + :rand.uniform() * 0.05
    mayer_amp = 4.0 + :rand.uniform() * 5.0
    mayer_phase = :rand.uniform() * pi2
    mayer_am_freq = 0.001 + :rand.uniform() * 0.004

    vlf_freq = 0.020 + :rand.uniform() * 0.020
    vlf_amp = 2.5 + :rand.uniform() * 3.5
    vlf_phase = :rand.uniform() * pi2

    drift_freq = 0.003 + :rand.uniform() * 0.007
    drift_amp = 4.0 + :rand.uniform() * 7.0
    drift_phase = :rand.uniform() * pi2

    # State transitions: 2-4 Gaussian bumps
    n_states = 2 + :rand.uniform(3) - 1
    state_times = Enum.map(1..n_states, fn _ -> :rand.uniform() * duration end)
    state_shifts = Enum.map(1..n_states, fn _ -> (:rand.uniform() - 0.5) * 16.0 end)
    states = Enum.zip(state_times, state_shifts)

    # Room coupling (deterministic seed=42 for all sensors)
    :rand.seed(:exsss, {42, 43, 44})
    room_freq = 0.004 + :rand.uniform() * 0.008
    room_amp = 3.0 + :rand.uniform() * 4.0
    room_phase = :rand.uniform() * pi2
    # Re-seed per sensor for coupling strength
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    # Advance state past the params we already consumed
    Enum.each(1..20, fn _ -> :rand.uniform() end)
    coupling = 0.2 + :rand.uniform() * 0.4

    n = trunc(duration * 0.2)

    Enum.map(0..(n - 1), fn i ->
      t = i / n * duration

      # State signal (sum of Gaussians)
      state_val =
        Enum.reduce(states, 0.0, fn {st, sv}, acc ->
          acc + sv * :math.exp(-0.5 * :math.pow((t - st) / 90.0, 2))
        end)

      resp_am = 1.0 + 0.3 * :math.sin(pi2 * resp_am_freq * t)
      mayer_am = 1.0 + 0.4 * :math.sin(pi2 * mayer_am_freq * t)

      value =
        baseline +
          state_val +
          resp_amp * resp_am * :math.sin(pi2 * resp_freq * t + resp_phase) +
          mayer_amp * mayer_am * :math.sin(pi2 * mayer_freq * t + mayer_phase) +
          vlf_amp * :math.sin(pi2 * vlf_freq * t + vlf_phase) +
          drift_amp * :math.sin(pi2 * drift_freq * t + drift_phase) +
          coupling * room_amp * :math.sin(pi2 * room_freq * t + room_phase) +
          (:rand.uniform() - 0.5) * 4.5

      Float.round(min(150.0, max(5.0, value)), 2)
    end)
  end

  # ===========================================
  # EYE TRACKING (Pupil Labs Neon)
  # ===========================================

  # Eye gaze data with realistic fixation/saccade state machine
  # Payload: %{x: 0.0-1.0, y: 0.0-1.0, confidence: 0.6-0.99}
  defp fetch_eye_gaze_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 200, 1)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)

    gaze_state = get_gaze_state(sensor_id, config)

    {results, final_state} =
      Enum.map_reduce(0..(batch_size - 1), gaze_state, fn i, state ->
        timestamp = now + i * interval_ms
        delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

        {x, y, confidence, new_state} = generate_gaze_point(state, timestamp)

        entry = %{
          timestamp: timestamp,
          delay: delay,
          payload: %{
            x: Float.round(x, 4),
            y: Float.round(y, 4),
            confidence: Float.round(confidence, 3)
          }
        }

        {entry, new_state}
      end)

    :ets.insert(@gaze_states_table, {sensor_id, final_state})
    results
  end

  defp get_gaze_state(sensor_id, config) do
    try do
      case :ets.lookup(@gaze_states_table, sensor_id) do
        [{^sensor_id, state}] -> state
        [] -> init_gaze_state(sensor_id, config)
      end
    rescue
      ArgumentError ->
        ensure_ets_table(@gaze_states_table)
        init_gaze_state(sensor_id, config)
    end
  end

  defp init_gaze_state(sensor_id, config) do
    now = :os.system_time(:millisecond)
    fixation_dur = config[:fixation_duration] || 200 + :rand.uniform(600)

    state = %{
      mode: :fixation,
      fixation_x: 0.3 + :rand.uniform() * 0.4,
      fixation_y: 0.3 + :rand.uniform() * 0.4,
      fixation_start: now,
      fixation_duration: fixation_dur,
      base_fixation_duration: fixation_dur,
      saccade_duration: config[:saccade_duration] || 20 + :rand.uniform(60),
      next_fixation_x: nil,
      next_fixation_y: nil
    }

    :ets.insert(@gaze_states_table, {sensor_id, state})
    state
  end

  defp generate_gaze_point(state, timestamp) do
    elapsed = timestamp - state.fixation_start

    case state.mode do
      :fixation ->
        jitter_x = (:rand.uniform() - 0.5) * 0.01
        jitter_y = (:rand.uniform() - 0.5) * 0.01

        x = clamp(state.fixation_x + jitter_x, 0.0, 1.0)
        y = clamp(state.fixation_y + jitter_y, 0.0, 1.0)
        confidence = 0.92 + :rand.uniform() * 0.07

        if elapsed >= state.fixation_duration do
          next_x = :rand.uniform()
          next_y = :rand.uniform()

          new_state = %{
            state
            | mode: :saccade,
              next_fixation_x: next_x,
              next_fixation_y: next_y,
              fixation_start: timestamp
          }

          {x, y, confidence, new_state}
        else
          {x, y, confidence, state}
        end

      :saccade ->
        progress = min(elapsed / state.saccade_duration, 1.0)
        eased = smoothstep(progress)

        x = lerp(state.fixation_x, state.next_fixation_x, eased)
        y = lerp(state.fixation_y, state.next_fixation_y, eased)
        confidence = 0.6 + :rand.uniform() * 0.2

        if progress >= 1.0 do
          new_duration =
            state.base_fixation_duration +
              :rand.uniform(trunc(state.base_fixation_duration * 0.5)) -
              trunc(state.base_fixation_duration * 0.25)

          new_state = %{
            state
            | mode: :fixation,
              fixation_x: state.next_fixation_x,
              fixation_y: state.next_fixation_y,
              fixation_start: timestamp,
              fixation_duration: max(100, new_duration),
              next_fixation_x: nil,
              next_fixation_y: nil
          }

          {x, y, confidence, new_state}
        else
          {x, y, confidence, state}
        end
    end
  end

  # Eye aperture data with blink correlation
  # Payload: %{left: 0.0-25.0, right: 0.0-25.0} (degrees)
  defp fetch_eye_aperture_data(config) do
    sensor_id = config[:sensor_id] || "unknown"
    batch_size = config[:batch_size] || 1
    sampling_rate = max(config[:sampling_rate] || 30, 1)

    now = :os.system_time(:millisecond)
    interval_ms = round(1000 / sampling_rate)
    blink_seed = :erlang.phash2(sensor_id, 1000)

    Enum.map(0..(batch_size - 1), fn i ->
      timestamp = now + i * interval_ms
      delay = if i == 0 and batch_size > 1, do: 0.0, else: 1.0 / sampling_rate

      {left, right} = generate_aperture(timestamp, blink_seed)

      %{
        timestamp: timestamp,
        delay: delay,
        payload: %{
          left: Float.round(left, 2),
          right: Float.round(right, 2)
        }
      }
    end)
  end

  defp generate_aperture(timestamp, blink_seed) do
    base_aperture = 17.5
    blink_phase = blink_phase(timestamp, blink_seed)

    if blink_phase > 0.0 do
      # During blink: smooth close/open curve
      # blink_phase goes 0→1→0 over the blink
      closure = :math.sin(blink_phase * :math.pi())
      aperture = base_aperture * (1.0 - closure)
      asymmetry = (:rand.uniform() - 0.5) * 0.3
      {max(0.0, aperture + asymmetry), max(0.0, aperture - asymmetry)}
    else
      # Normal state
      left = base_aperture + (:rand.uniform() - 0.5) * 1.5
      right = base_aperture + (:rand.uniform() - 0.5) * 1.5
      {clamp(left, 12.0, 22.0), clamp(right, 12.0, 22.0)}
    end
  end

  # Returns 0.0 when not blinking, or 0.0-1.0 progress through a blink
  # Uses deterministic timing from sensor_id hash for blink/aperture correlation
  defp blink_phase(timestamp, seed) do
    # ~15 blinks/min → one blink every ~4000ms
    cycle = rem(timestamp + seed * 1000, 4000)
    blink_duration = 250

    cond do
      cycle < blink_duration ->
        cycle / blink_duration

      cycle >= 2200 and cycle < 2200 + blink_duration ->
        (cycle - 2200) / blink_duration

      true ->
        0.0
    end
  end

  defp clamp(value, min_val, max_val), do: max(min_val, min(max_val, value))

  # Fetch real hydrological data from existenz.ch API (BAFU/FOEN source)
  # Called by AttributeServer for sensor_type: "hydro_api" attributes.
  # Returns a single measurement; the delay field controls next poll timing.
  defp fetch_hydro_api_data(config) do
    station_id = to_string(config[:hydro_station_id] || "")
    parameter = to_string(config[:hydro_parameter] || "")
    sampling_rate = max(config[:sampling_rate] || 0.00333, 0.000001)
    delay = 1.0 / sampling_rate

    url = "https://api.existenz.ch/apiv1/hydro/latest"

    result =
      Req.get(url,
        params: [locations: station_id, parameters: parameter, app: "sensocto"],
        receive_timeout: 15_000
      )

    case result do
      {:ok, %{status: 200, body: body}} ->
        payload_items = body["payload"] || []

        case Enum.find(payload_items, fn item ->
               item["loc"] == station_id and item["par"] == parameter
             end) do
          %{"val" => val, "timestamp" => ts} ->
            [%{delay: delay, payload: val, timestamp: ts * 1000}]

          nil ->
            Logger.warning("hydro_api: no value for station=#{station_id} parameter=#{parameter}")

            [%{delay: delay, payload: nil, timestamp: :os.system_time(:millisecond)}]
        end

      {:ok, %{status: status}} ->
        Logger.warning(
          "hydro_api: HTTP #{status} for station=#{station_id} parameter=#{parameter}"
        )

        [%{delay: delay, payload: nil, timestamp: :os.system_time(:millisecond)}]

      {:error, reason} ->
        Logger.warning(
          "hydro_api: request failed for station=#{station_id} parameter=#{parameter}: #{inspect(reason)}"
        )

        [%{delay: delay, payload: nil, timestamp: :os.system_time(:millisecond)}]
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
        "--mode",
        "csv",
        "--sensor_id",
        "#{config[:sensor_id] || "sim"}",
        "--sensor_type",
        "#{config[:sensor_type] || "heartrate"}",
        "--duration",
        "#{config[:duration] || 30}",
        "--sampling_rate",
        "#{config[:sampling_rate] || 1}",
        "--heart_rate",
        "#{config[:heart_rate] || 75}",
        "--respiratory_rate",
        "#{config[:respiratory_rate] || 15}",
        "--scr_number",
        "#{config[:scr_number] || 5}",
        "--burst_number",
        "#{config[:burst_number] || 5}"
      ]

      simulator_dir = Path.join(File.cwd!(), "simulator")

      case System.cmd("uv", ["run", "python3" | args],
             stderr_to_stdout: true,
             cd: simulator_dir
           ) do
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

    # sample_offset keeps waveform phase continuous across batch boundaries
    sample_offset = config[:sample_offset] || 0

    data_lines =
      Enum.map(0..(num_samples - 1), fn i ->
        timestamp = now + i * interval_ms
        # For batch_size 1, we still need the sampling_rate delay since each fetch is one sample
        # Only skip delay for the first sample in multi-sample batches
        delay = if i == 0 and num_samples > 1, do: 0.0, else: 1.0 / sampling_rate
        value = generate_value(sensor_type, config, i + sample_offset, sampling_rate)
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
  # activity_level (0.0-1.0) scales amplitude: 0.1=seated calm, 0.5=walking, 1.0=vigorous
  # Multiple overlapping frequencies create realistic, non-repetitive motion patterns
  defp generate_value("accelerometer_x", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 12.0
    step = :math.sin(i * 0.5) * a * 0.5
    swing = :math.sin(i * 0.17 + 1.2) * a * 0.3
    burst = if rem(trunc(i), 200) < 20, do: :math.sin(i * 1.5) * a * 0.8, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.2
    step + swing + burst + noise
  end

  defp generate_value("accelerometer_y", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 10.0
    sway = :math.sin(i * 0.25 + 0.7) * a * 0.4
    drift = :math.sin(i * 0.03) * a * 0.6
    jolt = if rem(trunc(i), 300) < 10, do: (:rand.uniform() - 0.5) * a * 1.5, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    sway + drift + jolt + noise
  end

  defp generate_value("accelerometer_z", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 8.0
    gravity = 9.81
    bounce = :math.sin(i * 0.5 + 2.1) * a * 0.4
    breathing = :math.sin(i * 0.08) * a * 0.2
    noise = (:rand.uniform() - 0.5) * a * 0.15
    gravity + bounce + breathing + noise
  end

  # Gyroscope - rotation rates (rad/s)
  defp generate_value("gyroscope_x", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 6.0
    nod = :math.sin(i * 0.15 + 0.5) * a * 0.5
    micro = :math.sin(i * 0.8) * a * 0.2
    head_turn = if rem(trunc(i), 250) < 30, do: :math.sin(i * 0.6) * a * 0.8, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    nod + micro + head_turn + noise
  end

  defp generate_value("gyroscope_y", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 5.0
    roll = :math.sin(i * 0.2 + 1.8) * a * 0.4
    wobble = :math.sin(i * 0.55 + 3.0) * a * 0.3
    noise = (:rand.uniform() - 0.5) * a * 0.12
    roll + wobble + noise
  end

  defp generate_value("gyroscope_z", config, i, _sampling_rate) do
    a = (config[:activity_level] || 0.5) * 8.0
    scan = :math.sin(i * 0.06) * a * 0.5
    turn = if rem(trunc(i), 180) < 25, do: :math.sin(i * 0.4 + 0.3) * a * 1.0, else: 0.0
    noise = (:rand.uniform() - 0.5) * a * 0.15
    scan + turn + noise
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

  # ===========================================
  # CORAL RESTORATION / MARINE SENSORS
  # ===========================================

  # Water temperature - critical for coral health
  # Coral bleaching threshold 29-30°C, stress begins around 29°C
  defp generate_value("water_temperature", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 26.5, 29.5)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Diurnal variation (warmer during day)
    diurnal = :math.sin(i * 0.001) * range * 0.6
    # Tidal influence
    tidal = :math.sin(i * 0.003) * range * 0.2
    noise = (:rand.uniform() - 0.5) * 0.1
    Float.round(base + diurnal + tidal + noise, 2)
  end

  # Sea surface temperature
  defp generate_value("sea_surface_temperature", config, i, sampling_rate) do
    generate_value("water_temperature", config, i, sampling_rate)
  end

  # Salinity (parts per thousand) - coral thrives 32-42 ppt
  defp generate_value("salinity", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 33.0, 36.0)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Slow tidal/evaporation variation
    tidal = :math.sin(i * 0.002) * range * 0.5
    # Rainfall events (occasional drops)
    rainfall = if :rand.uniform() < 0.02, do: -:rand.uniform() * 0.5, else: 0
    noise = (:rand.uniform() - 0.5) * 0.1
    Float.round(base + tidal + rainfall + noise, 2)
  end

  # pH - ocean acidification indicator (healthy 7.8-8.5)
  defp generate_value("ph", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 8.0, 8.3)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Diurnal variation (photosynthesis increases pH during day)
    diurnal = :math.sin(i * 0.001) * range * 0.7
    noise = (:rand.uniform() - 0.5) * 0.02
    Float.round(base + diurnal + noise, 3)
  end

  # PAR - Photosynthetically Active Radiation (umol/m2/s)
  defp generate_value("light_par", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 100, 400)
    midpoint = (min_val + max_val) / 2
    amplitude = (max_val - min_val) / 2
    # Strong diurnal cycle (day/night)
    diurnal = :math.sin(i * 0.001) * amplitude
    # Cloud cover variation
    clouds = :math.sin(i * 0.01) * amplitude * 0.3
    noise = (:rand.uniform() - 0.5) * 20
    max(0, Float.round(midpoint + diurnal + clouds + noise, 1))
  end

  # Dissolved oxygen (mg/L) - healthy >6 mg/L
  defp generate_value("dissolved_oxygen", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 6.0, 8.5)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Higher during day (photosynthesis), lower at night (respiration)
    diurnal = :math.sin(i * 0.001) * range * 0.6
    noise = (:rand.uniform() - 0.5) * 0.2
    Float.round(base + diurnal + noise, 2)
  end

  # Turbidity (NTU) - low is better for coral (<10 NTU ideal)
  defp generate_value("turbidity", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.5, 5.0)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Current/wave influence
    wave_effect = abs(:math.sin(i * 0.005)) * range * 0.5
    # Occasional sediment disturbance spikes
    spike = if :rand.uniform() < 0.03, do: :rand.uniform() * 3, else: 0
    noise = (:rand.uniform() - 0.5) * 0.3
    max(0, Float.round(base + wave_effect + spike + noise, 2))
  end

  # Depth (meters) - station depth monitoring
  defp generate_value("depth", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 8.0, 12.0)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Tidal variation
    tidal = :math.sin(i * 0.0005) * range * 0.8
    # Wave influence
    wave = :math.sin(i * 0.05) * 0.1
    Float.round(base + tidal + wave, 2)
  end

  # Nitrate (umol/L) - excess promotes algae, ideal <1 umol/L
  defp generate_value("nitrate", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.1, 0.8)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Slow drift with occasional inputs
    drift = :math.sin(i * 0.0002) * range * 0.5
    input_event = if :rand.uniform() < 0.01, do: :rand.uniform() * 0.2, else: 0
    noise = (:rand.uniform() - 0.5) * 0.05
    max(0, Float.round(base + drift + input_event + noise, 3))
  end

  # Phosphate (umol/L) - ideal <0.1 umol/L
  defp generate_value("phosphate", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.02, 0.08)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    drift = :math.sin(i * 0.0002) * range * 0.4
    noise = (:rand.uniform() - 0.5) * 0.01
    max(0, Float.round(base + drift + noise, 4))
  end

  # Ammonia (umol/L) - toxic at high levels
  defp generate_value("ammonia", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.01, 0.05)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    drift = :math.sin(i * 0.0003) * range * 0.3
    noise = (:rand.uniform() - 0.5) * 0.005
    max(0, Float.round(base + drift + noise, 4))
  end

  # Alkalinity (umol/kg) - carbonate chemistry for calcification
  defp generate_value("alkalinity", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 2200, 2400)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Slow biological/chemical variation
    variation = :math.sin(i * 0.0001) * range * 0.3
    noise = (:rand.uniform() - 0.5) * 20
    Float.round(base + variation + noise, 0)
  end

  # Current speed (m/s)
  defp generate_value("current_speed", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.05, 0.35)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Tidal influence
    tidal = abs(:math.sin(i * 0.001)) * range * 0.7
    # Turbulent fluctuations
    turbulence = :math.sin(i * 0.1) * range * 0.2
    noise = (:rand.uniform() - 0.5) * 0.02
    max(0, Float.round(base + tidal + turbulence + noise, 3))
  end

  # Current direction (degrees 0-360)
  defp generate_value("current_direction", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0, 360)
    base = (min_val + max_val) / 2
    # Slow tidal rotation
    rotation = :math.sin(i * 0.0005) * 45
    # Eddies
    eddy = :math.sin(i * 0.01) * 15
    noise = (:rand.uniform() - 0.5) * 10
    result = base + rotation + eddy + noise
    Float.round(rem(trunc(result) + 360, 360) * 1.0, 1)
  end

  # Wave height (meters)
  defp generate_value("wave_height", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.2, 1.5)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Swell patterns
    swell = abs(:math.sin(i * 0.002)) * range * 0.6
    # Wind chop
    chop = abs(:math.sin(i * 0.02)) * range * 0.2
    noise = (:rand.uniform() - 0.5) * 0.1
    max(0, Float.round(base + swell + chop + noise, 2))
  end

  # Wind speed (m/s)
  defp generate_value("wind_speed", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 2.0, 15.0)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Diurnal variation (often calmer at night/morning)
    diurnal = :math.sin(i * 0.001) * range * 0.4
    # Gusts
    gust = if :rand.uniform() < 0.05, do: :rand.uniform() * 5, else: 0
    noise = (:rand.uniform() - 0.5) * 1.0
    max(0, Float.round(base + diurnal + gust + noise, 1))
  end

  # Solar irradiance (W/m2)
  defp generate_value("solar_irradiance", config, i, _sampling_rate) do
    {_min_val, max_val} = get_min_max(config, 0, 1000)
    midpoint = max_val / 2
    amplitude = max_val / 2
    # Strong diurnal cycle
    diurnal = :math.sin(i * 0.001) * amplitude
    # Cloud cover
    clouds = :math.sin(i * 0.005) * amplitude * 0.3
    noise = (:rand.uniform() - 0.5) * 30
    max(0, Float.round(midpoint + diurnal - clouds + noise, 0))
  end

  # ===========================================
  # AI/INFERENCE SENSORS (YOLOfish style)
  # ===========================================

  # Fish count from detection
  defp generate_value("fish_count", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0, 20)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Schools passing through
    school_event = :math.sin(i * 0.01) * range * 0.5
    # Random appearances
    random_fish = :rand.uniform() * range * 0.3
    noise = (:rand.uniform() - 0.5) * 2
    max(0, trunc(base + school_event + random_fish + noise))
  end

  # Species diversity index (Shannon index style)
  defp generate_value("species_diversity", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 1.5, 3.5)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Slow variation based on time of day
    diurnal = :math.sin(i * 0.001) * range * 0.3
    noise = (:rand.uniform() - 0.5) * 0.2
    Float.round(base + diurnal + noise, 2)
  end

  # Coral coverage percentage
  defp generate_value("coral_coverage", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 25, 65)
    base = (min_val + max_val) / 2
    # Very slow change (restoration progress)
    trend = i * 0.0001
    # Detection noise
    noise = (:rand.uniform() - 0.5) * 3
    Float.round(min(max_val, max(min_val, base + trend + noise)), 1)
  end

  # Bleaching index percentage
  defp generate_value("bleaching_index", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0, 15)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Seasonal/temperature correlation
    temp_effect = :math.sin(i * 0.0005) * range * 0.4
    noise = (:rand.uniform() - 0.5) * 1.5
    max(0, Float.round(base + temp_effect + noise, 1))
  end

  # Algae coverage percentage
  defp generate_value("algae_coverage", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 5, 20)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Nutrient-driven growth cycles
    growth = :math.sin(i * 0.0003) * range * 0.4
    noise = (:rand.uniform() - 0.5) * 2
    max(0, Float.round(base + growth + noise, 1))
  end

  # Inference confidence
  defp generate_value("inference_confidence", config, i, _sampling_rate) do
    {min_val, max_val} = get_min_max(config, 0.75, 0.98)
    base = (min_val + max_val) / 2
    range = (max_val - min_val) / 2
    # Visibility affects confidence
    visibility_effect = :math.sin(i * 0.002) * range * 0.3
    noise = (:rand.uniform() - 0.5) * 0.05
    min(1.0, max(0.5, Float.round(base + visibility_effect + noise, 3)))
  end

  # Respiration fallback for dummy_data path (simple sine wave)
  # Primary respiration uses NeuroKit2 via fetch_respiration_data/1
  defp generate_value("respiration", config, i, sampling_rate) do
    brpm = config[:breaths_per_minute] || 15
    rate = max(sampling_rate, 0.1)
    freq = brpm / 60.0
    t = i / rate
    sensor_id = config[:sensor_id] || "default"
    phase_offset = :erlang.phash2(sensor_id, 10000) / 10000.0 * 2 * :math.pi()
    value = 75.0 + 25.0 * :math.sin(2 * :math.pi() * freq * t + phase_offset)
    noise = (:rand.uniform() - 0.5) * 1.5
    Float.round(value + noise, 1)
  end

  # Eye blink detection (0.0 = not blinking, 1.0 = blinking)
  # Uses same deterministic timing as eye_aperture for correlation
  defp generate_value("eye_blink", config, i, sampling_rate) do
    sensor_id = config[:sensor_id] || "default"
    blink_seed = :erlang.phash2(sensor_id, 1000)
    timestamp_ms = :os.system_time(:millisecond) + trunc(i / max(sampling_rate, 1) * 1000)

    if blink_phase(timestamp_ms, blink_seed) > 0.0, do: 1.0, else: 0.0
  end

  # Eye worn detection (1.0 = worn, 0.0 = not worn)
  # Mostly worn with occasional brief off periods (~15s off every ~300s)
  # Per-sensor phase offset so not all sensors go unworn simultaneously
  defp generate_value("eye_worn", config, _i, _sampling_rate) do
    sensor_id = config[:sensor_id] || "default"
    phase_offset = :erlang.phash2(sensor_id, 300)
    time_seconds = System.system_time(:second)
    cycle_position = rem(time_seconds + phase_offset, 300)

    if cycle_position < 15, do: 0.0, else: 1.0
  end

  # Buttplug vibrate/oscillate — smooth wave pattern (0.0–1.0)
  defp generate_value("buttplug_vibrate", _config, i, _sampling_rate) do
    # Slow sine wave with gentle randomness, clamped to 0.0–1.0
    base = (:math.sin(i * 0.05) + 1) / 2
    noise = (:rand.uniform() - 0.5) * 0.1
    Float.round(max(0.0, min(1.0, base + noise)), 3)
  end

  # Buttplug linear position — smooth back-and-forth (0.0–1.0)
  defp generate_value("buttplug_linear", _config, i, _sampling_rate) do
    # Triangle wave for linear stroking motion
    cycle = rem(i, 100) / 100.0
    position = if cycle < 0.5, do: cycle * 2, else: 2.0 - cycle * 2
    noise = (:rand.uniform() - 0.5) * 0.05
    Float.round(max(0.0, min(1.0, position + noise)), 3)
  end

  # Buttplug device status — always connected
  defp generate_value("buttplug_status", _config, _i, _sampling_rate) do
    1.0
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

  # Helper to extract min/max from config
  defp get_min_max(config, default_min, default_max) do
    min_val = config[:min_value] || default_min
    max_val = config[:max_value] || default_max
    {min_val, max_val}
  end
end
