defmodule Sensocto.Bio.HomeostaticTuner do
  @moduledoc """
  Homeostatic plasticity-inspired threshold adaptation.

  Self-tunes load thresholds based on historical distribution.
  Goal: Maintain target distribution of time spent in each load state.

  ## Biological Inspiration

  Neurons maintain homeostatic balance by self-adjusting their sensitivity
  thresholds. We replicate this by tracking load state distribution and
  adapting thresholds to match a target distribution.

  ## Target Distribution

  - :normal   → 70% of time (healthy operation)
  - :elevated → 20% of time (occasional load)
  - :high     → 8% of time (peak periods)
  - :critical → 2% of time (rare emergencies)
  """

  use GenServer
  require Logger

  @target_distribution %{
    normal: 0.70,
    elevated: 0.20,
    high: 0.08,
    critical: 0.02
  }

  @adaptation_interval :timer.hours(1)
  @adaptation_rate 0.005
  @sample_buffer_size 3600

  defstruct load_samples: [],
            threshold_offsets: %{
              elevated: 0.0,
              high: 0.0,
              critical: 0.0
            },
            last_adaptation: nil,
            actual_distribution: %{}

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a load sample. Called by SystemLoadMonitor.
  """
  def record_sample(load_level) do
    GenServer.cast(__MODULE__, {:record_sample, load_level})
  end

  @doc """
  Get current threshold offsets for SystemLoadMonitor.
  """
  def get_offsets do
    case :ets.lookup(:bio_homeostatic_offsets, :offsets) do
      [{_, offsets}] -> offsets
      [] -> %{elevated: 0.0, high: 0.0, critical: 0.0}
    end
  rescue
    ArgumentError -> %{elevated: 0.0, high: 0.0, critical: 0.0}
  end

  @doc """
  Get current state for monitoring.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Get target distribution.
  """
  def get_target_distribution, do: @target_distribution

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    :ets.new(:bio_homeostatic_offsets, [:named_table, :public, read_concurrency: true])
    :ets.insert(:bio_homeostatic_offsets, {:offsets, %{elevated: 0.0, high: 0.0, critical: 0.0}})

    Process.send_after(self(), :adapt, @adaptation_interval)

    Logger.info("Bio.HomeostaticTuner started (target: #{inspect(@target_distribution)})")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:record_sample, load_level}, state) do
    samples = [load_level | state.load_samples]
    samples = Enum.take(samples, @sample_buffer_size)

    {:noreply, %{state | load_samples: samples}}
  end

  @impl true
  def handle_info(:adapt, state) do
    new_state =
      if length(state.load_samples) >= 100 do
        actual_dist = calculate_distribution(state.load_samples)
        new_offsets = calculate_offsets(actual_dist, state.threshold_offsets)

        :ets.insert(:bio_homeostatic_offsets, {:offsets, new_offsets})

        Logger.info(
          "[Bio.HomeostaticTuner] Adaptation: " <>
            "actual=#{format_distribution(actual_dist)}, " <>
            "offsets=#{format_offsets(new_offsets)}"
        )

        Phoenix.PubSub.broadcast(
          Sensocto.PubSub,
          "bio:homeostasis",
          {:adaptation, %{actual: actual_dist, offsets: new_offsets}}
        )

        %{
          state
          | threshold_offsets: new_offsets,
            actual_distribution: actual_dist,
            last_adaptation: DateTime.utc_now()
        }
      else
        state
      end

    Process.send_after(self(), :adapt, @adaptation_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp calculate_distribution(samples) do
    total = length(samples)

    Enum.reduce(samples, %{normal: 0, elevated: 0, high: 0, critical: 0}, fn level, acc ->
      Map.update(acc, level, 1, &(&1 + 1))
    end)
    |> Enum.map(fn {level, count} -> {level, count / total} end)
    |> Map.new()
  end

  defp calculate_offsets(actual_dist, current_offsets) do
    Enum.reduce([:elevated, :high, :critical], current_offsets, fn level, offsets ->
      target = Map.get(@target_distribution, level, 0.0)
      actual = Map.get(actual_dist, level, 0.0)
      error = actual - target

      current_offset = Map.get(offsets, level, 0.0)
      adjustment = error * @adaptation_rate

      new_offset = current_offset + adjustment
      new_offset = max(-0.1, min(0.1, new_offset))

      Map.put(offsets, level, new_offset)
    end)
  end

  defp format_distribution(dist) do
    [:normal, :elevated, :high, :critical]
    |> Enum.map(fn level ->
      pct = Map.get(dist, level, 0.0) * 100
      "#{level}=#{Float.round(pct, 1)}%"
    end)
    |> Enum.join(", ")
  end

  defp format_offsets(offsets) do
    [:elevated, :high, :critical]
    |> Enum.map(fn level ->
      offset = Map.get(offsets, level, 0.0)
      sign = if offset >= 0, do: "+", else: ""
      "#{level}=#{sign}#{Float.round(offset, 3)}"
    end)
    |> Enum.join(", ")
  end
end
