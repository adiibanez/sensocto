defmodule Sensocto.Simulator.TrackPlayer do
  @moduledoc """
  Replays GPS tracks for realistic location simulation.

  Maintains playback state per sensor and interpolates between waypoints
  for smooth movement at configurable playback speeds.

  Features:
  - Smooth interpolation between waypoints
  - Configurable playback speed (1x, 2x, 10x, etc.)
  - Loop mode for continuous playback
  - Random start position within track
  - Support for multiple sensors on different tracks
  """

  use GenServer
  require Logger

  alias Sensocto.Simulator.GpsTracks
  alias Sensocto.Sensors.SimulatorTrackPosition

  # Delay hydration to allow HTTP server to start first (improves Fly.io routing)
  @hydration_delay_ms 6_000
  @sync_interval_ms 30_000

  @type player_state :: %{
          track: GpsTracks.track(),
          current_time_s: float(),
          playback_speed: float(),
          loop: boolean(),
          started_at: integer(),
          last_position: map() | nil
        }

  # Client API

  @doc """
  Starts the TrackPlayer server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts playback for a sensor with a specific track or mode.

  Options:
  - :track_name - specific track name (e.g., "berlin_walk")
  - :mode - transport mode to pick random track (e.g., :walk, :car, :bird)
  - :playback_speed - speed multiplier (default 1.0)
  - :loop - whether to loop the track (default true)
  - :random_start - start at random position in track (default false)
  - :generate - generate a new procedural track (default false)
  - :start_lat / :start_lng - for generated tracks
  - :duration_minutes - for generated tracks
  """
  @spec start_playback(String.t(), keyword()) :: :ok | {:error, term()}
  def start_playback(sensor_id, opts \\ []) do
    GenServer.call(__MODULE__, {:start_playback, sensor_id, opts})
  end

  @doc """
  Stops playback for a sensor.
  """
  @spec stop_playback(String.t()) :: :ok
  def stop_playback(sensor_id) do
    GenServer.call(__MODULE__, {:stop_playback, sensor_id})
  end

  @doc """
  Gets the current position for a sensor.
  Returns {:ok, position} or {:error, :not_playing}.
  """
  @spec get_position(String.t()) :: {:ok, map()} | {:error, :not_playing}
  def get_position(sensor_id) do
    GenServer.call(__MODULE__, {:get_position, sensor_id})
  end

  @doc """
  Gets the current position, advancing playback time.
  This is called by the data generator to get the next position.
  """
  @spec tick(String.t()) :: {:ok, map()} | {:error, :not_playing}
  def tick(sensor_id) do
    GenServer.call(__MODULE__, {:tick, sensor_id})
  end

  @doc """
  Sets playback speed for a sensor.
  """
  @spec set_speed(String.t(), float()) :: :ok | {:error, :not_playing}
  def set_speed(sensor_id, speed) do
    GenServer.call(__MODULE__, {:set_speed, sensor_id, speed})
  end

  @doc """
  Lists all currently playing sensors.
  """
  @spec list_playing() :: [String.t()]
  def list_playing do
    GenServer.call(__MODULE__, :list_playing)
  end

  @doc """
  Gets playback status for a sensor.
  """
  @spec get_status(String.t()) :: {:ok, map()} | {:error, :not_playing}
  def get_status(sensor_id) do
    GenServer.call(__MODULE__, {:get_status, sensor_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule hydration from PostgreSQL
    Process.send_after(self(), :hydrate_from_postgres, @hydration_delay_ms)
    # Schedule periodic sync
    Process.send_after(self(), :sync_positions, @sync_interval_ms)

    {:ok, %{players: %{}}}
  end

  @impl true
  def handle_call({:start_playback, sensor_id, opts}, _from, state) do
    case resolve_track(opts) do
      {:ok, track} ->
        playback_speed = Keyword.get(opts, :playback_speed, 1.0)
        loop = Keyword.get(opts, :loop, true)
        random_start = Keyword.get(opts, :random_start, false)

        # Calculate starting time
        start_time_s =
          if random_start do
            max_time = List.last(track.waypoints).timestamp_offset_s
            :rand.uniform() * max_time
          else
            0.0
          end

        player = %{
          track: track,
          current_time_s: start_time_s,
          playback_speed: playback_speed,
          loop: loop,
          started_at: System.monotonic_time(:millisecond),
          last_tick_at: System.monotonic_time(:millisecond),
          last_position: nil
        }

        new_state = put_in(state, [:players, sensor_id], player)

        Logger.debug(
          "[TrackPlayer] Started playback for #{sensor_id}: #{track.name} (#{track.mode})"
        )

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop_playback, sensor_id}, _from, state) do
    new_state = update_in(state, [:players], &Map.delete(&1, sensor_id))
    Logger.debug("[TrackPlayer] Stopped playback for #{sensor_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_position, sensor_id}, _from, state) do
    case Map.get(state.players, sensor_id) do
      nil ->
        {:reply, {:error, :not_playing}, state}

      player ->
        position = interpolate_position(player)
        {:reply, {:ok, position}, state}
    end
  end

  @impl true
  def handle_call({:tick, sensor_id}, _from, state) do
    case Map.get(state.players, sensor_id) do
      nil ->
        {:reply, {:error, :not_playing}, state}

      player ->
        # Calculate elapsed time since last tick
        now = System.monotonic_time(:millisecond)
        elapsed_ms = now - player.last_tick_at
        elapsed_s = elapsed_ms / 1000.0

        # Advance playback time
        new_time = player.current_time_s + elapsed_s * player.playback_speed

        # Handle looping or clamping
        track_duration = List.last(player.track.waypoints).timestamp_offset_s

        new_time =
          cond do
            new_time >= track_duration and player.loop ->
              rem_float(new_time, track_duration)

            new_time >= track_duration ->
              track_duration

            true ->
              new_time
          end

        updated_player = %{player | current_time_s: new_time, last_tick_at: now}

        position = interpolate_position(updated_player)
        updated_player = %{updated_player | last_position: position}

        new_state = put_in(state, [:players, sensor_id], updated_player)
        {:reply, {:ok, position}, new_state}
    end
  end

  @impl true
  def handle_call({:set_speed, sensor_id, speed}, _from, state) do
    case Map.get(state.players, sensor_id) do
      nil ->
        {:reply, {:error, :not_playing}, state}

      player ->
        updated_player = %{player | playback_speed: speed}
        new_state = put_in(state, [:players, sensor_id], updated_player)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_playing, _from, state) do
    {:reply, Map.keys(state.players), state}
  end

  @impl true
  def handle_call({:get_status, sensor_id}, _from, state) do
    case Map.get(state.players, sensor_id) do
      nil ->
        {:reply, {:error, :not_playing}, state}

      player ->
        track_duration = List.last(player.track.waypoints).timestamp_offset_s
        progress = player.current_time_s / track_duration * 100

        status = %{
          track_name: player.track.name,
          mode: player.track.mode,
          current_time_s: player.current_time_s,
          track_duration_s: track_duration,
          progress_percent: Float.round(progress, 1),
          playback_speed: player.playback_speed,
          loop: player.loop,
          last_position: player.last_position
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_info(:hydrate_from_postgres, state) do
    Logger.debug("[TrackPlayer] Hydrating track positions from PostgreSQL...")

    # Run database query in a task to avoid blocking GenServer
    Task.Supervisor.start_child(
      Sensocto.Simulator.DbTaskSupervisor,
      fn ->
        result = load_positions_from_db()
        send(__MODULE__, {:hydration_result, result})
      end
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:hydration_result, {:ok, positions}}, state) when positions != [] do
    Logger.info("[TrackPlayer] Found #{length(positions)} track positions to restore")
    new_state = restore_positions(state, positions)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hydration_result, {:ok, []}}, state) do
    Logger.debug("[TrackPlayer] No track positions to restore")
    {:noreply, state}
  end

  @impl true
  def handle_info({:hydration_result, {:error, reason}}, state) do
    Logger.warning("[TrackPlayer] Failed to hydrate: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_positions, state) do
    # Schedule next sync
    Process.send_after(self(), :sync_positions, @sync_interval_ms)

    # Sync all positions asynchronously via rate-limited task supervisor
    if map_size(state.players) > 0 do
      Task.Supervisor.start_child(
        Sensocto.Simulator.DbTaskSupervisor,
        fn -> sync_positions_to_postgres(state.players) end
      )
    end

    {:noreply, state}
  end

  # Private Functions

  defp resolve_track(opts) do
    cond do
      Keyword.get(opts, :generate, false) ->
        mode = Keyword.get(opts, :mode, :walk)
        {:ok, GpsTracks.generate_track(mode, opts)}

      track_name = Keyword.get(opts, :track_name) ->
        GpsTracks.get_track(track_name)

      # Stationary mode always generates a track at the specified location
      Keyword.get(opts, :mode) == :stationary ->
        {:ok, GpsTracks.generate_track(:stationary, opts)}

      # If start coordinates are provided, generate a track at that location
      Keyword.has_key?(opts, :start_lat) and Keyword.has_key?(opts, :start_lng) ->
        mode = Keyword.get(opts, :mode, :walk)
        {:ok, GpsTracks.generate_track(mode, opts)}

      mode = Keyword.get(opts, :mode) ->
        GpsTracks.get_random_track(mode)

      true ->
        {:ok, GpsTracks.get_random_track()}
    end
  end

  defp interpolate_position(player) do
    %{track: track, current_time_s: current_time} = player
    waypoints = track.waypoints

    # Find the two waypoints we're between
    {prev_wp, next_wp, t} = find_segment(waypoints, current_time)

    # Linear interpolation
    lat = lerp(prev_wp.lat, next_wp.lat, t)
    lng = lerp(prev_wp.lng, next_wp.lng, t)
    alt = lerp(prev_wp.alt || 0.0, next_wp.alt || 0.0, t)

    # Calculate current speed (distance / time between waypoints)
    dt = next_wp.timestamp_offset_s - prev_wp.timestamp_offset_s
    distance = haversine_distance(prev_wp.lat, prev_wp.lng, next_wp.lat, next_wp.lng)
    speed_ms = if dt > 0, do: distance / dt, else: 0.0

    # Calculate heading
    heading = calculate_heading(prev_wp.lat, prev_wp.lng, next_wp.lat, next_wp.lng)

    %{
      latitude: Float.round(lat, 6),
      longitude: Float.round(lng, 6),
      altitude: Float.round(alt, 1),
      speed: Float.round(speed_ms, 2),
      heading: Float.round(heading, 1),
      # Simulated accuracy
      accuracy: 5.0,
      mode: track.mode,
      track_name: track.name
    }
  end

  defp find_segment(waypoints, current_time) do
    # Find the segment containing current_time
    case Enum.find_index(waypoints, fn wp -> wp.timestamp_offset_s > current_time end) do
      nil ->
        # Past the end - use last waypoint
        last = List.last(waypoints)
        {last, last, 0.0}

      0 ->
        # Before first waypoint
        first = List.first(waypoints)
        {first, first, 0.0}

      idx ->
        prev_wp = Enum.at(waypoints, idx - 1)
        next_wp = Enum.at(waypoints, idx)

        # Calculate interpolation factor (0.0 to 1.0)
        segment_duration = next_wp.timestamp_offset_s - prev_wp.timestamp_offset_s
        time_into_segment = current_time - prev_wp.timestamp_offset_s
        t = if segment_duration > 0, do: time_into_segment / segment_duration, else: 0.0

        {prev_wp, next_wp, t}
    end
  end

  defp lerp(a, b, t), do: a + (b - a) * t

  defp rem_float(a, b), do: a - Float.floor(a / b) * b

  defp haversine_distance(lat1, lng1, lat2, lng2) do
    # Earth radius in meters
    r = 6_371_000

    dlat = (lat2 - lat1) * :math.pi() / 180
    dlng = (lng2 - lng1) * :math.pi() / 180

    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    r * c
  end

  defp calculate_heading(lat1, lng1, lat2, lng2) do
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    dlng = (lng2 - lng1) * :math.pi() / 180

    x = :math.sin(dlng) * :math.cos(lat2_rad)

    y =
      :math.cos(lat1_rad) * :math.sin(lat2_rad) -
        :math.sin(lat1_rad) * :math.cos(lat2_rad) * :math.cos(dlng)

    heading_rad = :math.atan2(x, y)
    heading_deg = heading_rad * 180 / :math.pi()

    # Normalize to 0-360
    if heading_deg < 0, do: heading_deg + 360, else: heading_deg
  end

  # PostgreSQL Persistence Functions

  defp load_positions_from_db do
    try do
      positions =
        SimulatorTrackPosition
        |> Ash.Query.for_read(:all)
        |> Ash.read!()

      {:ok, positions}
    rescue
      e -> {:error, e}
    end
  end

  defp restore_positions(state, positions) do
    Enum.reduce(positions, state, fn pos, acc ->
      # Only restore if the sensor is already playing (started by Manager hydration)
      case Map.get(acc.players, pos.sensor_id) do
        nil ->
          # Sensor not playing, skip
          acc

        player ->
          # Restore the current time position
          updated_player = %{player | current_time_s: pos.current_time_s || 0.0}

          Logger.debug(
            "[TrackPlayer] Restored position for #{pos.sensor_id}: #{pos.current_time_s}s"
          )

          put_in(acc, [:players, pos.sensor_id], updated_player)
      end
    end)
  end

  defp sync_positions_to_postgres(players) do
    try do
      Enum.each(players, fn {sensor_id, player} ->
        last_position =
          if player.last_position do
            %{
              "latitude" => player.last_position[:latitude],
              "longitude" => player.last_position[:longitude],
              "altitude" => player.last_position[:altitude],
              "speed" => player.last_position[:speed],
              "heading" => player.last_position[:heading]
            }
          else
            %{}
          end

        # Upsert the position
        case SimulatorTrackPosition
             |> Ash.Query.for_read(:by_sensor, %{sensor_id: sensor_id})
             |> Ash.read_one() do
          {:ok, nil} ->
            # Position record doesn't exist yet - it should be created when connector syncs
            :ok

          {:ok, existing} ->
            # Update position
            existing
            |> Ash.Changeset.for_update(:sync_position, %{
              current_time_s: player.current_time_s,
              playback_speed: player.playback_speed,
              loop: player.loop,
              last_position: last_position
            })
            |> Ash.update()

          {:error, _} ->
            :ok
        end
      end)
    rescue
      e ->
        Logger.warning("[TrackPlayer] Exception syncing positions: #{inspect(e)}")
    end
  end
end
