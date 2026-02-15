defmodule Sensocto.Bio.CircadianScheduler do
  @moduledoc """
  SCN-inspired circadian rhythm awareness.

  Learns daily patterns and pre-adjusts for predictable peaks.

  ## Biological Inspiration

  The suprachiasmatic nucleus (SCN) is the brain's master clock, coordinating
  circadian rhythms that pre-adjust metabolism and alertness. We replicate
  this by learning hourly load patterns and pre-adjusting resources.

  ## Phases

  - :approaching_peak  → Pre-throttle (1.15x)
  - :peak              → Full throttle (1.2x)
  - :approaching_off_peak → Pre-boost (0.9x)
  - :off_peak          → Full boost (0.85x)
  - :normal            → No adjustment (1.0x)
  """

  use GenServer
  require Logger

  @phase_check_interval :timer.minutes(10)
  @profile_learning_interval :timer.hours(6)

  defstruct hourly_profile: %{},
            current_phase: :unknown,
            phase_adjustment: 1.0,
            load_history: []

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current circadian phase adjustment.
  """
  def get_phase_adjustment do
    case :ets.lookup(:bio_circadian_state, :adjustment) do
      [{_, adj}] -> adj
      [] -> 1.0
    end
  rescue
    ArgumentError -> 1.0
  end

  @doc """
  Get current phase for monitoring.
  """
  def get_phase do
    case :ets.lookup(:bio_circadian_state, :phase) do
      [{_, phase}] -> phase
      [] -> :unknown
    end
  rescue
    ArgumentError -> :unknown
  end

  @doc """
  Record load sample for profile learning.
  """
  def record_load(load_level, pressure) do
    GenServer.cast(__MODULE__, {:record_load, load_level, pressure})
  end

  @doc """
  Get learned hourly profile.
  """
  def get_profile do
    GenServer.call(__MODULE__, :get_profile)
  end

  @doc """
  Get current state for monitoring.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    :ets.new(:bio_circadian_state, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.insert(:bio_circadian_state, {:adjustment, 1.0})
    :ets.insert(:bio_circadian_state, {:phase, :unknown})

    Process.send_after(self(), :check_phase, @phase_check_interval)
    Process.send_after(self(), :learn_profile, @profile_learning_interval)

    Logger.info("Bio.CircadianScheduler started")

    {:ok, %__MODULE__{hourly_profile: default_profile()}}
  end

  @impl true
  def handle_cast({:record_load, load_level, pressure}, state) do
    now = DateTime.utc_now()
    entry = {now.hour, load_to_score(load_level), pressure}

    history = [entry | state.load_history]
    history = Enum.take(history, 24 * 60)

    {:noreply, %{state | load_history: history}}
  end

  @impl true
  def handle_info(:check_phase, state) do
    now = DateTime.utc_now()
    hour = now.hour
    next_hour = rem(hour + 1, 24)

    current_load = Map.get(state.hourly_profile, hour, 0.5)
    next_load = Map.get(state.hourly_profile, next_hour, 0.5)

    new_phase =
      cond do
        next_load > 0.7 and current_load <= 0.7 -> :approaching_peak
        current_load > 0.7 -> :peak
        next_load < 0.3 and current_load >= 0.3 -> :approaching_off_peak
        current_load < 0.3 -> :off_peak
        true -> :normal
      end

    adjustment =
      case new_phase do
        :approaching_peak -> 1.15
        :peak -> 1.2
        :approaching_off_peak -> 0.9
        :off_peak -> 0.85
        :normal -> 1.0
        _ -> 1.0
      end

    if new_phase != state.current_phase do
      Logger.info(
        "[Bio.CircadianScheduler] Phase: #{state.current_phase} → #{new_phase} (adj=#{adjustment})"
      )

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "bio:circadian",
        {:phase_change, %{phase: new_phase, adjustment: adjustment, hour: hour}}
      )
    end

    :ets.insert(:bio_circadian_state, {:adjustment, adjustment})
    :ets.insert(:bio_circadian_state, {:phase, new_phase})

    Process.send_after(self(), :check_phase, @phase_check_interval)

    {:noreply, %{state | current_phase: new_phase, phase_adjustment: adjustment}}
  end

  @impl true
  def handle_info(:learn_profile, state) do
    new_profile =
      if length(state.load_history) >= 60 do
        state.load_history
        |> Enum.group_by(fn {hour, _, _} -> hour end)
        |> Enum.map(fn {hour, entries} ->
          avg_score = Enum.sum(Enum.map(entries, fn {_, score, _} -> score end)) / length(entries)
          {hour, avg_score}
        end)
        |> Map.new()
        |> then(fn learned ->
          Map.merge(default_profile(), learned)
        end)
      else
        state.hourly_profile
      end

    if new_profile != state.hourly_profile do
      Logger.info(
        "[Bio.CircadianScheduler] Profile updated from #{length(state.load_history)} samples"
      )
    end

    Process.send_after(self(), :learn_profile, @profile_learning_interval)

    {:noreply, %{state | hourly_profile: new_profile}}
  end

  @impl true
  def handle_call(:get_profile, _from, state) do
    {:reply, state.hourly_profile, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp load_to_score(:critical), do: 1.0
  defp load_to_score(:high), do: 0.8
  defp load_to_score(:elevated), do: 0.5
  defp load_to_score(:normal), do: 0.2
  defp load_to_score(_), do: 0.5

  defp default_profile do
    %{
      0 => 0.2,
      1 => 0.15,
      2 => 0.1,
      3 => 0.1,
      4 => 0.1,
      5 => 0.15,
      6 => 0.3,
      7 => 0.5,
      8 => 0.7,
      9 => 0.8,
      10 => 0.75,
      11 => 0.7,
      12 => 0.6,
      13 => 0.65,
      14 => 0.7,
      15 => 0.65,
      16 => 0.6,
      17 => 0.5,
      18 => 0.4,
      19 => 0.35,
      20 => 0.3,
      21 => 0.25,
      22 => 0.2,
      23 => 0.2
    }
  end
end
