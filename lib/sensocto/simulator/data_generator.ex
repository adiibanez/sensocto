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
      # Skeleton uses motion capture style animation
      cond do
        sensor_type == "battery" ->
          {:ok, fetch_battery_data(config)}

        sensor_type == "geolocation" ->
          {:ok, fetch_geolocation_data(config)}

        sensor_type in ["skeleton", "pose", "pose_skeleton"] ->
          {:ok, fetch_skeleton_data(config)}

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

  defp get_skeleton_state(sensor_id, motion_type) do
    try do
      case :ets.lookup(@skeleton_states_table, sensor_id) do
        [{^sensor_id, state}] -> state
        [] -> init_skeleton_state(sensor_id, motion_type)
      end
    rescue
      ArgumentError ->
        :ets.new(@skeleton_states_table, [:named_table, :public, :set])
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

  # Generate 33 MediaPipe pose landmarks with realistic motion
  # Landmarks: 0-10 face, 11-12 shoulders, 13-14 elbows, 15-16 wrists,
  # 17-22 hands, 23-24 hips, 25-26 knees, 27-28 ankles, 29-32 feet
  defp generate_skeleton_landmarks(state, time, motion_type) do
    phase = state.phase
    speed = state.speed_factor

    # Base standing pose (normalized 0-1 coordinates, facing camera)
    base_pose = get_base_pose()

    # Apply motion based on type
    animated_pose =
      case motion_type do
        :idle -> apply_idle_motion(base_pose, time, phase, speed)
        :walking -> apply_walking_motion(base_pose, time, phase, speed)
        :waving -> apply_waving_motion(base_pose, time, phase, speed)
        :jumping -> apply_jumping_motion(base_pose, time, phase, speed)
        :dancing -> apply_dancing_motion(base_pose, time, phase, speed)
        :exercise -> apply_exercise_motion(base_pose, time, phase, speed)
        _ -> apply_idle_motion(base_pose, time, phase, speed)
      end

    # Add slight noise for realism
    add_tracking_noise(animated_pose)
  end

  # Base standing T-pose (normalized coordinates)
  defp get_base_pose do
    [
      # Face (0-10)
      %{x: 0.5, y: 0.12, v: 0.99},
      # 0: nose
      %{x: 0.48, y: 0.10, v: 0.95},
      # 1: left eye inner
      %{x: 0.47, y: 0.10, v: 0.95},
      # 2: left eye
      %{x: 0.46, y: 0.10, v: 0.95},
      # 3: left eye outer
      %{x: 0.52, y: 0.10, v: 0.95},
      # 4: right eye inner
      %{x: 0.53, y: 0.10, v: 0.95},
      # 5: right eye
      %{x: 0.54, y: 0.10, v: 0.95},
      # 6: right eye outer
      %{x: 0.44, y: 0.11, v: 0.90},
      # 7: left ear
      %{x: 0.56, y: 0.11, v: 0.90},
      # 8: right ear
      %{x: 0.49, y: 0.14, v: 0.95},
      # 9: mouth left
      %{x: 0.51, y: 0.14, v: 0.95},
      # 10: mouth right
      # Upper body (11-16)
      %{x: 0.40, y: 0.22, v: 0.99},
      # 11: left shoulder
      %{x: 0.60, y: 0.22, v: 0.99},
      # 12: right shoulder
      %{x: 0.35, y: 0.35, v: 0.95},
      # 13: left elbow
      %{x: 0.65, y: 0.35, v: 0.95},
      # 14: right elbow
      %{x: 0.32, y: 0.48, v: 0.90},
      # 15: left wrist
      %{x: 0.68, y: 0.48, v: 0.90},
      # 16: right wrist
      # Hands (17-22)
      %{x: 0.30, y: 0.50, v: 0.85},
      # 17: left pinky
      %{x: 0.70, y: 0.50, v: 0.85},
      # 18: right pinky
      %{x: 0.31, y: 0.51, v: 0.85},
      # 19: left index
      %{x: 0.69, y: 0.51, v: 0.85},
      # 20: right index
      %{x: 0.30, y: 0.49, v: 0.85},
      # 21: left thumb
      %{x: 0.70, y: 0.49, v: 0.85},
      # 22: right thumb
      # Lower body (23-28)
      %{x: 0.45, y: 0.52, v: 0.99},
      # 23: left hip
      %{x: 0.55, y: 0.52, v: 0.99},
      # 24: right hip
      %{x: 0.44, y: 0.72, v: 0.95},
      # 25: left knee
      %{x: 0.56, y: 0.72, v: 0.95},
      # 26: right knee
      %{x: 0.43, y: 0.92, v: 0.90},
      # 27: left ankle
      %{x: 0.57, y: 0.92, v: 0.90},
      # 28: right ankle
      # Feet (29-32)
      %{x: 0.42, y: 0.95, v: 0.85},
      # 29: left heel
      %{x: 0.58, y: 0.95, v: 0.85},
      # 30: right heel
      %{x: 0.41, y: 0.97, v: 0.80},
      # 31: left foot index
      %{x: 0.59, y: 0.97, v: 0.80}
      # 32: right foot index
    ]
  end

  # Idle breathing and subtle sway
  defp apply_idle_motion(pose, time, phase, speed) do
    breath = :math.sin(time * 0.5 * speed + phase) * 0.005
    sway = :math.sin(time * 0.3 * speed + phase) * 0.008

    Enum.with_index(pose)
    |> Enum.map(fn {lm, idx} ->
      cond do
        # Upper body breathing
        idx in [11, 12, 13, 14, 15, 16] ->
          %{lm | y: lm.y + breath, x: lm.x + sway * 0.5}

        # Head subtle movement
        idx in 0..10 ->
          %{lm | y: lm.y + breath * 0.5, x: lm.x + sway * 0.3}

        true ->
          lm
      end
    end)
  end

  # Walking cycle animation
  defp apply_walking_motion(pose, time, phase, speed) do
    cycle = time * 2.0 * speed + phase
    step_phase = :math.sin(cycle)
    arm_swing = :math.sin(cycle) * 0.08
    leg_swing = :math.sin(cycle) * 0.06
    bounce = abs(:math.sin(cycle)) * 0.015

    Enum.with_index(pose)
    |> Enum.map(fn {lm, idx} ->
      case idx do
        # Left arm swings opposite to left leg
        13 -> %{lm | y: lm.y + arm_swing * 0.5}
        15 -> %{lm | y: lm.y + arm_swing}
        # Right arm
        14 -> %{lm | y: lm.y - arm_swing * 0.5}
        16 -> %{lm | y: lm.y - arm_swing}
        # Left leg
        25 -> %{lm | y: lm.y + leg_swing * 0.5 - bounce, x: lm.x + step_phase * 0.02}
        27 -> %{lm | y: lm.y + leg_swing - bounce * 2, x: lm.x + step_phase * 0.03}
        # Right leg
        26 -> %{lm | y: lm.y - leg_swing * 0.5 - bounce, x: lm.x - step_phase * 0.02}
        28 -> %{lm | y: lm.y - leg_swing - bounce * 2, x: lm.x - step_phase * 0.03}
        # Body bounce
        _ when idx in 0..16 -> %{lm | y: lm.y - bounce}
        _ -> lm
      end
    end)
  end

  # Waving hand animation
  defp apply_waving_motion(pose, time, phase, speed) do
    wave = :math.sin(time * 4.0 * speed + phase)
    breath = :math.sin(time * 0.5 * speed + phase) * 0.005

    Enum.with_index(pose)
    |> Enum.map(fn {lm, idx} ->
      case idx do
        # Right arm raised and waving
        14 -> %{lm | x: lm.x + 0.05, y: 0.15 + wave * 0.03}
        16 -> %{lm | x: lm.x + 0.10, y: 0.08 + wave * 0.05}
        18 -> %{lm | x: lm.x + 0.12, y: 0.05 + wave * 0.06}
        20 -> %{lm | x: lm.x + 0.12, y: 0.05 + wave * 0.06}
        22 -> %{lm | x: lm.x + 0.11, y: 0.06 + wave * 0.05}
        # Subtle body movement
        _ when idx in 0..16 -> %{lm | y: lm.y + breath}
        _ -> lm
      end
    end)
  end

  # Jumping animation
  defp apply_jumping_motion(pose, time, phase, speed) do
    cycle = time * 1.5 * speed + phase
    jump_phase = rem(trunc(cycle), 4)
    progress = cycle - trunc(cycle)

    # Jump height based on phase
    jump_height =
      case jump_phase do
        0 -> -progress * 0.02
        1 -> -0.02 - :math.sin(progress * :math.pi()) * 0.15
        2 -> -0.02 - (1 - progress) * 0.02
        _ -> 0
      end

    # Arms up during jump
    arms_up =
      case jump_phase do
        1 -> :math.sin(progress * :math.pi()) * 0.15
        _ -> 0
      end

    Enum.with_index(pose)
    |> Enum.map(fn {lm, idx} ->
      base = %{lm | y: lm.y + jump_height}

      case idx do
        # Arms raise during jump
        13 -> %{base | y: base.y - arms_up * 0.5}
        14 -> %{base | y: base.y - arms_up * 0.5}
        15 -> %{base | y: base.y - arms_up}
        16 -> %{base | y: base.y - arms_up}
        # Knees bend on landing
        25 when jump_phase == 3 -> %{base | y: base.y + progress * 0.03}
        26 when jump_phase == 3 -> %{base | y: base.y + progress * 0.03}
        _ -> base
      end
    end)
  end

  # Dancing animation with more complex movement
  defp apply_dancing_motion(pose, time, phase, speed) do
    beat = time * 2.0 * speed + phase
    bounce = abs(:math.sin(beat * 2)) * 0.02
    hip_sway = :math.sin(beat) * 0.03
    arm_groove = :math.sin(beat * 2) * 0.06

    Enum.with_index(pose)
    |> Enum.map(fn {lm, idx} ->
      case idx do
        # Hip sway
        23 -> %{lm | x: lm.x + hip_sway, y: lm.y - bounce}
        24 -> %{lm | x: lm.x + hip_sway, y: lm.y - bounce}
        # Arms grooving
        13 -> %{lm | x: lm.x - arm_groove * 0.5, y: lm.y - bounce + abs(arm_groove) * 0.3}
        14 -> %{lm | x: lm.x + arm_groove * 0.5, y: lm.y - bounce + abs(arm_groove) * 0.3}
        15 -> %{lm | x: lm.x - arm_groove, y: lm.y - bounce * 2 + abs(arm_groove) * 0.5}
        16 -> %{lm | x: lm.x + arm_groove, y: lm.y - bounce * 2 + abs(arm_groove) * 0.5}
        # Head bobbing
        _ when idx in 0..10 -> %{lm | y: lm.y - bounce * 1.5, x: lm.x + hip_sway * 0.5}
        # Body bounce
        _ when idx in 11..22 -> %{lm | y: lm.y - bounce, x: lm.x + hip_sway * 0.3}
        _ -> lm
      end
    end)
  end

  # Exercise/workout animation (squats, arm raises)
  defp apply_exercise_motion(pose, time, phase, speed) do
    cycle = time * 0.8 * speed + phase
    exercise_phase = rem(trunc(cycle), 3)
    progress = :math.sin((cycle - trunc(cycle)) * :math.pi())

    case exercise_phase do
      # Squat
      0 ->
        squat_depth = progress * 0.12

        Enum.with_index(pose)
        |> Enum.map(fn {lm, idx} ->
          case idx do
            # Knees bend
            25 -> %{lm | y: lm.y + squat_depth * 0.6, x: lm.x - 0.02}
            26 -> %{lm | y: lm.y + squat_depth * 0.6, x: lm.x + 0.02}
            # Hips lower
            23 -> %{lm | y: lm.y + squat_depth}
            24 -> %{lm | y: lm.y + squat_depth}
            # Upper body lowers
            _ when idx in 0..22 -> %{lm | y: lm.y + squat_depth * 0.8}
            _ -> lm
          end
        end)

      # Arm raises
      1 ->
        arm_height = progress * 0.25

        Enum.with_index(pose)
        |> Enum.map(fn {lm, idx} ->
          case idx do
            13 -> %{lm | y: lm.y - arm_height * 0.5}
            14 -> %{lm | y: lm.y - arm_height * 0.5}
            15 -> %{lm | y: lm.y - arm_height, x: lm.x - 0.05}
            16 -> %{lm | y: lm.y - arm_height, x: lm.x + 0.05}
            _ -> lm
          end
        end)

      # Side stretch
      _ ->
        stretch = progress * 0.08
        side = if rem(trunc(cycle / 3), 2) == 0, do: 1, else: -1

        Enum.with_index(pose)
        |> Enum.map(fn {lm, idx} ->
          case idx do
            # Arm over head
            15 when side > 0 -> %{lm | y: lm.y - 0.35, x: lm.x + stretch}
            16 when side < 0 -> %{lm | y: lm.y - 0.35, x: lm.x - stretch}
            # Body lean
            _ when idx in 0..22 -> %{lm | x: lm.x + stretch * side * 0.3}
            _ -> lm
          end
        end)
    end
  end

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
