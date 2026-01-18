defmodule Sensocto.Simulator.GpsTracks do
  @moduledoc """
  Embedded GPS track data for realistic location simulation.

  Contains sample tracks for different transport modes:
  - Walking/hiking
  - Cycling
  - Driving (car)
  - Train/transit
  - Animal migration patterns
  - Flight paths

  Each track is a list of waypoints with lat, lng, altitude, and metadata.
  Tracks are normalized to be replayable at configurable speeds.
  """

  @type waypoint :: %{
          lat: float(),
          lng: float(),
          alt: float() | nil,
          timestamp_offset_s: float()
        }

  @type track :: %{
          name: String.t(),
          mode: atom(),
          waypoints: [waypoint()],
          avg_speed_kmh: float(),
          total_distance_km: float(),
          duration_minutes: float()
        }

  @doc """
  Lists available track names.
  """
  @spec list_tracks() :: [String.t()]
  def list_tracks do
    [
      "berlin_walk",
      "berlin_cycle",
      "autobahn_drive",
      "ice_train",
      "stork_migration",
      "seagull_coastal",
      "drone_survey",
      "ferry_crossing"
    ]
  end

  @doc """
  Lists available transport modes.
  """
  @spec list_modes() :: [atom()]
  def list_modes do
    [:walk, :cycle, :car, :train, :bird, :drone, :boat, :stationary]
  end

  @doc """
  Gets a track by name.
  """
  @spec get_track(String.t()) :: {:ok, track()} | {:error, :not_found}
  def get_track(name) do
    case tracks()[name] do
      nil -> {:error, :not_found}
      track -> {:ok, track}
    end
  end

  @doc """
  Gets a random track for a given mode.
  """
  @spec get_random_track(atom()) :: {:ok, track()} | {:error, :not_found}
  def get_random_track(mode) do
    mode_tracks = Enum.filter(tracks(), fn {_name, track} -> track.mode == mode end)

    case mode_tracks do
      [] -> {:error, :not_found}
      list -> {:ok, elem(Enum.random(list), 1)}
    end
  end

  @doc """
  Gets a random track for any mode.
  """
  @spec get_random_track() :: track()
  def get_random_track do
    tracks()
    |> Map.values()
    |> Enum.random()
  end

  @doc """
  Generates a procedural track based on parameters.
  Useful for creating unique tracks on-the-fly.
  """
  @spec generate_track(atom(), keyword()) :: track()
  def generate_track(mode, opts \\ []) do
    start_lat = Keyword.get(opts, :start_lat, 52.52)
    start_lng = Keyword.get(opts, :start_lng, 13.405)
    duration_minutes = Keyword.get(opts, :duration_minutes, 30)

    # Special handling for stationary mode - just stay at fixed position
    if mode == :stationary do
      generate_stationary_track(start_lat, start_lng, duration_minutes)
    else
      {avg_speed_kmh, step_variation, turn_frequency} = mode_params(mode)

      # Generate waypoints every ~5 seconds for smooth animation
      num_waypoints = trunc(duration_minutes * 60 / 5)
      # Convert to m/s
      speed_ms = avg_speed_kmh / 3.6

      # Random initial heading
      heading = :rand.uniform() * 2 * :math.pi()

      waypoints =
        generate_waypoints(
          start_lat,
          start_lng,
          heading,
          speed_ms,
          step_variation,
          turn_frequency,
          num_waypoints,
          mode
        )

      total_distance = calculate_total_distance(waypoints)

      %{
        name: "generated_#{mode}_#{:rand.uniform(9999)}",
        mode: mode,
        waypoints: waypoints,
        avg_speed_kmh: avg_speed_kmh,
        total_distance_km: total_distance / 1000,
        duration_minutes: duration_minutes
      }
    end
  end

  # Generate a stationary track - stays at fixed position with minor GPS drift
  defp generate_stationary_track(lat, lng, duration_minutes) do
    # Generate waypoints every 60 seconds for stationary sensors (less frequent)
    num_waypoints = max(2, trunc(duration_minutes))

    waypoints =
      Enum.map(0..(num_waypoints - 1), fn i ->
        # Small GPS drift to simulate real sensor behavior (±5m)
        drift_lat = (:rand.uniform() - 0.5) * 0.0001
        drift_lng = (:rand.uniform() - 0.5) * 0.0001

        %{
          lat: lat + drift_lat,
          lng: lng + drift_lng,
          alt: 0.0,
          timestamp_offset_s: i * 60.0
        }
      end)

    %{
      name: "stationary_#{:rand.uniform(9999)}",
      mode: :stationary,
      waypoints: waypoints,
      avg_speed_kmh: 0.0,
      total_distance_km: 0.0,
      duration_minutes: duration_minutes
    }
  end

  # Mode-specific parameters: {avg_speed_kmh, step_variation, turn_frequency}
  defp mode_params(:walk), do: {5.0, 0.1, 0.3}
  defp mode_params(:cycle), do: {20.0, 0.15, 0.2}
  defp mode_params(:car), do: {60.0, 0.2, 0.1}
  defp mode_params(:train), do: {120.0, 0.05, 0.05}
  defp mode_params(:bird), do: {40.0, 0.3, 0.4}
  defp mode_params(:drone), do: {30.0, 0.25, 0.35}
  defp mode_params(:boat), do: {25.0, 0.1, 0.15}
  # Stationary mode - no movement, stays at fixed position
  defp mode_params(:stationary), do: {0.0, 0.0, 0.0}

  defp generate_waypoints(lat, lng, heading, speed_ms, variation, turn_freq, count, mode) do
    {waypoints, _} =
      Enum.reduce(0..(count - 1), {[], {lat, lng, heading, 0.0}}, fn i,
                                                                     {acc,
                                                                      {curr_lat, curr_lng,
                                                                       curr_heading, curr_alt}} ->
        # 5 seconds between waypoints
        timestamp_offset = i * 5.0

        # Speed variation
        actual_speed = speed_ms * (1 + (:rand.uniform() - 0.5) * variation * 2)

        # Gradual heading changes
        heading_change =
          if :rand.uniform() < turn_freq do
            # Up to 45 degree turn
            (:rand.uniform() - 0.5) * :math.pi() / 4
          else
            # Small drift
            (:rand.uniform() - 0.5) * 0.1
          end

        new_heading = curr_heading + heading_change

        # Move in heading direction
        # Distance covered in 5 seconds
        distance_m = actual_speed * 5
        {new_lat, new_lng} = move_point(curr_lat, curr_lng, new_heading, distance_m)

        # Altitude changes based on mode
        new_alt = generate_altitude(mode, curr_alt, i)

        waypoint = %{
          lat: new_lat,
          lng: new_lng,
          alt: new_alt,
          timestamp_offset_s: timestamp_offset
        }

        {[waypoint | acc], {new_lat, new_lng, new_heading, new_alt}}
      end)

    Enum.reverse(waypoints)
  end

  defp generate_altitude(:bird, curr_alt, i) do
    base = if curr_alt == 0.0, do: 100.0, else: curr_alt
    # Thermal soaring pattern
    variation = :math.sin(i * 0.1) * 50 + (:rand.uniform() - 0.5) * 20
    max(20.0, base + variation)
  end

  defp generate_altitude(:drone, curr_alt, i) do
    base = if curr_alt == 0.0, do: 50.0, else: curr_alt
    # Survey pattern - mostly stable with occasional adjustments
    if :rand.uniform() < 0.1 do
      base + (:rand.uniform() - 0.5) * 30
    else
      base + :math.sin(i * 0.05) * 5
    end
  end

  defp generate_altitude(:walk, curr_alt, i) do
    base = if curr_alt == 0.0, do: 50.0, else: curr_alt
    # Gentle terrain variations
    base + :math.sin(i * 0.02) * 10 + (:rand.uniform() - 0.5) * 2
  end

  defp generate_altitude(:cycle, curr_alt, i) do
    base = if curr_alt == 0.0, do: 30.0, else: curr_alt
    # Hill climbing patterns
    base + :math.sin(i * 0.03) * 20 + (:rand.uniform() - 0.5) * 3
  end

  defp generate_altitude(_mode, curr_alt, _i) do
    if curr_alt == 0.0, do: 10.0, else: curr_alt + (:rand.uniform() - 0.5) * 2
  end

  # Move a point by distance in heading direction
  defp move_point(lat, lng, heading, distance_m) do
    # Earth radius in meters
    r = 6_371_000

    lat_rad = lat * :math.pi() / 180
    lng_rad = lng * :math.pi() / 180

    # Calculate new position
    angular_distance = distance_m / r

    new_lat_rad =
      :math.asin(
        :math.sin(lat_rad) * :math.cos(angular_distance) +
          :math.cos(lat_rad) * :math.sin(angular_distance) * :math.cos(heading)
      )

    new_lng_rad =
      lng_rad +
        :math.atan2(
          :math.sin(heading) * :math.sin(angular_distance) * :math.cos(lat_rad),
          :math.cos(angular_distance) - :math.sin(lat_rad) * :math.sin(new_lat_rad)
        )

    new_lat = new_lat_rad * 180 / :math.pi()
    new_lng = new_lng_rad * 180 / :math.pi()

    {Float.round(new_lat, 6), Float.round(new_lng, 6)}
  end

  defp calculate_total_distance(waypoints) do
    waypoints
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [w1, w2], acc ->
      acc + haversine_distance(w1.lat, w1.lng, w2.lat, w2.lng)
    end)
  end

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

  # Embedded track data
  defp tracks do
    %{
      # Berlin Tiergarten walking tour (~3km, ~40 min)
      "berlin_walk" => %{
        name: "Berlin Tiergarten Walk",
        mode: :walk,
        avg_speed_kmh: 4.5,
        total_distance_km: 3.0,
        duration_minutes: 40,
        waypoints: [
          %{lat: 52.5145, lng: 13.3501, alt: 35.0, timestamp_offset_s: 0.0},
          %{lat: 52.5148, lng: 13.3520, alt: 35.5, timestamp_offset_s: 30.0},
          %{lat: 52.5152, lng: 13.3545, alt: 36.0, timestamp_offset_s: 60.0},
          %{lat: 52.5158, lng: 13.3568, alt: 35.8, timestamp_offset_s: 90.0},
          %{lat: 52.5163, lng: 13.3590, alt: 36.2, timestamp_offset_s: 120.0},
          %{lat: 52.5170, lng: 13.3615, alt: 37.0, timestamp_offset_s: 150.0},
          %{lat: 52.5175, lng: 13.3640, alt: 37.5, timestamp_offset_s: 180.0},
          %{lat: 52.5180, lng: 13.3668, alt: 38.0, timestamp_offset_s: 210.0},
          %{lat: 52.5183, lng: 13.3695, alt: 37.8, timestamp_offset_s: 240.0},
          %{lat: 52.5188, lng: 13.3720, alt: 37.2, timestamp_offset_s: 270.0},
          %{lat: 52.5192, lng: 13.3745, alt: 36.5, timestamp_offset_s: 300.0},
          %{lat: 52.5198, lng: 13.3770, alt: 36.0, timestamp_offset_s: 330.0},
          %{lat: 52.5205, lng: 13.3798, alt: 35.5, timestamp_offset_s: 360.0},
          %{lat: 52.5212, lng: 13.3825, alt: 35.0, timestamp_offset_s: 390.0},
          %{lat: 52.5218, lng: 13.3850, alt: 34.8, timestamp_offset_s: 420.0},
          %{lat: 52.5225, lng: 13.3878, alt: 35.2, timestamp_offset_s: 450.0},
          %{lat: 52.5230, lng: 13.3905, alt: 35.5, timestamp_offset_s: 480.0},
          %{lat: 52.5235, lng: 13.3932, alt: 36.0, timestamp_offset_s: 510.0},
          %{lat: 52.5240, lng: 13.3960, alt: 36.5, timestamp_offset_s: 540.0},
          %{lat: 52.5245, lng: 13.3985, alt: 37.0, timestamp_offset_s: 570.0}
        ]
      },

      # Berlin cycling route (~8km, ~25 min)
      "berlin_cycle" => %{
        name: "Berlin Cycle Tour",
        mode: :cycle,
        avg_speed_kmh: 19.0,
        total_distance_km: 8.0,
        duration_minutes: 25,
        waypoints: [
          %{lat: 52.5200, lng: 13.4050, alt: 38.0, timestamp_offset_s: 0.0},
          %{lat: 52.5180, lng: 13.4120, alt: 37.5, timestamp_offset_s: 20.0},
          %{lat: 52.5155, lng: 13.4190, alt: 36.8, timestamp_offset_s: 40.0},
          %{lat: 52.5130, lng: 13.4265, alt: 36.0, timestamp_offset_s: 60.0},
          %{lat: 52.5108, lng: 13.4340, alt: 35.5, timestamp_offset_s: 80.0},
          %{lat: 52.5085, lng: 13.4410, alt: 35.0, timestamp_offset_s: 100.0},
          %{lat: 52.5060, lng: 13.4485, alt: 34.5, timestamp_offset_s: 120.0},
          %{lat: 52.5035, lng: 13.4560, alt: 34.0, timestamp_offset_s: 140.0},
          %{lat: 52.5012, lng: 13.4635, alt: 33.5, timestamp_offset_s: 160.0},
          %{lat: 52.4990, lng: 13.4705, alt: 33.0, timestamp_offset_s: 180.0},
          %{lat: 52.4965, lng: 13.4780, alt: 32.8, timestamp_offset_s: 200.0},
          %{lat: 52.4940, lng: 13.4855, alt: 33.2, timestamp_offset_s: 220.0},
          %{lat: 52.4918, lng: 13.4930, alt: 34.0, timestamp_offset_s: 240.0},
          %{lat: 52.4895, lng: 13.5000, alt: 35.0, timestamp_offset_s: 260.0},
          %{lat: 52.4870, lng: 13.5075, alt: 36.0, timestamp_offset_s: 280.0}
        ]
      },

      # German Autobahn drive (~50km, ~30 min)
      "autobahn_drive" => %{
        name: "Autobahn A10 Drive",
        mode: :car,
        avg_speed_kmh: 100.0,
        total_distance_km: 50.0,
        duration_minutes: 30,
        waypoints: [
          %{lat: 52.4500, lng: 13.2800, alt: 45.0, timestamp_offset_s: 0.0},
          %{lat: 52.4380, lng: 13.2550, alt: 48.0, timestamp_offset_s: 30.0},
          %{lat: 52.4250, lng: 13.2280, alt: 52.0, timestamp_offset_s: 60.0},
          %{lat: 52.4110, lng: 13.1990, alt: 55.0, timestamp_offset_s: 90.0},
          %{lat: 52.3960, lng: 13.1680, alt: 58.0, timestamp_offset_s: 120.0},
          %{lat: 52.3800, lng: 13.1350, alt: 62.0, timestamp_offset_s: 150.0},
          %{lat: 52.3630, lng: 13.1000, alt: 65.0, timestamp_offset_s: 180.0},
          %{lat: 52.3450, lng: 13.0630, alt: 68.0, timestamp_offset_s: 210.0},
          %{lat: 52.3260, lng: 13.0240, alt: 70.0, timestamp_offset_s: 240.0},
          %{lat: 52.3060, lng: 12.9830, alt: 72.0, timestamp_offset_s: 270.0},
          %{lat: 52.2850, lng: 12.9400, alt: 75.0, timestamp_offset_s: 300.0},
          %{lat: 52.2630, lng: 12.8950, alt: 78.0, timestamp_offset_s: 330.0},
          %{lat: 52.2400, lng: 12.8480, alt: 80.0, timestamp_offset_s: 360.0},
          %{lat: 52.2160, lng: 12.7990, alt: 82.0, timestamp_offset_s: 390.0},
          %{lat: 52.1910, lng: 12.7480, alt: 85.0, timestamp_offset_s: 420.0}
        ]
      },

      # ICE train Berlin to Hamburg (~280km, ~90 min)
      "ice_train" => %{
        name: "ICE Berlin-Hamburg",
        mode: :train,
        avg_speed_kmh: 190.0,
        total_distance_km: 280.0,
        duration_minutes: 90,
        waypoints: [
          # Berlin Hbf
          %{lat: 52.5251, lng: 13.3694, alt: 35.0, timestamp_offset_s: 0.0},
          %{lat: 52.5420, lng: 13.2890, alt: 38.0, timestamp_offset_s: 60.0},
          %{lat: 52.5680, lng: 13.1850, alt: 42.0, timestamp_offset_s: 120.0},
          %{lat: 52.6100, lng: 13.0600, alt: 45.0, timestamp_offset_s: 180.0},
          %{lat: 52.6650, lng: 12.9100, alt: 48.0, timestamp_offset_s: 240.0},
          %{lat: 52.7350, lng: 12.7300, alt: 50.0, timestamp_offset_s: 300.0},
          %{lat: 52.8200, lng: 12.5200, alt: 52.0, timestamp_offset_s: 360.0},
          %{lat: 52.9200, lng: 12.2800, alt: 48.0, timestamp_offset_s: 420.0},
          %{lat: 53.0350, lng: 12.0100, alt: 45.0, timestamp_offset_s: 480.0},
          %{lat: 53.1650, lng: 11.7100, alt: 42.0, timestamp_offset_s: 540.0},
          %{lat: 53.3100, lng: 11.3800, alt: 38.0, timestamp_offset_s: 600.0},
          %{lat: 53.4700, lng: 11.0200, alt: 35.0, timestamp_offset_s: 660.0},
          # Hamburg Hbf
          %{lat: 53.5511, lng: 10.0065, alt: 15.0, timestamp_offset_s: 720.0}
        ]
      },

      # White stork migration (simulated segment ~200km)
      "stork_migration" => %{
        name: "White Stork Migration",
        mode: :bird,
        avg_speed_kmh: 45.0,
        total_distance_km: 200.0,
        duration_minutes: 270,
        waypoints: [
          %{lat: 52.5200, lng: 13.4050, alt: 450.0, timestamp_offset_s: 0.0},
          %{lat: 52.4500, lng: 13.3200, alt: 520.0, timestamp_offset_s: 120.0},
          %{lat: 52.3600, lng: 13.2100, alt: 680.0, timestamp_offset_s: 240.0},
          %{lat: 52.2500, lng: 13.0800, alt: 750.0, timestamp_offset_s: 360.0},
          %{lat: 52.1200, lng: 12.9200, alt: 820.0, timestamp_offset_s: 480.0},
          %{lat: 51.9700, lng: 12.7400, alt: 900.0, timestamp_offset_s: 600.0},
          %{lat: 51.8000, lng: 12.5400, alt: 850.0, timestamp_offset_s: 720.0},
          %{lat: 51.6100, lng: 12.3200, alt: 780.0, timestamp_offset_s: 840.0},
          %{lat: 51.4000, lng: 12.0800, alt: 720.0, timestamp_offset_s: 960.0},
          %{lat: 51.1700, lng: 11.8200, alt: 650.0, timestamp_offset_s: 1080.0},
          %{lat: 50.9200, lng: 11.5400, alt: 580.0, timestamp_offset_s: 1200.0},
          %{lat: 50.6500, lng: 11.2400, alt: 520.0, timestamp_offset_s: 1320.0},
          %{lat: 50.3600, lng: 10.9200, alt: 480.0, timestamp_offset_s: 1440.0}
        ]
      },

      # Seagull coastal patrol (~15km)
      "seagull_coastal" => %{
        name: "Seagull Coastal Patrol",
        mode: :bird,
        avg_speed_kmh: 35.0,
        total_distance_km: 15.0,
        duration_minutes: 26,
        waypoints: [
          # Warnemünde
          %{lat: 54.1789, lng: 12.0867, alt: 25.0, timestamp_offset_s: 0.0},
          %{lat: 54.1820, lng: 12.0950, alt: 35.0, timestamp_offset_s: 30.0},
          %{lat: 54.1855, lng: 12.1080, alt: 50.0, timestamp_offset_s: 60.0},
          %{lat: 54.1890, lng: 12.1220, alt: 65.0, timestamp_offset_s: 90.0},
          %{lat: 54.1930, lng: 12.1380, alt: 45.0, timestamp_offset_s: 120.0},
          %{lat: 54.1975, lng: 12.1550, alt: 30.0, timestamp_offset_s: 150.0},
          %{lat: 54.2020, lng: 12.1730, alt: 55.0, timestamp_offset_s: 180.0},
          %{lat: 54.2070, lng: 12.1920, alt: 70.0, timestamp_offset_s: 210.0},
          %{lat: 54.2125, lng: 12.2120, alt: 60.0, timestamp_offset_s: 240.0},
          %{lat: 54.2180, lng: 12.2330, alt: 40.0, timestamp_offset_s: 270.0},
          %{lat: 54.2240, lng: 12.2550, alt: 25.0, timestamp_offset_s: 300.0},
          %{lat: 54.2300, lng: 12.2780, alt: 35.0, timestamp_offset_s: 330.0}
        ]
      },

      # Drone survey pattern (~5km grid)
      "drone_survey" => %{
        name: "Drone Survey Pattern",
        mode: :drone,
        avg_speed_kmh: 25.0,
        total_distance_km: 5.0,
        duration_minutes: 12,
        waypoints: [
          %{lat: 52.5100, lng: 13.3900, alt: 80.0, timestamp_offset_s: 0.0},
          %{lat: 52.5110, lng: 13.3900, alt: 80.0, timestamp_offset_s: 15.0},
          %{lat: 52.5110, lng: 13.3950, alt: 80.0, timestamp_offset_s: 30.0},
          %{lat: 52.5100, lng: 13.3950, alt: 80.0, timestamp_offset_s: 45.0},
          %{lat: 52.5100, lng: 13.4000, alt: 80.0, timestamp_offset_s: 60.0},
          %{lat: 52.5110, lng: 13.4000, alt: 80.0, timestamp_offset_s: 75.0},
          %{lat: 52.5110, lng: 13.4050, alt: 80.0, timestamp_offset_s: 90.0},
          %{lat: 52.5100, lng: 13.4050, alt: 80.0, timestamp_offset_s: 105.0},
          %{lat: 52.5100, lng: 13.4100, alt: 80.0, timestamp_offset_s: 120.0},
          %{lat: 52.5110, lng: 13.4100, alt: 80.0, timestamp_offset_s: 135.0},
          %{lat: 52.5110, lng: 13.4150, alt: 80.0, timestamp_offset_s: 150.0},
          %{lat: 52.5100, lng: 13.4150, alt: 80.0, timestamp_offset_s: 165.0}
        ]
      },

      # Ferry crossing (~20km)
      "ferry_crossing" => %{
        name: "Ferry Crossing",
        mode: :boat,
        avg_speed_kmh: 30.0,
        total_distance_km: 20.0,
        duration_minutes: 40,
        waypoints: [
          # Puttgarden
          %{lat: 54.5069, lng: 11.0579, alt: 5.0, timestamp_offset_s: 0.0},
          %{lat: 54.5200, lng: 11.0800, alt: 5.0, timestamp_offset_s: 60.0},
          %{lat: 54.5400, lng: 11.1100, alt: 5.0, timestamp_offset_s: 120.0},
          %{lat: 54.5650, lng: 11.1450, alt: 5.0, timestamp_offset_s: 180.0},
          %{lat: 54.5950, lng: 11.1850, alt: 5.0, timestamp_offset_s: 240.0},
          %{lat: 54.6300, lng: 11.2300, alt: 5.0, timestamp_offset_s: 300.0},
          %{lat: 54.6700, lng: 11.2800, alt: 5.0, timestamp_offset_s: 360.0},
          %{lat: 54.7150, lng: 11.3350, alt: 5.0, timestamp_offset_s: 420.0},
          %{lat: 54.7600, lng: 11.3900, alt: 5.0, timestamp_offset_s: 480.0},
          # Rødby
          %{lat: 54.7754, lng: 11.4166, alt: 5.0, timestamp_offset_s: 540.0}
        ]
      }
    }
  end
end
