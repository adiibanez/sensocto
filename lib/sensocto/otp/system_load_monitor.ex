defmodule Sensocto.SystemLoadMonitor do
  @moduledoc """
  Monitors system load metrics and provides load multipliers for backpressure.

  Tracks:
  - Scheduler utilization (CPU load across BEAM schedulers)
  - Message queue depths (process mailbox sizes)
  - Memory pressure

  Load levels:
  - :normal - System running smoothly, no throttling
  - :elevated - Moderate load, slight throttling (1.5x batch window)
  - :high - Heavy load, significant throttling (3x batch window)
  - :critical - System overloaded, maximum throttling (5x batch window)

  The monitor broadcasts load changes via PubSub, allowing AttributeServers
  to adjust batch windows based on system health.
  """

  use GenServer
  require Logger

  @sample_interval 2_000
  @scheduler_sample_interval 1_000

  # ETS table for fast concurrent reads
  @load_state_table :system_load_cache

  # Load thresholds (scheduler utilization 0.0 - 1.0)
  @load_thresholds %{
    normal: 0.5,
    elevated: 0.7,
    high: 0.85,
    critical: 0.95
  }

  # Batch window multipliers based on load level
  @load_config %{
    normal: %{window_multiplier: 1.0, description: "System normal"},
    elevated: %{window_multiplier: 1.5, description: "Moderate load"},
    high: %{window_multiplier: 3.0, description: "Heavy load"},
    critical: %{window_multiplier: 5.0, description: "System overloaded"}
  }

  defstruct [
    :current_load_level,
    :scheduler_utilization,
    :message_queue_pressure,
    :memory_pressure,
    :last_scheduler_sample,
    :scheduler_history
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current system load level.
  Uses ETS for fast concurrent reads.
  """
  def get_load_level do
    case :ets.lookup(@load_state_table, :load_level) do
      [{_, level}] -> level
      [] -> :normal
    end
  end

  @doc """
  Get the load multiplier for batch window calculations.
  """
  def get_load_multiplier do
    level = get_load_level()
    Map.get(@load_config, level, @load_config.normal).window_multiplier
  end

  @doc """
  Get detailed load metrics for debugging/display.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Get load configuration for a specific level.
  """
  def get_load_config(level) do
    Map.get(@load_config, level, @load_config.normal)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS table for fast concurrent reads
    :ets.new(@load_state_table, [:named_table, :public, read_concurrency: true])
    :ets.insert(@load_state_table, {:load_level, :normal})
    :ets.insert(@load_state_table, {:load_multiplier, 1.0})

    # Start scheduler utilization sampling
    :scheduler.sample()

    state = %__MODULE__{
      current_load_level: :normal,
      scheduler_utilization: 0.0,
      message_queue_pressure: 0.0,
      memory_pressure: 0.0,
      last_scheduler_sample: nil,
      scheduler_history: []
    }

    # Schedule first sample
    Process.send_after(self(), :sample_scheduler, @scheduler_sample_interval)
    Process.send_after(self(), :calculate_load, @sample_interval)

    Logger.info("SystemLoadMonitor started")
    {:ok, state}
  end

  @impl true
  def handle_info(:sample_scheduler, state) do
    # Get scheduler utilization since last sample
    sample = :scheduler.sample()

    new_state =
      if state.last_scheduler_sample do
        utilization = :scheduler.utilization(state.last_scheduler_sample, sample)

        # Extract total scheduler utilization (weighted average)
        total_util = extract_total_utilization(utilization)

        # Keep history for smoothing (last 5 samples)
        history = Enum.take([total_util | state.scheduler_history], 5)

        %{state |
          scheduler_utilization: total_util,
          last_scheduler_sample: sample,
          scheduler_history: history
        }
      else
        %{state | last_scheduler_sample: sample}
      end

    Process.send_after(self(), :sample_scheduler, @scheduler_sample_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:calculate_load, state) do
    # Calculate message queue pressure (sample key processes)
    msg_pressure = calculate_message_queue_pressure()

    # Calculate memory pressure
    mem_pressure = calculate_memory_pressure()

    # Use smoothed scheduler utilization
    smoothed_util =
      if length(state.scheduler_history) > 0 do
        Enum.sum(state.scheduler_history) / length(state.scheduler_history)
      else
        state.scheduler_utilization
      end

    # Determine overall load level (use max of all pressures)
    overall_pressure = max(smoothed_util, max(msg_pressure, mem_pressure))
    new_level = determine_load_level(overall_pressure)

    new_state = %{state |
      message_queue_pressure: msg_pressure,
      memory_pressure: mem_pressure,
      scheduler_utilization: smoothed_util
    }

    # Broadcast if level changed
    if new_level != state.current_load_level do
      Logger.info(
        "System load changed: #{state.current_load_level} -> #{new_level} " <>
        "(scheduler: #{Float.round(smoothed_util * 100, 1)}%, " <>
        "msg_queue: #{Float.round(msg_pressure * 100, 1)}%, " <>
        "memory: #{Float.round(mem_pressure * 100, 1)}%)"
      )

      update_ets_cache(new_level)
      broadcast_load_change(new_level, new_state)
    end

    Process.send_after(self(), :calculate_load, @sample_interval)
    {:noreply, %{new_state | current_load_level: new_level}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      load_level: state.current_load_level,
      scheduler_utilization: state.scheduler_utilization,
      message_queue_pressure: state.message_queue_pressure,
      memory_pressure: state.memory_pressure,
      load_multiplier: get_load_multiplier(),
      thresholds: @load_thresholds,
      config: @load_config
    }
    {:reply, metrics, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp extract_total_utilization(utilization) do
    # utilization is a list containing tuples like:
    # - {:total, util, percent_string} for total
    # - {scheduler_id, util, percent_string} for individual schedulers
    # Find the :total entry directly in the list
    case Enum.find(utilization, fn
      {:total, _, _} -> true
      _ -> false
    end) do
      {:total, util, _percent} ->
        util

      nil ->
        # Calculate average from individual schedulers (integers only, skip :cpu etc)
        scheduler_utils =
          utilization
          |> Enum.filter(fn
            {id, _, _} when is_integer(id) -> true
            _ -> false
          end)
          |> Enum.map(fn {_, util, _} -> util end)

        if length(scheduler_utils) > 0 do
          Enum.sum(scheduler_utils) / length(scheduler_utils)
        else
          0.0
        end
    end
  end

  defp calculate_message_queue_pressure do
    # Sample message queue lengths from key processes
    key_processes = [
      Sensocto.AttentionTracker,
      Sensocto.SensorsDynamicSupervisor,
      SensoctoWeb.Endpoint
    ]

    queue_lengths =
      key_processes
      |> Enum.map(fn name ->
        case Process.whereis(name) do
          nil -> 0
          pid ->
            case Process.info(pid, :message_queue_len) do
              {:message_queue_len, len} -> len
              nil -> 0
            end
        end
      end)

    # Also sample some random processes from the system
    random_samples =
      Process.list()
      |> Enum.take_random(20)
      |> Enum.map(fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> len
          nil -> 0
        end
      end)

    all_lengths = queue_lengths ++ random_samples
    max_queue = Enum.max(all_lengths, fn -> 0 end)
    avg_queue = Enum.sum(all_lengths) / max(length(all_lengths), 1)

    # Normalize: queue > 1000 is critical, > 500 is high, > 100 is elevated
    cond do
      max_queue > 1000 -> 1.0
      max_queue > 500 -> 0.9
      max_queue > 100 -> 0.75
      avg_queue > 50 -> 0.6
      avg_queue > 20 -> 0.4
      true -> avg_queue / 100
    end
  end

  defp calculate_memory_pressure do
    mem_data = :erlang.memory()
    total = Keyword.get(mem_data, :total, 0)
    processes = Keyword.get(mem_data, :processes, 0)

    # Get system memory info if available
    case :memsup.get_system_memory_data() do
      data when is_list(data) ->
        free = Keyword.get(data, :free_memory, 0)
        total_sys = Keyword.get(data, :total_memory, 1)
        1.0 - (free / total_sys)

      _ ->
        # Fallback: estimate based on BEAM memory growth
        # This is a rough heuristic
        process_ratio = processes / max(total, 1)
        min(process_ratio * 2, 1.0)
    end
  rescue
    # :memsup might not be available
    _ -> 0.3
  end

  defp determine_load_level(pressure) do
    cond do
      pressure >= @load_thresholds.critical -> :critical
      pressure >= @load_thresholds.high -> :high
      pressure >= @load_thresholds.elevated -> :elevated
      true -> :normal
    end
  end

  defp update_ets_cache(level) do
    config = Map.get(@load_config, level, @load_config.normal)
    :ets.insert(@load_state_table, {:load_level, level})
    :ets.insert(@load_state_table, {:load_multiplier, config.window_multiplier})
  end

  defp broadcast_load_change(level, state) do
    config = Map.get(@load_config, level, @load_config.normal)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "system:load",
      {:system_load_changed, %{
        level: level,
        multiplier: config.window_multiplier,
        scheduler_utilization: state.scheduler_utilization,
        message_queue_pressure: state.message_queue_pressure,
        memory_pressure: state.memory_pressure
      }}
    )
  end
end
