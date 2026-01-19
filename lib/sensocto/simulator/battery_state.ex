defmodule Sensocto.Simulator.BatteryState do
  @moduledoc """
  Manages persistent battery state for simulated sensors.
  Tracks battery level, charging status, and handles realistic drain/charge rates.

  Realistic rates based on typical mobile device usage:
  - Drain rate (active use): ~10-15% per hour (0.17-0.25% per minute)
  - Drain rate (standby): ~1-2% per hour (0.017-0.033% per minute)
  - Charge rate (fast charging): ~50% per hour (0.83% per minute)
  - Charge rate (normal): ~20% per hour (0.33% per minute)
  """

  use GenServer
  require Logger

  alias Sensocto.Sensors.SimulatorBatteryState

  @table_name :battery_state
  @hydration_delay_ms 200
  @sync_interval_ms 60_000
  # Check every 10 seconds for state flip (faster for demo)
  @state_check_interval :timer.seconds(10)

  # Realistic rates (% per minute) - slightly accelerated for demo visibility
  @drain_rate_active 0.5
  # @drain_rate_standby 0.025  # Reserved for future standby mode
  @charge_rate_normal 0.8
  # @charge_rate_fast 1.5  # Reserved for future fast charging mode

  # Charging flip parameters (in minutes) - short for demo visibility
  # Each sensor gets its own random flip time within this range
  @min_flip_duration 1
  @max_flip_duration 5

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current battery state for a sensor.
  Returns {level, charging?} where level is 0-100 and charging? is boolean.
  Initializes state if not exists.
  """
  def get_state(sensor_id, config \\ %{}) do
    case :ets.lookup(@table_name, sensor_id) do
      [{^sensor_id, state}] ->
        # Update the level based on time elapsed
        updated_state = update_level(state)
        :ets.insert(@table_name, {sensor_id, updated_state})
        {updated_state.level, updated_state.charging}

      [] ->
        # Initialize new battery state
        state = init_state(sensor_id, config)
        :ets.insert(@table_name, {sensor_id, state})
        {state.level, state.charging}
    end
  end

  @doc """
  Gets battery data formatted for the data generator.
  Returns a map with level and charging status.
  """
  def get_battery_data(sensor_id, config \\ %{}) do
    {level, charging} = get_state(sensor_id, config)

    %{
      level: Float.round(level, 1),
      charging: if(charging, do: "yes", else: "no")
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for battery states
    :ets.new(@table_name, [:named_table, :public, :set])

    # Start periodic state flip checker
    Process.send_after(self(), :check_state_flips, @state_check_interval)

    # Schedule hydration from PostgreSQL
    Process.send_after(self(), :hydrate_from_postgres, @hydration_delay_ms)

    # Schedule periodic sync
    Process.send_after(self(), :sync_battery_states, @sync_interval_ms)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_state_flips, state) do
    now = System.monotonic_time(:millisecond)

    # Check all battery states for potential flip
    :ets.foldl(
      fn {sensor_id, battery_state}, _acc ->
        if should_flip?(battery_state, now) do
          new_state = flip_charging_state(battery_state, now)
          :ets.insert(@table_name, {sensor_id, new_state})
        end

        :ok
      end,
      :ok,
      @table_name
    )

    Process.send_after(self(), :check_state_flips, @state_check_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:hydrate_from_postgres, state) do
    Logger.debug("[BatteryState] Hydrating battery states from PostgreSQL...")

    case load_battery_states_from_db() do
      {:ok, battery_states} when battery_states != [] ->
        Logger.info("[BatteryState] Found #{length(battery_states)} battery states to restore")
        restore_battery_states(battery_states)
        {:noreply, state}

      {:ok, []} ->
        Logger.debug("[BatteryState] No battery states to restore")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[BatteryState] Failed to hydrate: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:sync_battery_states, state) do
    # Schedule next sync
    Process.send_after(self(), :sync_battery_states, @sync_interval_ms)

    # Sync all battery states asynchronously via rate-limited task supervisor
    ets_size = :ets.info(@table_name, :size)

    if ets_size > 0 do
      Task.Supervisor.start_child(
        Sensocto.Simulator.DbTaskSupervisor,
        fn -> sync_battery_states_to_postgres() end
      )
    end

    {:noreply, state}
  end

  # Private Functions

  defp init_state(sensor_id, config) do
    now = System.monotonic_time(:millisecond)

    # Initialize with values from config or random defaults
    initial_level =
      case {config[:min_value], config[:max_value]} do
        {min, max} when is_number(min) and is_number(max) ->
          # Start at a random level within the configured range
          min + :rand.uniform() * (max - min)

        _ ->
          # Random starting level between 20-90%
          20.0 + :rand.uniform() * 70.0
      end

    # Random initial charging state (30% chance of charging)
    charging = :rand.uniform() < 0.3

    # Calculate when to flip state (random duration)
    flip_at = calculate_next_flip(now, charging)

    Logger.debug(
      "Battery state initialized for #{sensor_id}: level=#{Float.round(initial_level, 1)}%, charging=#{charging}"
    )

    %{
      level: initial_level,
      charging: charging,
      last_update: now,
      flip_at: flip_at,
      # Varies drain rate slightly per sensor
      drain_multiplier: 0.7 + :rand.uniform() * 0.6,
      # Varies charge rate slightly per sensor
      charge_multiplier: 0.8 + :rand.uniform() * 0.4
    }
  end

  defp update_level(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_minutes = (now - state.last_update) / :timer.minutes(1)

    new_level =
      if state.charging do
        # Charging: level increases
        rate = @charge_rate_normal * state.charge_multiplier
        min(100.0, state.level + rate * elapsed_minutes)
      else
        # Draining: level decreases (use active rate for simulation visibility)
        rate = @drain_rate_active * state.drain_multiplier
        max(0.0, state.level - rate * elapsed_minutes)
      end

    # Add small random noise for realism
    noise = (:rand.uniform() - 0.5) * 0.1
    new_level = max(0.0, min(100.0, new_level + noise))

    %{state | level: new_level, last_update: now}
  end

  defp should_flip?(state, now) do
    cond do
      # Always flip if battery is full and charging
      state.charging and state.level >= 99.5 -> true
      # Always flip if battery is empty and draining
      not state.charging and state.level <= 0.5 -> true
      # Flip at scheduled time
      now >= state.flip_at -> true
      true -> false
    end
  end

  defp flip_charging_state(state, now) do
    new_charging = not state.charging

    Logger.debug(
      "Battery state flipped: charging=#{state.charging} -> #{new_charging}, level=#{Float.round(state.level, 1)}%"
    )

    %{
      state
      | charging: new_charging,
        flip_at: calculate_next_flip(now, new_charging)
    }
  end

  defp calculate_next_flip(now, _charging) do
    # Each sensor gets a random flip duration between 1-5 minutes
    # This is per-sensor, so different sensors flip at different times
    duration_minutes = @min_flip_duration + :rand.uniform(@max_flip_duration - @min_flip_duration)

    now + :timer.minutes(duration_minutes)
  end

  # PostgreSQL Persistence Functions

  defp load_battery_states_from_db do
    try do
      battery_states =
        SimulatorBatteryState
        |> Ash.Query.for_read(:all)
        |> Ash.read!()

      {:ok, battery_states}
    rescue
      e -> {:error, e}
    end
  end

  defp restore_battery_states(battery_states) do
    now = System.monotonic_time(:millisecond)

    Enum.each(battery_states, fn bs ->
      state = %{
        level: bs.level || 50.0,
        charging: bs.charging || false,
        last_update: now,
        flip_at: calculate_next_flip(now, bs.charging || false),
        drain_multiplier: bs.drain_multiplier || 1.0,
        charge_multiplier: bs.charge_multiplier || 1.0
      }

      :ets.insert(@table_name, {bs.sensor_id, state})
      Logger.debug("[BatteryState] Restored state for #{bs.sensor_id}: level=#{bs.level}%")
    end)
  end

  defp sync_battery_states_to_postgres do
    try do
      :ets.foldl(
        fn {sensor_id, battery_state}, _acc ->
          case SimulatorBatteryState
               |> Ash.Query.for_read(:by_sensor, %{sensor_id: sensor_id})
               |> Ash.read_one() do
            {:ok, nil} ->
              # Record doesn't exist yet - it should be created when connector syncs
              :ok

            {:ok, existing} ->
              # Update battery state
              existing
              |> Ash.Changeset.for_update(:sync_state, %{
                level: battery_state.level,
                charging: battery_state.charging,
                drain_multiplier: battery_state.drain_multiplier,
                charge_multiplier: battery_state.charge_multiplier
              })
              |> Ash.update()

            {:error, _} ->
              :ok
          end

          :ok
        end,
        :ok,
        @table_name
      )
    rescue
      e ->
        Logger.warning("[BatteryState] Exception syncing states: #{inspect(e)}")
    end
  end
end
