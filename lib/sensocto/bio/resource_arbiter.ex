defmodule Sensocto.Bio.ResourceArbiter do
  @moduledoc """
  Retina-inspired lateral inhibition for resource allocation.

  Implements competitive resource allocation where high-priority
  sensors suppress low-priority sensors during contention.

  ## Biological Inspiration

  In the retina, neighboring neurons inhibit each other to sharpen contrast
  and prevent resource waste on redundant signals. We replicate this by
  giving high-priority sensors disproportionate resources during contention.

  ## How It Works

  1. Calculate priority for each sensor (attention + novelty)
  2. Apply power-law allocation (winner-take-more)
  3. Convert allocation to batch window multiplier
  """

  use GenServer
  require Logger

  @reallocation_interval 5_000
  @power_law_exponent 1.3

  defstruct sensor_priorities: %{},
            allocations: %{},
            total_sensors: 0,
            last_allocation: nil

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the competitive multiplier for a sensor.
  Lower = more resources (faster updates).
  """
  def get_multiplier(sensor_id) do
    case :ets.lookup(:bio_resource_allocations, sensor_id) do
      [{_, multiplier}] -> multiplier
      [] -> 1.0
    end
  rescue
    ArgumentError -> 1.0
  end

  @doc """
  Get all current allocations for monitoring.
  """
  def get_allocations do
    :ets.tab2list(:bio_resource_allocations) |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @doc """
  Force reallocation (for testing).
  """
  def reallocate do
    GenServer.call(__MODULE__, :reallocate)
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
    :ets.new(:bio_resource_allocations, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    Process.send_after(self(), :reallocate, @reallocation_interval)

    Logger.info("Bio.ResourceArbiter started (power_law=#{@power_law_exponent})")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:reallocate, state) do
    sensors = list_active_sensors()

    new_state =
      if length(sensors) > 0 do
        priorities =
          Enum.map(sensors, fn sensor_id ->
            priority = calculate_priority(sensor_id)
            {sensor_id, priority}
          end)
          |> Map.new()

        allocations = allocate_with_inhibition(priorities)

        Enum.each(allocations, fn {sensor_id, multiplier} ->
          :ets.insert(:bio_resource_allocations, {sensor_id, multiplier})
        end)

        %{
          state
          | sensor_priorities: priorities,
            allocations: allocations,
            total_sensors: length(sensors),
            last_allocation: DateTime.utc_now()
        }
      else
        state
      end

    Process.send_after(self(), :reallocate, @reallocation_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:reallocate, _from, state) do
    send(self(), :reallocate)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp list_active_sensors do
    try do
      Registry.select(Sensocto.SimpleSensorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    rescue
      _ -> []
    end
  end

  defp calculate_priority(sensor_id) do
    attention = get_attention_score(sensor_id)

    novelty =
      try do
        Sensocto.Bio.NoveltyDetector.get_novelty_score(sensor_id, "*")
      rescue
        _ -> 0.0
      end

    0.5 * attention + 0.3 * novelty + 0.2 * 0.5
  end

  defp get_attention_score(sensor_id) do
    try do
      case Sensocto.AttentionTracker.get_sensor_attention_level(sensor_id) do
        :high -> 1.0
        :medium -> 0.6
        :low -> 0.3
        :none -> 0.1
        _ -> 0.5
      end
    rescue
      _ -> 0.5
    end
  end

  defp allocate_with_inhibition(priorities) do
    sorted = Enum.sort_by(priorities, fn {_, p} -> -p end)
    total_priority = Enum.sum(Enum.map(sorted, fn {_, p} -> max(p, 0.01) end))

    Enum.map(sorted, fn {sensor_id, priority} ->
      fraction = :math.pow(max(priority, 0.01) / total_priority, @power_law_exponent)

      multiplier = 5.0 - fraction * 4.5
      multiplier = max(0.5, min(5.0, multiplier))

      {sensor_id, multiplier}
    end)
    |> Map.new()
  end
end
