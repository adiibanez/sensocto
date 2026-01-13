# Let's Go Bio: Biomimetic Backpressure Implementation Plan

**Project:** Sensocto Biomimetic Enhancement
**Date:** January 12, 2026
**Status:** Ready for Implementation

---

## Executive Summary

Transform Sensocto from a **reactive** to a **predictive, adaptive, content-aware** system by implementing 5 biomimetic modules inspired by neuroscience and biological systems.

### The Core Insight

> **Nature doesn't do reactive systems.**
> Biology favors prediction over reaction, adaptation over fixed rules, and competition over fairness.

### What We're Building

```
CURRENT                          FUTURE
═══════                          ══════
Reactive throttling      →       Predictive pre-adjustment
Fixed thresholds         →       Self-adapting thresholds
Blind to data content    →       Novelty-aware boosting
Equal resource sharing   →       Competitive allocation
No temporal awareness    →       Circadian pattern learning
```

### Expected Outcomes

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Reactive throttling events | 100% | 70% | -30% |
| Anomaly detection latency | Manual | 5s | Automated |
| Resource utilization | Fair | Optimal | +20% |
| Threshold tuning | Manual | Automatic | Zero-config |
| Peak transition smoothness | Abrupt | Gradual | +15% |

---

## Architecture Overview

### Current System

```
┌─────────────────────────────────────────────────────────────────┐
│                     CURRENT ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Browser ──viewport/focus/battery──▶ AttentionTracker          │
│                                            │                     │
│                                            │ PubSub              │
│                                            ▼                     │
│   SystemLoadMonitor ──CPU/memory──▶ AttributeServer             │
│                                                                  │
│   Formula: window = base × attention_mult × load_mult           │
│                                                                  │
│   Mode: REACTIVE (wait for event → respond)                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Enhanced System (What We're Building)

```
┌─────────────────────────────────────────────────────────────────┐
│                    ENHANCED ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Browser ─────────────────────────▶ AttentionTracker           │
│                                            │                     │
│   SystemLoadMonitor ───────────────────────┤                     │
│                                            │                     │
│   ┌────────────────────────────────────────┼──────────────────┐ │
│   │           NEW BIOMIMETIC LAYER         │                  │ │
│   │                                        ▼                  │ │
│   │  ┌──────────────┐    ┌──────────────────────────────┐    │ │
│   │  │ Novelty      │───▶│     Enhanced AttributeServer │    │ │
│   │  │ Detector     │    │                              │    │ │
│   │  │ (Locus       │    │  window = base               │    │ │
│   │  │  Coeruleus)  │    │         × attention_mult     │    │ │
│   │  └──────────────┘    │         × load_mult          │    │ │
│   │                      │         × novelty_boost  ◀───│    │ │
│   │  ┌──────────────┐    │         × predictive_adj ◀───│    │ │
│   │  │ Predictive   │───▶│         × competitive_mult◀──│    │ │
│   │  │ LoadBalancer │    │         × circadian_adj  ◀───│    │ │
│   │  │ (Cerebellum) │    │         × homeostatic_adj◀───│    │ │
│   │  └──────────────┘    └──────────────────────────────┘    │ │
│   │                                        ▲                  │ │
│   │  ┌──────────────┐    ┌──────────────┐ │                  │ │
│   │  │ Resource     │    │ Circadian    │ │                  │ │
│   │  │ Arbiter      │────│ Scheduler    │─┘                  │ │
│   │  │ (Retina)     │    │ (SCN)        │                    │ │
│   │  └──────────────┘    └──────────────┘                    │ │
│   │         ▲                    ▲                            │ │
│   │         │            ┌──────────────┐                    │ │
│   │         └────────────│ Homeostatic  │                    │ │
│   │                      │ Tuner        │                    │ │
│   │                      │ (Plasticity) │                    │ │
│   │                      └──────────────┘                    │ │
│   │                                                          │ │
│   └──────────────────────────────────────────────────────────┘ │
│                                                                  │
│   Mode: PREDICTIVE + ADAPTIVE + CONTENT-AWARE                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Biology → Code Mapping

```
┌────────────────────────┬─────────────────────────┬──────────────┐
│ Biological System      │ Sensocto Module         │ Function     │
├────────────────────────┼─────────────────────────┼──────────────┤
│ Locus Coeruleus        │ NoveltyDetector         │ Anomaly →    │
│ (alertness center)     │                         │ attention    │
├────────────────────────┼─────────────────────────┼──────────────┤
│ Cerebellum             │ PredictiveLoadBalancer  │ Pattern →    │
│ (forward models)       │                         │ prediction   │
├────────────────────────┼─────────────────────────┼──────────────┤
│ Retina                 │ ResourceArbiter         │ Competition  │
│ (lateral inhibition)   │                         │ → priority   │
├────────────────────────┼─────────────────────────┼──────────────┤
│ Synaptic Plasticity    │ HomeostaticTuner        │ History →    │
│ (homeostasis)          │                         │ adaptation   │
├────────────────────────┼─────────────────────────┼──────────────┤
│ Suprachiasmatic Nucl.  │ CircadianScheduler      │ Time →       │
│ (circadian rhythms)    │                         │ prediction   │
└────────────────────────┴─────────────────────────┴──────────────┘
```

---

## Implementation Phases

### Phase Overview

| Phase | Module | Complexity | Duration | Impact |
|-------|--------|------------|----------|--------|
| 1 | NoveltyDetector | Low | 3-4 days | High |
| 2 | PredictiveLoadBalancer | Medium | 1-2 weeks | High |
| 3 | HomeostaticTuner | Low | 2-3 days | Medium |
| 4 | ResourceArbiter | Medium | 1 week | Medium |
| 5 | CircadianScheduler | Low | 3-4 days | Low |

---

## Phase 1: NoveltyDetector (Locus Coeruleus)

### Biological Inspiration

The locus coeruleus detects novelty and floods the brain with norepinephrine, instantly boosting alertness. We replicate this by:
- Tracking baseline statistics per sensor/attribute
- Detecting statistical anomalies (z-score > 3.0)
- Auto-boosting attention for anomalous data

### File: `lib/sensocto/bio/novelty_detector.ex`

```elixir
defmodule Sensocto.Bio.NoveltyDetector do
  @moduledoc """
  Locus Coeruleus-inspired novelty detection.

  Detects anomalous sensor readings using online statistics (Welford's algorithm)
  and broadcasts attention boosts for novel events.

  ## How It Works

  1. Each sensor/attribute pair maintains running mean and variance
  2. New values are compared against baseline (z-score calculation)
  3. Values beyond threshold (default: 3.0 = 99.7th percentile) trigger novelty
  4. Novelty events broadcast via PubSub, causing temporary attention boost

  ## Example

      # Normal temperature readings: 22.0 ± 0.5°C
      # Spike to 45.0°C triggers z-score of ~46
      # NoveltyDetector broadcasts {:novelty_detected, ...}
      # AttributeServer receives and boosts to :high attention
  """

  use GenServer
  require Logger

  @novelty_threshold 3.0  # Standard deviations (99.7th percentile)
  @min_samples 10         # Need baseline before detecting novelty
  @decay_rate 0.01        # How fast baseline adapts (lower = more stable)

  defstruct [
    sensor_stats: %{},      # %{{sensor_id, attribute_id} => stats}
    novelty_events: [],     # Recent novelty events for debugging
    threshold: @novelty_threshold
  ]

  # Stats structure for Welford's online algorithm
  defmodule Stats do
    defstruct [:mean, :m2, :count, :last_novelty]

    def new, do: %__MODULE__{mean: 0.0, m2: 0.0, count: 0, last_novelty: nil}
  end

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Report a batch of sensor readings for novelty analysis.

  Called by AttributeServer after pushing data.
  Non-blocking cast to avoid slowing down data pipeline.
  """
  def report_batch(sensor_id, attribute_id, batch) when is_list(batch) do
    GenServer.cast(__MODULE__, {:report_batch, sensor_id, attribute_id, batch})
  end

  @doc """
  Get current novelty score for a sensor/attribute.
  Returns 0.0-1.0 where 1.0 = highly anomalous.
  """
  def get_novelty_score(sensor_id, attribute_id) do
    case :ets.lookup(:novelty_scores, {sensor_id, attribute_id}) do
      [{_, score, _timestamp}] -> score
      [] -> 0.0
    end
  end

  @doc """
  Get baseline statistics for debugging.
  """
  def get_stats(sensor_id, attribute_id) do
    GenServer.call(__MODULE__, {:get_stats, sensor_id, attribute_id})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    # ETS for fast concurrent reads of novelty scores
    :ets.new(:novelty_scores, [:named_table, :public, read_concurrency: true])

    threshold = Keyword.get(opts, :threshold, @novelty_threshold)

    Logger.info("NoveltyDetector started with threshold: #{threshold} sigma")

    {:ok, %__MODULE__{threshold: threshold}}
  end

  @impl true
  def handle_cast({:report_batch, sensor_id, attribute_id, batch}, state) do
    key = {sensor_id, attribute_id}

    # Get or create stats
    stats = Map.get(state.sensor_stats, key, Stats.new())

    # Extract numeric values from batch
    values = extract_values(batch)

    if length(values) > 0 do
      # Update stats and check for novelty
      {new_stats, max_z_score} = process_values(stats, values)

      # Calculate novelty score (sigmoid of z-score)
      novelty_score = sigmoid(max_z_score - state.threshold)

      # Update ETS cache
      :ets.insert(:novelty_scores, {key, novelty_score, System.system_time(:millisecond)})

      # Check for novelty event
      new_state =
        if max_z_score > state.threshold and new_stats.count >= @min_samples do
          handle_novelty_detected(sensor_id, attribute_id, max_z_score, novelty_score, state)
        else
          state
        end

      # Update stats
      new_sensor_stats = Map.put(new_state.sensor_stats, key, new_stats)
      {:noreply, %{new_state | sensor_stats: new_sensor_stats}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:get_stats, sensor_id, attribute_id}, _from, state) do
    stats = Map.get(state.sensor_stats, {sensor_id, attribute_id})
    {:reply, stats, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp extract_values(batch) do
    batch
    |> Enum.flat_map(fn
      %{payload: %{value: v}} when is_number(v) -> [v]
      %{payload: %{level: v}} when is_number(v) -> [v]
      %{payload: %{temperature: v}} when is_number(v) -> [v]
      %{payload: %{humidity: v}} when is_number(v) -> [v]
      %{payload: %{pressure: v}} when is_number(v) -> [v]
      %{"payload" => %{"value" => v}} when is_number(v) -> [v]
      %{"payload" => %{"level" => v}} when is_number(v) -> [v]
      _ -> []
    end)
  end

  # Welford's online algorithm for running mean and variance
  defp process_values(stats, values) do
    Enum.reduce(values, {stats, 0.0}, fn value, {s, max_z} ->
      # Calculate z-score BEFORE updating (compare against baseline)
      z_score = if s.count > 1 do
        stddev = :math.sqrt(s.m2 / (s.count - 1))
        if stddev > 0.001, do: abs(value - s.mean) / stddev, else: 0.0
      else
        0.0
      end

      # Update running statistics
      count = s.count + 1
      delta = value - s.mean
      mean = s.mean + delta / count
      delta2 = value - mean
      m2 = s.m2 + delta * delta2

      new_stats = %{s | mean: mean, m2: m2, count: count}

      {new_stats, max(max_z, z_score)}
    end)
  end

  defp handle_novelty_detected(sensor_id, attribute_id, z_score, novelty_score, state) do
    now = System.system_time(:millisecond)
    stats = Map.get(state.sensor_stats, {sensor_id, attribute_id}, Stats.new())

    # Debounce: don't fire again within 10 seconds
    should_fire = case stats.last_novelty do
      nil -> true
      last -> now - last > 10_000
    end

    if should_fire do
      Logger.warning(
        "Novelty detected: #{sensor_id}/#{attribute_id} " <>
        "z=#{Float.round(z_score, 2)}, score=#{Float.round(novelty_score, 2)}"
      )

      # Broadcast novelty event
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "novelty:#{sensor_id}",
        {:novelty_detected, %{
          sensor_id: sensor_id,
          attribute_id: attribute_id,
          z_score: z_score,
          novelty_score: novelty_score,
          boost_duration: calculate_boost_duration(z_score),
          timestamp: now
        }}
      )

      # Also broadcast to global channel for monitoring
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "novelty:global",
        {:novelty_detected, sensor_id, attribute_id, z_score}
      )

      # Update last novelty time
      updated_stats = %{stats | last_novelty: now}
      updated_sensor_stats = Map.put(state.sensor_stats, {sensor_id, attribute_id}, updated_stats)

      # Keep event log (last 100)
      event = %{sensor_id: sensor_id, attribute_id: attribute_id, z_score: z_score, time: now}
      events = Enum.take([event | state.novelty_events], 100)

      %{state | sensor_stats: updated_sensor_stats, novelty_events: events}
    else
      state
    end
  end

  # Longer boost for more extreme anomalies
  defp calculate_boost_duration(z_score) do
    base = 10_000  # 10 seconds minimum
    extra = min(z_score - @novelty_threshold, 10) * 5_000  # Up to 50s extra
    trunc(base + extra)
  end

  # Sigmoid function: maps any real number to 0.0-1.0
  defp sigmoid(x), do: 1.0 / (1.0 + :math.exp(-x))
end
```

### Integration with AttributeServer

Add to `lib/sensocto/simulator/attribute_server.ex`:

```elixir
# In init/1 - Subscribe to novelty events
def init(config) do
  # ... existing code ...

  # Subscribe to novelty events for this sensor
  Phoenix.PubSub.subscribe(Sensocto.PubSub, "novelty:#{sensor_id}")

  # Add to state
  state = %{
    # ... existing fields ...
    novelty_boosted: false,
    novelty_boost_until: nil
  }

  {:ok, state}
end

# Handle novelty boost
def handle_info({:novelty_detected, %{attribute_id: attr_id, boost_duration: duration}}, state) do
  if attr_id == state.attribute_id_str do
    Logger.info("Novelty boost for #{state.sensor_id}/#{attr_id}, duration: #{duration}ms")

    boost_until = System.system_time(:millisecond) + duration

    # Recalculate batch window with :high attention
    new_window = Sensocto.AttentionTracker.calculate_batch_window(
      state.base_batch_window,
      state.sensor_id,
      state.attribute_id_str
    )

    # Force to minimum window during boost
    boosted_window = min(new_window, 500)  # Max 500ms during novelty

    {:noreply, %{state |
      attention_level: :high,
      current_batch_window: boosted_window,
      novelty_boosted: true,
      novelty_boost_until: boost_until
    }}
  else
    {:noreply, state}
  end
end

# Check boost expiry in existing timer
def handle_info(:push_batch, state) do
  # Check if novelty boost expired
  state = if state.novelty_boosted do
    now = System.system_time(:millisecond)
    if now >= state.novelty_boost_until do
      # Return to normal attention
      attention = Sensocto.AttentionTracker.get_attention_level(
        state.sensor_id,
        state.attribute_id_str
      )
      window = Sensocto.AttentionTracker.calculate_batch_window(
        state.base_batch_window,
        state.sensor_id,
        state.attribute_id_str
      )
      %{state | attention_level: attention, current_batch_window: window, novelty_boosted: false}
    else
      state
    end
  else
    state
  end

  # ... existing push logic ...

  # Report batch to novelty detector
  unless state.paused or Enum.empty?(state.batch) do
    Sensocto.Bio.NoveltyDetector.report_batch(
      state.sensor_id,
      state.attribute_id_str,
      state.batch
    )
  end

  # ... rest of existing code ...
end
```

### Add to Supervision Tree

In `lib/sensocto/application.ex`:

```elixir
children = [
  # ... existing children ...

  # Biomimetic layer
  Sensocto.Bio.NoveltyDetector,
]
```

### Testing

```elixir
# test/sensocto/bio/novelty_detector_test.exs
defmodule Sensocto.Bio.NoveltyDetectorTest do
  use ExUnit.Case, async: false

  alias Sensocto.Bio.NoveltyDetector

  setup do
    start_supervised!(NoveltyDetector)
    :ok
  end

  describe "baseline learning" do
    test "builds baseline from consistent values" do
      sensor_id = "test_sensor"
      attribute_id = "temperature"

      # Feed 20 consistent values
      for _ <- 1..20 do
        batch = [%{payload: %{value: 22.0 + :rand.normal() * 0.5}}]
        NoveltyDetector.report_batch(sensor_id, attribute_id, batch)
      end

      # Allow processing
      Process.sleep(100)

      stats = NoveltyDetector.get_stats(sensor_id, attribute_id)
      assert stats.count == 20
      assert_in_delta stats.mean, 22.0, 1.0
    end
  end

  describe "novelty detection" do
    test "detects spike anomaly" do
      sensor_id = "test_sensor_2"
      attribute_id = "temperature"

      # Establish baseline
      for _ <- 1..50 do
        batch = [%{payload: %{value: 22.0 + :rand.normal() * 0.3}}]
        NoveltyDetector.report_batch(sensor_id, attribute_id, batch)
      end

      # Subscribe to novelty events
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "novelty:#{sensor_id}")

      # Inject anomaly
      batch = [%{payload: %{value: 45.0}}]  # Way outside normal
      NoveltyDetector.report_batch(sensor_id, attribute_id, batch)

      # Should receive novelty event
      assert_receive {:novelty_detected, %{z_score: z}}, 1000
      assert z > 3.0
    end

    test "does not fire on gradual drift" do
      sensor_id = "test_sensor_3"
      attribute_id = "temperature"

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "novelty:#{sensor_id}")

      # Gradual increase (baseline adapts)
      for i <- 1..100 do
        value = 20.0 + i * 0.1  # Slow drift from 20 to 30
        batch = [%{payload: %{value: value}}]
        NoveltyDetector.report_batch(sensor_id, attribute_id, batch)
      end

      # Should NOT receive novelty (baseline adapted)
      refute_receive {:novelty_detected, _}, 500
    end
  end
end
```

---

## Phase 2: PredictiveLoadBalancer (Cerebellum)

### Biological Inspiration

The cerebellum maintains forward models that predict sensory consequences 50-200ms before they occur. We replicate this by:
- Learning temporal patterns (hourly, daily, weekly)
- Predicting attention changes before they happen
- Pre-adjusting resources

### File: `lib/sensocto/bio/predictive_load_balancer.ex`

```elixir
defmodule Sensocto.Bio.PredictiveLoadBalancer do
  @moduledoc """
  Cerebellum-inspired predictive load balancing.

  Learns temporal patterns in sensor attention and predicts future load.
  Pre-adjusts batch windows before attention changes occur.

  ## Pattern Learning

  - Tracks attention events with timestamps
  - Identifies hourly patterns (e.g., "sensor X gets high attention at 9am")
  - Stores patterns in ETS for O(1) lookup

  ## Prediction

  - Every minute, checks if predictions apply
  - 5 minutes before predicted spike: pre-boost (0.8x multiplier)
  - After spike passes: gradual ramp-down (1.2x multiplier)
  """

  use GenServer
  require Logger

  @history_days 14       # Keep 2 weeks of history
  @analysis_interval :timer.hours(1)
  @prediction_window 600  # Predict 10 minutes ahead
  @confidence_threshold 0.7

  defstruct [
    attention_history: [],      # [{sensor_id, timestamp, attention_level}]
    hourly_patterns: %{},       # %{sensor_id => %{hour => {avg_attention, confidence}}}
    daily_patterns: %{},        # %{sensor_id => %{day_of_week => %{hour => ...}}}
    predictions: %{},           # %{sensor_id => {:pre_boost | :post_peak | :normal, seconds}}
    last_analysis: nil
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record an attention event for pattern learning.
  Called when attention level changes.
  """
  def record_attention(sensor_id, attention_level) do
    GenServer.cast(__MODULE__, {:record_attention, sensor_id, attention_level})
  end

  @doc """
  Get predictive adjustment factor for a sensor.
  Returns multiplier (< 1.0 = pre-boost, > 1.0 = post-peak slowdown).
  """
  def get_predictive_factor(sensor_id) do
    case :ets.lookup(:predictions, sensor_id) do
      [{_, {:pre_boost, seconds_until}}] ->
        # Gradually increase boost as we approach the peak
        # 10 min out: 0.95x, 5 min out: 0.85x, 1 min out: 0.75x
        boost = 0.95 - (1 - seconds_until / @prediction_window) * 0.2
        max(0.75, boost)

      [{_, {:post_peak, seconds_since}}] ->
        # Gradually reduce after peak
        # Just passed: 1.0x, 5 min later: 1.1x, 10 min later: 1.2x
        slowdown = 1.0 + min(seconds_since / @prediction_window, 1.0) * 0.2
        min(1.2, slowdown)

      _ ->
        1.0  # No prediction
    end
  end

  @doc """
  Get current predictions for monitoring.
  """
  def get_predictions do
    :ets.tab2list(:predictions) |> Map.new()
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
    # ETS for fast prediction lookups
    :ets.new(:predictions, [:named_table, :public, read_concurrency: true])
    :ets.new(:attention_history, [:named_table, :public, :bag])

    # Schedule periodic analysis
    Process.send_after(self(), :analyze_patterns, @analysis_interval)
    Process.send_after(self(), :update_predictions, :timer.minutes(1))

    Logger.info("PredictiveLoadBalancer started")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:record_attention, sensor_id, attention_level}, state) do
    now = DateTime.utc_now()

    # Store in ETS for persistence
    event = {sensor_id, now, attention_to_score(attention_level)}
    :ets.insert(:attention_history, event)

    # Also keep in-memory for quick access
    history = [{sensor_id, now, attention_level} | state.attention_history]
    history = Enum.take(history, 10_000)  # Keep last 10k events in memory

    {:noreply, %{state | attention_history: history}}
  end

  @impl true
  def handle_info(:analyze_patterns, state) do
    Logger.info("PredictiveLoadBalancer: Analyzing patterns...")

    # Get history from last N days
    cutoff = DateTime.add(DateTime.utc_now(), -@history_days * 24 * 60 * 60)

    history = :ets.select(:attention_history, [
      {{:"$1", :"$2", :"$3"}, [{:>, :"$2", cutoff}], [{{:"$1", :"$2", :"$3"}}]}
    ])

    # Analyze hourly patterns per sensor
    hourly_patterns = analyze_hourly_patterns(history)

    # Analyze day-of-week patterns (optional, for weekly cycles)
    daily_patterns = analyze_daily_patterns(history)

    Logger.info("Patterns learned for #{map_size(hourly_patterns)} sensors")

    # Clean old history
    cleanup_old_history(cutoff)

    # Schedule next analysis
    Process.send_after(self(), :analyze_patterns, @analysis_interval)

    {:noreply, %{state |
      hourly_patterns: hourly_patterns,
      daily_patterns: daily_patterns,
      last_analysis: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_info(:update_predictions, state) do
    now = DateTime.utc_now()
    hour = now.hour
    next_hour = rem(hour + 1, 24)

    # Generate predictions based on patterns
    predictions = Enum.flat_map(state.hourly_patterns, fn {sensor_id, pattern} ->
      current_attention = Map.get(pattern, hour, {0.5, 0.0})
      next_attention = Map.get(pattern, next_hour, {0.5, 0.0})

      {current_avg, _} = current_attention
      {next_avg, next_confidence} = next_attention

      cond do
        # Next hour is significantly higher AND confident
        next_avg > current_avg + 0.3 and next_confidence >= @confidence_threshold ->
          minutes_until_next_hour = 60 - now.minute
          [{sensor_id, {:pre_boost, minutes_until_next_hour * 60}}]

        # Current hour was a peak, ramping down
        current_avg > next_avg + 0.3 and next_confidence >= @confidence_threshold ->
          minutes_since_hour = now.minute
          [{sensor_id, {:post_peak, minutes_since_hour * 60}}]

        true ->
          []
      end
    end)

    # Update ETS
    :ets.delete_all_objects(:predictions)
    Enum.each(predictions, fn {sensor_id, prediction} ->
      :ets.insert(:predictions, {sensor_id, prediction})
    end)

    # Schedule next update
    Process.send_after(self(), :update_predictions, :timer.minutes(1))

    {:noreply, %{state | predictions: Map.new(predictions)}}
  end

  @impl true
  def handle_call({:get_patterns, sensor_id}, _from, state) do
    hourly = Map.get(state.hourly_patterns, sensor_id, %{})
    daily = Map.get(state.daily_patterns, sensor_id, %{})
    {:reply, %{hourly: hourly, daily: daily}, state}
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
    # Group by sensor_id and hour
    history
    |> Enum.group_by(fn {sensor_id, datetime, _score} ->
      {sensor_id, datetime.hour}
    end)
    |> Enum.map(fn {{sensor_id, hour}, events} ->
      scores = Enum.map(events, fn {_, _, score} -> score end)
      avg = Enum.sum(scores) / length(scores)

      # Confidence based on sample size and variance
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

  defp analyze_daily_patterns(history) do
    # Group by sensor_id, day-of-week, and hour
    history
    |> Enum.group_by(fn {sensor_id, datetime, _score} ->
      day = Date.day_of_week(DateTime.to_date(datetime))
      {sensor_id, day, datetime.hour}
    end)
    |> Enum.map(fn {{sensor_id, day, hour}, events} ->
      scores = Enum.map(events, fn {_, _, score} -> score end)
      avg = Enum.sum(scores) / length(scores)
      variance = calculate_variance(scores, avg)
      confidence = calculate_confidence(length(scores), variance)

      {{sensor_id, day, hour}, {avg, confidence}}
    end)
    |> Enum.group_by(fn {{sensor_id, day, _hour}, _} -> {sensor_id, day} end)
    |> Enum.map(fn {{sensor_id, day}, hour_data} ->
      hours = Enum.map(hour_data, fn {{_, _, hour}, data} -> {hour, data} end) |> Map.new()
      {{sensor_id, day}, hours}
    end)
    |> Enum.group_by(fn {{sensor_id, _day}, _} -> sensor_id end)
    |> Enum.map(fn {sensor_id, day_data} ->
      pattern = Enum.map(day_data, fn {{_, day}, hours} -> {day, hours} end) |> Map.new()
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
    # More samples and less variance = higher confidence
    size_factor = min(sample_size / 50, 1.0)  # Max confidence at 50 samples
    variance_factor = 1.0 / (1.0 + variance * 10)  # Lower variance = higher confidence

    size_factor * variance_factor
  end

  defp cleanup_old_history(cutoff) do
    # Delete old events from ETS
    :ets.select_delete(:attention_history, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$2", cutoff}], [true]}
    ])
  end
end
```

### Integration with AttentionTracker

In `lib/sensocto/otp/attention_tracker.ex`, modify `calculate_batch_window/3`:

```elixir
def calculate_batch_window(base_window, sensor_id, attribute_id) do
  config = get_attention_config(sensor_id, attribute_id)
  load_multiplier = Sensocto.SystemLoadMonitor.get_load_multiplier()

  # NEW: Get predictive factor from PredictiveLoadBalancer
  predictive_factor = Sensocto.Bio.PredictiveLoadBalancer.get_predictive_factor(sensor_id)

  adjusted = trunc(
    base_window *
    config.window_multiplier *
    load_multiplier *
    predictive_factor  # NEW
  )

  max(config.min_window, min(adjusted, config.max_window))
end

# Also record attention changes for learning
def handle_cast({:register_view, sensor_id, attribute_id, user_id}, state) do
  # ... existing logic ...

  # NEW: Record for pattern learning
  new_level = get_attention_level(sensor_id, attribute_id)
  Sensocto.Bio.PredictiveLoadBalancer.record_attention(sensor_id, new_level)

  {:noreply, new_state}
end
```

---

## Phase 3: HomeostaticTuner (Synaptic Plasticity)

### Biological Inspiration

Neurons maintain homeostatic balance by self-adjusting their sensitivity thresholds. We replicate this by tracking the distribution of load states and adapting thresholds to match a target distribution.

### File: `lib/sensocto/bio/homeostatic_tuner.ex`

```elixir
defmodule Sensocto.Bio.HomeostaticTuner do
  @moduledoc """
  Homeostatic plasticity-inspired threshold adaptation.

  Self-tunes load thresholds based on historical distribution.
  Goal: Maintain target distribution of time spent in each load state.

  ## Target Distribution

  - :normal   → 70% of time (healthy operation)
  - :elevated → 20% of time (occasional load)
  - :high     → 8% of time (peak periods)
  - :critical → 2% of time (rare emergencies)

  ## Adaptation

  If spending too much time in :critical, raise the threshold (harder to enter).
  If spending too little time in :normal, lower the :elevated threshold.
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
  @adaptation_rate 0.005  # Slow adaptation (0.5% per hour max)
  @sample_buffer_size 3600  # 1 hour of samples at 1/second

  defstruct [
    load_samples: [],           # Circular buffer of load levels
    threshold_offsets: %{       # Current adjustments
      elevated: 0.0,
      high: 0.0,
      critical: 0.0
    },
    last_adaptation: nil,
    actual_distribution: %{}
  ]

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
    case :ets.lookup(:homeostatic_offsets, :offsets) do
      [{_, offsets}] -> offsets
      [] -> %{elevated: 0.0, high: 0.0, critical: 0.0}
    end
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
    :ets.new(:homeostatic_offsets, [:named_table, :public, read_concurrency: true])
    :ets.insert(:homeostatic_offsets, {:offsets, %{elevated: 0.0, high: 0.0, critical: 0.0}})

    # Schedule periodic adaptation
    Process.send_after(self(), :adapt, @adaptation_interval)

    Logger.info("HomeostaticTuner started with target: #{inspect(@target_distribution)}")

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
    if length(state.load_samples) >= 100 do
      # Calculate actual distribution
      actual_dist = calculate_distribution(state.load_samples)

      # Calculate new offsets
      new_offsets = calculate_offsets(actual_dist, state.threshold_offsets)

      # Update ETS
      :ets.insert(:homeostatic_offsets, {:offsets, new_offsets})

      Logger.info(
        "Homeostatic adaptation: " <>
        "actual=#{inspect(actual_dist)}, " <>
        "offsets=#{inspect(new_offsets)}"
      )

      # Broadcast for monitoring
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "system:homeostasis",
        {:adaptation, %{actual: actual_dist, offsets: new_offsets}}
      )

      Process.send_after(self(), :adapt, @adaptation_interval)

      {:noreply, %{state |
        threshold_offsets: new_offsets,
        actual_distribution: actual_dist,
        last_adaptation: DateTime.utc_now()
      }}
    else
      # Not enough samples yet
      Process.send_after(self(), :adapt, @adaptation_interval)
      {:noreply, state}
    end
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
    # For each threshold level, adjust based on error
    Enum.reduce([:elevated, :high, :critical], current_offsets, fn level, offsets ->
      target = Map.get(@target_distribution, level, 0.0)
      actual = Map.get(actual_dist, level, 0.0)
      error = actual - target  # Positive = too much time in this state

      # Adjust threshold: positive error → raise threshold (harder to enter)
      current_offset = Map.get(offsets, level, 0.0)
      adjustment = error * @adaptation_rate

      # Clamp offset to reasonable range (-0.1 to +0.1)
      new_offset = current_offset + adjustment
      new_offset = max(-0.1, min(0.1, new_offset))

      Map.put(offsets, level, new_offset)
    end)
  end
end
```

### Integration with SystemLoadMonitor

In `lib/sensocto/otp/system_load_monitor.ex`:

```elixir
defp determine_load_level(pressure) do
  # Get homeostatic offsets
  offsets = Sensocto.Bio.HomeostaticTuner.get_offsets()

  # Apply offsets to thresholds
  adjusted = %{
    normal: @load_thresholds.normal,
    elevated: @load_thresholds.elevated + Map.get(offsets, :elevated, 0.0),
    high: @load_thresholds.high + Map.get(offsets, :high, 0.0),
    critical: @load_thresholds.critical + Map.get(offsets, :critical, 0.0)
  }

  level = cond do
    pressure >= adjusted.critical -> :critical
    pressure >= adjusted.high -> :high
    pressure >= adjusted.elevated -> :elevated
    true -> :normal
  end

  # Record for homeostatic tuning
  Sensocto.Bio.HomeostaticTuner.record_sample(level)

  level
end
```

---

## Phase 4: ResourceArbiter (Lateral Inhibition)

### File: `lib/sensocto/bio/resource_arbiter.ex`

```elixir
defmodule Sensocto.Bio.ResourceArbiter do
  @moduledoc """
  Retina-inspired lateral inhibition for resource allocation.

  Implements competitive resource allocation where high-priority
  sensors suppress low-priority sensors during contention.
  """

  use GenServer
  require Logger

  @reallocation_interval 5_000  # Every 5 seconds
  @power_law_exponent 1.3       # > 1.0 = winner-take-more

  defstruct [
    sensor_priorities: %{},
    allocations: %{},
    total_sensors: 0,
    last_allocation: nil
  ]

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
    case :ets.lookup(:resource_allocations, sensor_id) do
      [{_, multiplier}] -> multiplier
      [] -> 1.0  # Default: no adjustment
    end
  end

  @doc """
  Force reallocation (for testing).
  """
  def reallocate do
    GenServer.call(__MODULE__, :reallocate)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    :ets.new(:resource_allocations, [:named_table, :public, read_concurrency: true])

    Process.send_after(self(), :reallocate, @reallocation_interval)

    Logger.info("ResourceArbiter started")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:reallocate, state) do
    # Get all active sensors from registry
    sensors = list_active_sensors()

    if length(sensors) > 0 do
      # Calculate priorities
      priorities = Enum.map(sensors, fn sensor_id ->
        priority = calculate_priority(sensor_id)
        {sensor_id, priority}
      end) |> Map.new()

      # Allocate with lateral inhibition
      allocations = allocate_with_inhibition(priorities)

      # Update ETS
      Enum.each(allocations, fn {sensor_id, multiplier} ->
        :ets.insert(:resource_allocations, {sensor_id, multiplier})
      end)

      Process.send_after(self(), :reallocate, @reallocation_interval)

      {:noreply, %{state |
        sensor_priorities: priorities,
        allocations: allocations,
        total_sensors: length(sensors),
        last_allocation: DateTime.utc_now()
      }}
    else
      Process.send_after(self(), :reallocate, @reallocation_interval)
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:reallocate, _from, state) do
    send(self(), :reallocate)
    {:reply, :ok, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp list_active_sensors do
    # Get from SimpleSensorRegistry
    case Registry.select(Sensocto.SimpleSensorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      sensors when is_list(sensors) -> sensors
      _ -> []
    end
  end

  defp calculate_priority(sensor_id) do
    # Multi-factor priority calculation
    attention = get_attention_score(sensor_id)
    novelty = Sensocto.Bio.NoveltyDetector.get_novelty_score(sensor_id, "*")

    # Weights: attention 50%, novelty 30%, base 20%
    0.5 * attention + 0.3 * novelty + 0.2 * 0.5
  end

  defp get_attention_score(sensor_id) do
    case Sensocto.AttentionTracker.get_sensor_attention_level(sensor_id) do
      :high -> 1.0
      :medium -> 0.6
      :low -> 0.3
      :none -> 0.1
      _ -> 0.5
    end
  end

  defp allocate_with_inhibition(priorities) do
    # Sort by priority (highest first)
    sorted = Enum.sort_by(priorities, fn {_, p} -> -p end)
    total_priority = Enum.sum(Enum.map(sorted, fn {_, p} -> max(p, 0.01) end))

    # Competitive allocation using power law
    Enum.map(sorted, fn {sensor_id, priority} ->
      # Fraction of total priority (with power law for winner-take-more)
      fraction = :math.pow(max(priority, 0.01) / total_priority, @power_law_exponent)

      # Convert to multiplier: high fraction = low multiplier (faster)
      # fraction ∈ [0, 1] → multiplier ∈ [5.0, 0.5]
      multiplier = 5.0 - fraction * 4.5
      multiplier = max(0.5, min(5.0, multiplier))

      {sensor_id, multiplier}
    end) |> Map.new()
  end
end
```

---

## Phase 5: CircadianScheduler (Suprachiasmatic Nucleus)

### File: `lib/sensocto/bio/circadian_scheduler.ex`

```elixir
defmodule Sensocto.Bio.CircadianScheduler do
  @moduledoc """
  SCN-inspired circadian rhythm awareness.

  Learns daily patterns and pre-adjusts for predictable peaks.
  """

  use GenServer
  require Logger

  @phase_check_interval :timer.minutes(10)
  @profile_learning_interval :timer.hours(24)

  defstruct [
    hourly_profile: %{},      # %{hour => avg_load}
    current_phase: :unknown,
    phase_adjustment: 1.0
  ]

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
    case :ets.lookup(:circadian_state, :adjustment) do
      [{_, adj}] -> adj
      [] -> 1.0
    end
  end

  @doc """
  Get current phase for monitoring.
  """
  def get_phase do
    case :ets.lookup(:circadian_state, :phase) do
      [{_, phase}] -> phase
      [] -> :unknown
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    :ets.new(:circadian_state, [:named_table, :public, read_concurrency: true])
    :ets.insert(:circadian_state, {:adjustment, 1.0})
    :ets.insert(:circadian_state, {:phase, :unknown})

    Process.send_after(self(), :check_phase, @phase_check_interval)
    Process.send_after(self(), :learn_profile, @profile_learning_interval)

    Logger.info("CircadianScheduler started")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:check_phase, state) do
    now = DateTime.utc_now()
    hour = now.hour
    next_hour = rem(hour + 1, 24)

    # Get predicted load for current and next hour
    current_load = Map.get(state.hourly_profile, hour, 0.5)
    next_load = Map.get(state.hourly_profile, next_hour, 0.5)

    # Determine phase
    new_phase = cond do
      next_load > 0.7 -> :approaching_peak
      current_load > 0.7 -> :peak
      next_load < 0.3 -> :approaching_off_peak
      current_load < 0.3 -> :off_peak
      true -> :normal
    end

    # Calculate adjustment
    adjustment = case new_phase do
      :approaching_peak -> 1.15    # Pre-throttle
      :peak -> 1.2                  # Full throttle
      :approaching_off_peak -> 0.9 # Pre-boost
      :off_peak -> 0.85            # Full boost
      :normal -> 1.0
    end

    if new_phase != state.current_phase do
      Logger.info("Circadian phase: #{state.current_phase} → #{new_phase}, adj=#{adjustment}")

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "system:circadian",
        {:phase_change, %{phase: new_phase, adjustment: adjustment}}
      )
    end

    :ets.insert(:circadian_state, {:adjustment, adjustment})
    :ets.insert(:circadian_state, {:phase, new_phase})

    Process.send_after(self(), :check_phase, @phase_check_interval)

    {:noreply, %{state | current_phase: new_phase, phase_adjustment: adjustment}}
  end

  @impl true
  def handle_info(:learn_profile, state) do
    # Get load samples from HomeostaticTuner
    tuner_state = Sensocto.Bio.HomeostaticTuner.get_state()
    samples = tuner_state.load_samples

    if length(samples) > 100 do
      # This is simplified - in production, you'd track timestamps
      # For now, assume samples are evenly distributed
      profile = %{
        0 => 0.2, 1 => 0.15, 2 => 0.1, 3 => 0.1, 4 => 0.1, 5 => 0.15,
        6 => 0.3, 7 => 0.5, 8 => 0.7, 9 => 0.8, 10 => 0.75, 11 => 0.7,
        12 => 0.6, 13 => 0.65, 14 => 0.7, 15 => 0.65, 16 => 0.6, 17 => 0.5,
        18 => 0.4, 19 => 0.35, 20 => 0.3, 21 => 0.25, 22 => 0.2, 23 => 0.2
      }

      Logger.info("Circadian profile learned")

      Process.send_after(self(), :learn_profile, @profile_learning_interval)
      {:noreply, %{state | hourly_profile: profile}}
    else
      Process.send_after(self(), :learn_profile, @profile_learning_interval)
      {:noreply, state}
    end
  end
end
```

---

## Supervision Tree

### File: `lib/sensocto/bio/supervisor.ex`

```elixir
defmodule Sensocto.Bio.Supervisor do
  @moduledoc """
  Supervisor for all biomimetic components.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Phase 1: Novelty Detection (no dependencies)
      Sensocto.Bio.NoveltyDetector,

      # Phase 2: Predictive Load Balancing (no dependencies)
      Sensocto.Bio.PredictiveLoadBalancer,

      # Phase 3: Homeostatic Tuning (no dependencies)
      Sensocto.Bio.HomeostaticTuner,

      # Phase 4: Resource Arbitration (depends on NoveltyDetector)
      Sensocto.Bio.ResourceArbiter,

      # Phase 5: Circadian Scheduling (depends on HomeostaticTuner)
      Sensocto.Bio.CircadianScheduler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Add to Application

In `lib/sensocto/application.ex`:

```elixir
children = [
  # ... existing children ...

  # Biomimetic layer (add after AttentionTracker and SystemLoadMonitor)
  Sensocto.Bio.Supervisor,
]
```

---

## Integration: Enhanced calculate_batch_window

The final integration point - all factors combined:

```elixir
# In lib/sensocto/otp/attention_tracker.ex

def calculate_batch_window(base_window, sensor_id, attribute_id) do
  # Existing factors
  config = get_attention_config(sensor_id, attribute_id)
  load_multiplier = Sensocto.SystemLoadMonitor.get_load_multiplier()

  # NEW: Biomimetic factors
  novelty_factor = if Code.ensure_loaded?(Sensocto.Bio.NoveltyDetector) do
    score = Sensocto.Bio.NoveltyDetector.get_novelty_score(sensor_id, attribute_id)
    if score > 0.5, do: 0.5, else: 1.0  # Boost for novelty
  else
    1.0
  end

  predictive_factor = if Code.ensure_loaded?(Sensocto.Bio.PredictiveLoadBalancer) do
    Sensocto.Bio.PredictiveLoadBalancer.get_predictive_factor(sensor_id)
  else
    1.0
  end

  competitive_factor = if Code.ensure_loaded?(Sensocto.Bio.ResourceArbiter) do
    Sensocto.Bio.ResourceArbiter.get_multiplier(sensor_id)
  else
    1.0
  end

  circadian_factor = if Code.ensure_loaded?(Sensocto.Bio.CircadianScheduler) do
    Sensocto.Bio.CircadianScheduler.get_phase_adjustment()
  else
    1.0
  end

  # Combine all factors
  adjusted = trunc(
    base_window *
    config.window_multiplier *
    load_multiplier *
    novelty_factor *
    predictive_factor *
    competitive_factor *
    circadian_factor
  )

  max(config.min_window, min(adjusted, config.max_window))
end
```

---

## Monitoring Dashboard

### LiveView Component for Bio Metrics

```elixir
# lib/sensocto_web/live/bio_dashboard_live.ex
defmodule SensoctoWeb.BioDashboardLive do
  use SensoctoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "novelty:global")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:homeostasis")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:circadian")

      :timer.send_interval(5000, :refresh)
    end

    {:ok, assign(socket, metrics: get_metrics())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, metrics: get_metrics())}
  end

  @impl true
  def handle_info({:novelty_detected, sensor_id, attr_id, z_score}, socket) do
    # Flash novelty alert
    {:noreply, put_flash(socket, :info, "Novelty: #{sensor_id}/#{attr_id} (z=#{Float.round(z_score, 1)})")}
  end

  defp get_metrics do
    %{
      novelty: get_recent_novelty_events(),
      predictions: Sensocto.Bio.PredictiveLoadBalancer.get_predictions(),
      homeostasis: Sensocto.Bio.HomeostaticTuner.get_state(),
      circadian: %{
        phase: Sensocto.Bio.CircadianScheduler.get_phase(),
        adjustment: Sensocto.Bio.CircadianScheduler.get_phase_adjustment()
      }
    }
  end

  defp get_recent_novelty_events do
    # Get from NoveltyDetector state
    []
  end
end
```

---

## Testing Strategy

```elixir
# test/sensocto/bio/integration_test.exs
defmodule Sensocto.Bio.IntegrationTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Sensocto.Bio.Supervisor)
    :ok
  end

  describe "end-to-end biomimetic flow" do
    test "novelty detection triggers attention boost" do
      sensor_id = "test_sensor"
      attribute_id = "temperature"

      # Establish baseline
      for _ <- 1..50 do
        batch = [%{payload: %{value: 22.0 + :rand.normal() * 0.3}}]
        Sensocto.Bio.NoveltyDetector.report_batch(sensor_id, attribute_id, batch)
      end

      # Get baseline window
      base_window = Sensocto.AttentionTracker.calculate_batch_window(1000, sensor_id, attribute_id)

      # Inject anomaly
      batch = [%{payload: %{value: 50.0}}]
      Sensocto.Bio.NoveltyDetector.report_batch(sensor_id, attribute_id, batch)

      Process.sleep(100)

      # Window should be reduced (novelty boost)
      boosted_window = Sensocto.AttentionTracker.calculate_batch_window(1000, sensor_id, attribute_id)
      assert boosted_window < base_window
    end

    test "competitive allocation prioritizes high-attention sensors" do
      # Create two sensors
      sensor_high = "sensor_high_attention"
      sensor_low = "sensor_low_attention"

      # Set different attention levels
      Sensocto.AttentionTracker.register_view(sensor_high, "attr", "user1")
      # sensor_low has no attention

      # Force reallocation
      Sensocto.Bio.ResourceArbiter.reallocate()

      Process.sleep(100)

      # High attention sensor should get lower multiplier (more resources)
      mult_high = Sensocto.Bio.ResourceArbiter.get_multiplier(sensor_high)
      mult_low = Sensocto.Bio.ResourceArbiter.get_multiplier(sensor_low)

      assert mult_high < mult_low
    end
  end
end
```

---

## Rollout Plan

### Week 1: NoveltyDetector

1. **Day 1-2**: Implement `NoveltyDetector` module
2. **Day 3**: Integrate with `AttributeServer`
3. **Day 4**: Add to supervision tree
4. **Day 5**: Testing and tuning

### Week 2-3: PredictiveLoadBalancer

1. **Week 2**: Core implementation + history tracking
2. **Week 3**: Pattern analysis + prediction logic

### Week 4: HomeostaticTuner + ResourceArbiter

1. **Day 1-2**: HomeostaticTuner
2. **Day 3-5**: ResourceArbiter

### Week 5: CircadianScheduler + Final Integration

1. **Day 1-2**: CircadianScheduler
2. **Day 3-4**: Full integration testing
3. **Day 5**: Production deployment

---

## Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Reactive throttle events | 100/hour | 70/hour | Log analysis |
| Anomaly detection latency | N/A | <5s | NoveltyDetector timestamps |
| Prediction accuracy | N/A | >70% | Predicted vs actual attention |
| Threshold tuning frequency | Weekly | Never | Homeostatic convergence |
| Peak transition smoothness | 3 state changes | 1-2 | State change logs |

---

## Conclusion

This implementation plan transforms Sensocto from a reactive to a predictive, adaptive, content-aware system by applying biological principles:

1. **NoveltyDetector** (Locus Coeruleus): Automatic anomaly detection
2. **PredictiveLoadBalancer** (Cerebellum): Temporal pattern prediction
3. **HomeostaticTuner** (Synaptic Plasticity): Self-optimizing thresholds
4. **ResourceArbiter** (Lateral Inhibition): Competitive resource allocation
5. **CircadianScheduler** (SCN): Daily rhythm awareness

Each module is independently deployable, backward-compatible, and incrementally valuable.

**Let's go bio!**

---

*Document generated: January 12, 2026*
*Sensocto Biomimetic Enhancement Project*
