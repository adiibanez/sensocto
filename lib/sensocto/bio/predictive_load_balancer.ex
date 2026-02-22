defmodule Sensocto.Bio.PredictiveLoadBalancer do
  @moduledoc """
  Cerebellum-inspired predictive load balancing.

  Learns temporal patterns in sensor attention and predicts future load.
  Pre-adjusts batch windows before attention changes occur.

  ## Biological Inspiration

  The cerebellum maintains forward models that predict sensory consequences
  50-200ms before they occur. We replicate this by learning hourly patterns
  and pre-adjusting resources before predicted attention spikes.
  """

  use GenServer
  require Logger

  @history_days 14
  @analysis_interval :timer.hours(1)
  @prediction_window 600
  @confidence_threshold 0.6

  defstruct attention_history: [],
            hourly_patterns: %{},
            predictions: %{},
            last_analysis: nil

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record an attention event for pattern learning.
  """
  def record_attention(sensor_id, attention_level) do
    GenServer.cast(__MODULE__, {:record_attention, sensor_id, attention_level})
  end

  @doc """
  Get predictive adjustment factor for a sensor.
  Returns multiplier (< 1.0 = pre-boost, > 1.0 = post-peak slowdown).

  Also checks Hebbian correlations: if a correlated sensor is being boosted,
  this sensor gets a weaker sympathetic boost.
  """
  def get_predictive_factor(sensor_id) do
    direct_factor = get_direct_factor(sensor_id)

    # Apply correlation-based sympathetic boosting
    if direct_factor == 1.0 do
      apply_correlation_boost(sensor_id)
    else
      direct_factor
    end
  rescue
    ArgumentError -> 1.0
  end

  defp get_direct_factor(sensor_id) do
    case :ets.lookup(:bio_predictions, sensor_id) do
      [{_, {:pre_boost, seconds_until}}] ->
        boost = 0.95 - (1 - seconds_until / @prediction_window) * 0.2
        max(0.75, boost)

      [{_, {:post_peak, seconds_since}}] ->
        slowdown = 1.0 + min(seconds_since / @prediction_window, 1.0) * 0.2
        min(1.2, slowdown)

      _ ->
        1.0
    end
  rescue
    ArgumentError -> 1.0
  end

  # If a correlated sensor is being pre-boosted, apply a weaker sympathetic boost.
  # The boost is proportional to the correlation strength.
  defp apply_correlation_boost(sensor_id) do
    correlated = Sensocto.Bio.CorrelationTracker.get_correlated(sensor_id)

    case correlated do
      [] ->
        1.0

      peers ->
        # Find the strongest pre-boost among correlated sensors
        best_boost =
          peers
          |> Enum.reduce(1.0, fn {peer_id, strength}, acc ->
            peer_factor = get_direct_factor(peer_id)

            if peer_factor < 1.0 do
              # Sympathetic boost: weaker version of the peer's boost
              sympathetic = 1.0 - (1.0 - peer_factor) * strength * 0.5
              min(acc, sympathetic)
            else
              acc
            end
          end)

        # Don't boost below 0.9 from correlations alone
        max(0.9, best_boost)
    end
  rescue
    _ -> 1.0
  end

  @doc """
  Get current predictions for monitoring.
  """
  def get_predictions do
    :ets.tab2list(:bio_predictions) |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @doc """
  Get learned patterns for a sensor.
  """
  def get_patterns(sensor_id) do
    GenServer.call(__MODULE__, {:get_patterns, sensor_id})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    :ets.new(:bio_predictions, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(:bio_attention_history, [:named_table, :public, :bag, write_concurrency: true])

    Process.send_after(self(), :analyze_patterns, @analysis_interval)
    Process.send_after(self(), :update_predictions, :timer.minutes(1))

    Logger.info("Bio.PredictiveLoadBalancer started")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:record_attention, sensor_id, attention_level}, state) do
    now = DateTime.utc_now()
    event = {sensor_id, now, attention_to_score(attention_level)}
    :ets.insert(:bio_attention_history, event)

    history = [{sensor_id, now, attention_level} | state.attention_history]
    history = Enum.take(history, 10_000)

    {:noreply, %{state | attention_history: history}}
  end

  @impl true
  def handle_info(:analyze_patterns, state) do
    Logger.debug("[Bio.PredictiveLoadBalancer] Analyzing patterns...")

    cutoff = DateTime.add(DateTime.utc_now(), -@history_days * 24 * 60 * 60)

    history =
      try do
        :ets.select(:bio_attention_history, [
          {{:"$1", :"$2", :"$3"}, [{:>, :"$2", cutoff}], [{{:"$1", :"$2", :"$3"}}]}
        ])
      rescue
        _ -> []
      end

    hourly_patterns = analyze_hourly_patterns(history)

    if map_size(hourly_patterns) > 0 do
      Logger.info(
        "[Bio.PredictiveLoadBalancer] Patterns learned for #{map_size(hourly_patterns)} sensors"
      )
    end

    cleanup_old_history(cutoff)

    Process.send_after(self(), :analyze_patterns, @analysis_interval)

    {:noreply, %{state | hourly_patterns: hourly_patterns, last_analysis: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:update_predictions, state) do
    now = DateTime.utc_now()
    hour = now.hour
    next_hour = rem(hour + 1, 24)

    predictions =
      Enum.flat_map(state.hourly_patterns, fn {sensor_id, pattern} ->
        current_attention = Map.get(pattern, hour, {0.5, 0.0})
        next_attention = Map.get(pattern, next_hour, {0.5, 0.0})

        {current_avg, _} = current_attention
        {next_avg, next_confidence} = next_attention

        cond do
          next_avg > current_avg + 0.3 and next_confidence >= @confidence_threshold ->
            minutes_until_next_hour = 60 - now.minute
            [{sensor_id, {:pre_boost, minutes_until_next_hour * 60}}]

          current_avg > next_avg + 0.3 and next_confidence >= @confidence_threshold ->
            minutes_since_hour = now.minute
            [{sensor_id, {:post_peak, minutes_since_hour * 60}}]

          true ->
            []
        end
      end)

    :ets.delete_all_objects(:bio_predictions)

    Enum.each(predictions, fn {sensor_id, prediction} ->
      :ets.insert(:bio_predictions, {sensor_id, prediction})
    end)

    Process.send_after(self(), :update_predictions, :timer.minutes(1))

    {:noreply, %{state | predictions: Map.new(predictions)}}
  end

  @impl true
  def handle_call({:get_patterns, sensor_id}, _from, state) do
    hourly = Map.get(state.hourly_patterns, sensor_id, %{})
    {:reply, %{hourly: hourly}, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp attention_to_score(:high), do: 1.0
  defp attention_to_score(:medium), do: 0.6
  defp attention_to_score(:low), do: 0.3
  defp attention_to_score(:none), do: 0.0
  defp attention_to_score(_), do: 0.5

  defp analyze_hourly_patterns(history) do
    history
    |> Enum.group_by(fn {sensor_id, datetime, _score} ->
      {sensor_id, datetime.hour}
    end)
    |> Enum.map(fn {{sensor_id, hour}, events} ->
      scores = Enum.map(events, fn {_, _, score} -> score end)
      avg = Enum.sum(scores) / length(scores)
      variance = calculate_variance(scores, avg)
      confidence = calculate_confidence(length(scores), variance)

      {{sensor_id, hour}, {avg, confidence}}
    end)
    |> Enum.group_by(fn {{sensor_id, _hour}, _} -> sensor_id end)
    |> Enum.map(fn {sensor_id, hour_data} ->
      pattern = Enum.map(hour_data, fn {{_, hour}, data} -> {hour, data} end) |> Map.new()
      {sensor_id, pattern}
    end)
    |> Map.new()
  end

  defp calculate_variance(scores, mean) do
    if length(scores) > 1 do
      sum_sq = Enum.reduce(scores, 0.0, fn s, acc -> acc + (s - mean) * (s - mean) end)
      sum_sq / (length(scores) - 1)
    else
      0.0
    end
  end

  defp calculate_confidence(sample_size, variance) do
    size_factor = min(sample_size / 50, 1.0)
    variance_factor = 1.0 / (1.0 + variance * 10)
    size_factor * variance_factor
  end

  defp cleanup_old_history(cutoff) do
    try do
      :ets.select_delete(:bio_attention_history, [
        {{:"$1", :"$2", :"$3"}, [{:<, :"$2", cutoff}], [true]}
      ])
    rescue
      _ -> :ok
    end
  end
end
