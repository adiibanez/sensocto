defmodule Sensocto.AttentionTracker do
  @moduledoc """
  Tracks user attention on sensors and attributes to enable back-pressure.

  Attention levels:
  - :high - User has attribute focused (clicked, interacting)
  - :medium - User has attribute in viewport
  - :low - Sensor connected but no users viewing
  - :none - No active connections

  Battery states (applied as modifiers):
  - :normal - No restrictions
  - :low - Cap attention at :medium (battery < 30%)
  - :critical - Cap attention at :low (battery < 15%)

  The tracker aggregates attention across all users and uses the highest
  attention level to determine data transmission rates, modified by battery state.
  """

  use GenServer
  require Logger

  @cleanup_interval :timer.seconds(30)
  @stale_threshold :timer.seconds(60)

  # Attention boost decay durations (how long boost lasts after interaction ends)
  @focus_boost_duration :timer.seconds(5)
  @hover_boost_duration :timer.seconds(2)

  # ETS table names for fast concurrent reads
  @attention_levels_table :attention_levels_cache
  @attention_config_table :attention_config_cache
  @sensor_attention_table :sensor_attention_cache

  # Batch window multipliers based on attention level
  # Medium attention needs to be responsive enough for real-time visualizations
  # like pose tracking, while still providing some back-pressure savings.
  # The max_window of 500ms ensures at least 2 updates/second even with bio multipliers.
  @attention_config %{
    high: %{window_multiplier: 0.2, min_window: 100, max_window: 500},
    medium: %{window_multiplier: 0.4, min_window: 150, max_window: 500},
    low: %{window_multiplier: 4.0, min_window: 2000, max_window: 10000},
    none: %{window_multiplier: 10.0, min_window: 5000, max_window: 30000}
  }

  defstruct [
    :attention_state,
    :pinned_sensors,
    :battery_states,
    :boost_timers,
    :last_cleanup
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register that a user is viewing an attribute (in viewport).
  """
  def register_view(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:register_view, sensor_id, attribute_id, user_id})
  end

  @doc """
  Unregister that a user is no longer viewing an attribute.
  """
  def unregister_view(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:unregister_view, sensor_id, attribute_id, user_id})
  end

  @doc """
  Register that a user is hovering over an attribute (mouse entered).
  Hover provides a temporary attention boost between viewing and focus.
  """
  def register_hover(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:register_hover, sensor_id, attribute_id, user_id})
  end

  @doc """
  Unregister hover from an attribute (mouse left).
  """
  def unregister_hover(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:unregister_hover, sensor_id, attribute_id, user_id})
  end

  @doc """
  Register that a user has focused on an attribute (clicked, interacting).
  """
  def register_focus(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:register_focus, sensor_id, attribute_id, user_id})
  end

  @doc """
  Unregister focus from an attribute.
  """
  def unregister_focus(sensor_id, attribute_id, user_id) do
    GenServer.cast(__MODULE__, {:unregister_focus, sensor_id, attribute_id, user_id})
  end

  @doc """
  Pin a sensor for high-frequency updates regardless of view state.
  """
  def pin_sensor(sensor_id, user_id) do
    GenServer.cast(__MODULE__, {:pin_sensor, sensor_id, user_id})
  end

  @doc """
  Unpin a sensor.
  """
  def unpin_sensor(sensor_id, user_id) do
    GenServer.cast(__MODULE__, {:unpin_sensor, sensor_id, user_id})
  end

  @doc """
  Remove all attention records for a user (called on disconnect).
  """
  def unregister_all(sensor_id, user_id) do
    GenServer.cast(__MODULE__, {:unregister_all, sensor_id, user_id})
  end

  @doc """
  Report battery/energy state for a user.

  Battery states: :normal, :low, :critical
  - :normal - No restrictions (charging or battery >= 30%)
  - :low - Cap attention at :medium (battery 15-30%, not charging)
  - :critical - Cap attention at :low (battery < 15%, not charging)

  Options (metadata about the source):
  - :source - Where the battery info came from (:web_api, :native_ios, :native_android, :external_api)
  - :level - Battery percentage (0-100)
  - :charging - Whether device is charging
  - :power_source - Power source type (:battery, :ac, :usb, :wireless)

  ## Examples

      # From web browser Battery API
      report_battery_state(user_id, :low, source: :web_api, level: 25, charging: false)

      # From native iOS app
      report_battery_state(user_id, :critical, source: :native_ios, level: 10)

      # From external energy API (e.g., grid carbon intensity)
      report_battery_state(user_id, :low, source: :external_api, reason: :high_carbon_intensity)

  """
  def report_battery_state(user_id, state, opts \\ [])
      when state in [:normal, :low, :critical] do
    metadata = %{
      source: Keyword.get(opts, :source, :unknown),
      level: Keyword.get(opts, :level),
      charging: Keyword.get(opts, :charging),
      power_source: Keyword.get(opts, :power_source),
      reason: Keyword.get(opts, :reason),
      reported_at: DateTime.utc_now()
    }

    GenServer.cast(__MODULE__, {:battery_state, user_id, state, metadata})
  end

  @doc """
  Get the battery state for a user.
  Returns {state, metadata} tuple or {:normal, nil} if not set.
  """
  def get_battery_state(user_id) do
    GenServer.call(__MODULE__, {:get_battery_state, user_id})
  end

  @doc """
  Get all battery states (for debugging/dashboard).
  """
  def get_all_battery_states do
    GenServer.call(__MODULE__, :get_all_battery_states)
  end

  @doc """
  Get the current attention level for an attribute.
  Returns :high, :medium, :low, or :none

  Uses ETS for fast concurrent reads - no GenServer bottleneck.
  """
  def get_attention_level(sensor_id, attribute_id) do
    case :ets.lookup(@attention_levels_table, {sensor_id, attribute_id}) do
      [{_, level}] -> level
      [] -> :none
    end
  end

  @doc """
  Get the sensor-level attention summary (highest of all attributes).

  Uses ETS for fast concurrent reads - no GenServer bottleneck.
  Falls back to GenServer call only if ETS lookup fails.
  """
  def get_sensor_attention_level(sensor_id) do
    case :ets.lookup(@sensor_attention_table, sensor_id) do
      [{_, level}] -> level
      [] -> :none
    end
  rescue
    # ETS table might not exist yet during startup
    ArgumentError -> :none
  end

  @doc """
  Get batch configuration based on attention level.
  Returns %{window_multiplier, min_window, max_window}

  Uses ETS for fast concurrent reads - no GenServer bottleneck.

  Falls back to sensor-level attention if attribute-level attention is :none.
  This ensures that when a user is viewing a sensor tile (which has medium/high
  sensor-level attention), all attributes benefit from faster updates even if
  the specific attribute hasn't been individually focused.
  """
  def get_attention_config(sensor_id, attribute_id) do
    attr_level = get_attention_level(sensor_id, attribute_id)

    # If attribute has no specific attention, use sensor-level attention as fallback
    # This handles the case where a user views a sensor tile (which tracks sensor-level
    # attention) but individual attributes haven't been hovered/focused
    level =
      if attr_level == :none do
        sensor_level = get_sensor_attention_level(sensor_id)
        if sensor_level != :none, do: sensor_level, else: attr_level
      else
        attr_level
      end

    case :ets.lookup(@attention_config_table, level) do
      [{_, config}] -> config
      [] -> @attention_config.none
    end
  end

  @doc """
  Calculate the adjusted batch window based on base window, attention, system load,
  and biomimetic factors.

  The calculation applies multiple multipliers:
  - Attention multiplier: 0.2x (high) to 10x (none) based on user attention
  - System load multiplier: 1.0x (normal) to 5x (critical) based on CPU/memory pressure
  - Novelty factor: 0.5x boost for anomalous data (from NoveltyDetector)
  - Predictive factor: 0.75x-1.2x based on learned patterns (from PredictiveLoadBalancer)
  - Competitive factor: 0.5x-5.0x based on sensor priority (from ResourceArbiter)
  - Circadian factor: 0.85x-1.2x based on time-of-day patterns (from CircadianScheduler)

  These multipliers are combined to produce the final batch window, clamped
  to the attention level's min/max bounds.
  """
  def calculate_batch_window(base_window, sensor_id, attribute_id) do
    config = get_attention_config(sensor_id, attribute_id)

    # Get system load multiplier (1.0 to 5.0)
    load_multiplier = get_system_load_multiplier()

    # Get biomimetic factors (with safe fallbacks)
    bio_factors = get_bio_factors(sensor_id, attribute_id)

    # Apply all multipliers
    adjusted =
      trunc(
        base_window *
          config.window_multiplier *
          load_multiplier *
          bio_factors.novelty *
          bio_factors.predictive *
          bio_factors.competitive *
          bio_factors.circadian
      )

    max(config.min_window, min(adjusted, config.max_window))
  end

  @doc """
  Get all biomimetic adjustment factors for a sensor.
  Returns safe defaults (1.0) if Bio modules are not available.
  """
  def get_bio_factors(sensor_id, attribute_id) do
    %{
      novelty: get_novelty_factor(sensor_id, attribute_id),
      predictive: get_predictive_factor(sensor_id),
      competitive: get_competitive_factor(sensor_id),
      circadian: get_circadian_factor()
    }
  end

  defp get_novelty_factor(sensor_id, attribute_id) do
    try do
      score = Sensocto.Bio.NoveltyDetector.get_novelty_score(sensor_id, attribute_id)
      if score > 0.5, do: 0.5, else: 1.0
    rescue
      _ -> 1.0
    catch
      :exit, _ -> 1.0
    end
  end

  defp get_predictive_factor(sensor_id) do
    try do
      Sensocto.Bio.PredictiveLoadBalancer.get_predictive_factor(sensor_id)
    rescue
      _ -> 1.0
    catch
      :exit, _ -> 1.0
    end
  end

  defp get_competitive_factor(sensor_id) do
    try do
      Sensocto.Bio.ResourceArbiter.get_multiplier(sensor_id)
    rescue
      _ -> 1.0
    catch
      :exit, _ -> 1.0
    end
  end

  defp get_circadian_factor do
    try do
      Sensocto.Bio.CircadianScheduler.get_phase_adjustment()
    rescue
      _ -> 1.0
    catch
      :exit, _ -> 1.0
    end
  end

  @doc """
  Get the current system load multiplier.
  Falls back to 1.0 if SystemLoadMonitor is not available.
  """
  def get_system_load_multiplier do
    try do
      Sensocto.SystemLoadMonitor.get_load_multiplier()
    catch
      :exit, {:noproc, _} -> 1.0
    end
  end

  @doc """
  Get full attention state for debugging/display.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables for fast concurrent reads
    :ets.new(@attention_levels_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@attention_config_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@sensor_attention_table, [:named_table, :public, read_concurrency: true])

    # Pre-populate config table (static values)
    for {level, config} <- @attention_config do
      :ets.insert(@attention_config_table, {level, config})
    end

    schedule_cleanup()

    state = %__MODULE__{
      attention_state: %{},
      pinned_sensors: %{},
      battery_states: %{},
      boost_timers: %{},
      last_cleanup: DateTime.utc_now()
    }

    Logger.info(
      "AttentionTracker started with ETS caching, battery awareness, and attention decay"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:register_view, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :add_viewer)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_view, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :remove_viewer)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:register_hover, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :add_hover)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_hover, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :remove_hover)
    # Don't broadcast immediately - schedule decay timer
    new_state = schedule_boost_decay(new_state, sensor_id, attribute_id, :hover)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:register_focus, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :add_focus)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_focus, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :remove_focus)
    # Don't broadcast immediately - schedule decay timer
    new_state = schedule_boost_decay(new_state, sensor_id, attribute_id, :focus)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:pin_sensor, sensor_id, user_id}, state) do
    pinned =
      Map.update(state.pinned_sensors, sensor_id, MapSet.new([user_id]), &MapSet.put(&1, user_id))

    new_state = %{state | pinned_sensors: pinned}

    # Update ETS cache for all attributes of this sensor (now :high)
    update_sensor_ets_cache(new_state, sensor_id)

    # Broadcast pin change for all attributes of this sensor
    broadcast_sensor_attention_change(sensor_id, :high)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unpin_sensor, sensor_id, user_id}, state) do
    pinned =
      case Map.get(state.pinned_sensors, sensor_id) do
        nil ->
          state.pinned_sensors

        users ->
          remaining = MapSet.delete(users, user_id)

          if MapSet.size(remaining) == 0 do
            Map.delete(state.pinned_sensors, sensor_id)
          else
            Map.put(state.pinned_sensors, sensor_id, remaining)
          end
      end

    new_state = %{state | pinned_sensors: pinned}

    # Update ETS cache for all attributes of this sensor
    update_sensor_ets_cache(new_state, sensor_id)

    # Recalculate and broadcast new attention level
    new_level = do_get_sensor_attention_level(new_state, sensor_id)
    broadcast_sensor_attention_change(sensor_id, new_level)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_all, sensor_id, user_id}, state) do
    # Track which attributes exist before removal (for ETS cleanup)
    old_attributes = Map.get(state.attention_state, sensor_id, %{}) |> Map.keys()

    # Remove user from all attributes of this sensor
    new_attention_state =
      case Map.get(state.attention_state, sensor_id) do
        nil ->
          state.attention_state

        attributes ->
          updated_attributes =
            Enum.reduce(attributes, %{}, fn {attr_id, attr_state}, acc ->
              # Ensure hovered key exists for backward compatibility
              attr_state = Map.put_new(attr_state, :hovered, MapSet.new())

              new_attr_state = %{
                attr_state
                | viewers: MapSet.delete(attr_state.viewers, user_id),
                  hovered: MapSet.delete(attr_state.hovered, user_id),
                  focused: MapSet.delete(attr_state.focused, user_id)
              }

              if MapSet.size(new_attr_state.viewers) == 0 and
                   MapSet.size(new_attr_state.hovered) == 0 and
                   MapSet.size(new_attr_state.focused) == 0 do
                acc
              else
                Map.put(acc, attr_id, new_attr_state)
              end
            end)

          if map_size(updated_attributes) == 0 do
            Map.delete(state.attention_state, sensor_id)
          else
            Map.put(state.attention_state, sensor_id, updated_attributes)
          end
      end

    # Also remove from pinned
    pinned =
      Map.update(state.pinned_sensors, sensor_id, MapSet.new(), &MapSet.delete(&1, user_id))

    pinned =
      if MapSet.size(Map.get(pinned, sensor_id, MapSet.new())) == 0,
        do: Map.delete(pinned, sensor_id),
        else: pinned

    new_state = %{state | attention_state: new_attention_state, pinned_sensors: pinned}

    # Update ETS cache for all affected attributes
    for attr_id <- old_attributes do
      level = do_get_attention_level(new_state, sensor_id, attr_id)

      if level == :none do
        delete_ets_cache(sensor_id, attr_id)
      else
        update_ets_cache(sensor_id, attr_id, level)
      end
    end

    # Broadcast sensor-level change
    new_level = do_get_sensor_attention_level(new_state, sensor_id)
    broadcast_sensor_attention_change(sensor_id, new_level)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:battery_state, user_id, battery_state, metadata}, state) do
    {old_state, _old_metadata} = Map.get(state.battery_states, user_id, {:normal, nil})

    if old_state != battery_state do
      source_info = if metadata.source != :unknown, do: " (source: #{metadata.source})", else: ""
      level_info = if metadata.level, do: ", level: #{metadata.level}%", else: ""

      Logger.debug(
        "Battery state changed for user #{inspect(user_id)}: #{old_state} -> #{battery_state}#{source_info}#{level_info}"
      )

      new_battery_states = Map.put(state.battery_states, user_id, {battery_state, metadata})
      new_state = %{state | battery_states: new_battery_states}

      # Recalculate and broadcast attention for all sensors this user is viewing
      # The battery modifier affects the effective attention level
      broadcast_battery_affected_sensors(state, user_id)

      {:noreply, new_state}
    else
      # State unchanged, but update metadata (e.g., new level reading)
      new_battery_states = Map.put(state.battery_states, user_id, {battery_state, metadata})
      {:noreply, %{state | battery_states: new_battery_states}}
    end
  end

  @impl true
  def handle_call({:get_battery_state, user_id}, _from, state) do
    case Map.get(state.battery_states, user_id) do
      {battery_state, metadata} -> {:reply, {battery_state, metadata}, state}
      nil -> {:reply, {:normal, nil}, state}
    end
  end

  @impl true
  def handle_call(:get_all_battery_states, _from, state) do
    {:reply, state.battery_states, state}
  end

  @impl true
  def handle_call({:get_attention_level, sensor_id, attribute_id}, _from, state) do
    level = do_get_attention_level(state, sensor_id, attribute_id)
    {:reply, level, state}
  end

  @impl true
  def handle_call({:get_sensor_attention_level, sensor_id}, _from, state) do
    level = do_get_sensor_attention_level(state, sensor_id)
    {:reply, level, state}
  end

  @impl true
  def handle_call({:get_attention_config, sensor_id, attribute_id}, _from, state) do
    level = do_get_attention_level(state, sensor_id, attribute_id)
    config = Map.get(@attention_config, level, @attention_config.none)
    {:reply, config, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -div(@stale_threshold, 1000), :second)

    # Clean up stale attention records and track removed entries for ETS cleanup
    {new_attention_state, removed_entries} =
      Enum.reduce(state.attention_state, {%{}, []}, fn {sensor_id, attributes}, {acc, removed} ->
        {cleaned_attributes, removed_attrs} =
          Enum.reduce(attributes, {%{}, removed}, fn {attr_id, attr_state}, {attr_acc, rem_acc} ->
            if DateTime.compare(attr_state.last_updated, threshold) == :lt do
              {attr_acc, [{sensor_id, attr_id} | rem_acc]}
            else
              {Map.put(attr_acc, attr_id, attr_state), rem_acc}
            end
          end)

        if map_size(cleaned_attributes) == 0 do
          {acc, removed_attrs}
        else
          {Map.put(acc, sensor_id, cleaned_attributes), removed_attrs}
        end
      end)

    # Clean up ETS entries for removed records
    for {sensor_id, attr_id} <- removed_entries do
      delete_ets_cache(sensor_id, attr_id)
    end

    schedule_cleanup()
    {:noreply, %{state | attention_state: new_attention_state, last_cleanup: now}}
  end

  # Handle boost decay timer expiry
  @impl true
  def handle_info({:boost_decay, sensor_id, attribute_id, boost_type}, state) do
    # Remove the timer from boost_timers
    timer_key = {sensor_id, attribute_id, boost_type}
    new_boost_timers = Map.delete(state.boost_timers, timer_key)
    new_state = %{state | boost_timers: new_boost_timers}

    # Clear the boost expiry from attribute state
    new_state = clear_boost_expiry(new_state, sensor_id, attribute_id, boost_type)

    # Update attribute-level ETS cache
    attr_level = do_get_attention_level(new_state, sensor_id, attribute_id)
    update_ets_cache(sensor_id, attribute_id, attr_level)

    # Broadcast the attention change at sensor level
    sensor_level = do_get_sensor_attention_level(new_state, sensor_id)
    broadcast_sensor_attention_change(sensor_id, sensor_level)

    {:noreply, new_state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp update_attention(state, sensor_id, attribute_id, user_id, action) do
    now = DateTime.utc_now()

    # Get existing attributes for this sensor, or empty map
    attributes = Map.get(state.attention_state, sensor_id, %{})

    # Get existing attribute state, or create new one
    attr_state = Map.get(attributes, attribute_id, new_attribute_state(now))

    # Ensure attr_state has all keys (for backward compatibility with existing state)
    attr_state = Map.put_new(attr_state, :hovered, MapSet.new())

    # Apply the action
    updated_attr_state =
      case action do
        :add_viewer ->
          %{attr_state | viewers: MapSet.put(attr_state.viewers, user_id), last_updated: now}

        :remove_viewer ->
          %{attr_state | viewers: MapSet.delete(attr_state.viewers, user_id), last_updated: now}

        :add_hover ->
          %{
            attr_state
            | hovered: MapSet.put(attr_state.hovered, user_id),
              viewers: MapSet.put(attr_state.viewers, user_id),
              last_updated: now
          }

        :remove_hover ->
          # Set hover boost expiry
          hover_boost_until = DateTime.add(now, div(@hover_boost_duration, 1000), :second)

          %{
            attr_state
            | hovered: MapSet.delete(attr_state.hovered, user_id),
              hover_boosted_until: hover_boost_until,
              last_updated: now
          }

        :add_focus ->
          %{
            attr_state
            | focused: MapSet.put(attr_state.focused, user_id),
              hovered: MapSet.put(attr_state.hovered, user_id),
              viewers: MapSet.put(attr_state.viewers, user_id),
              last_updated: now
          }

        :remove_focus ->
          # Set focus boost expiry
          focus_boost_until = DateTime.add(now, div(@focus_boost_duration, 1000), :second)

          %{
            attr_state
            | focused: MapSet.delete(attr_state.focused, user_id),
              focus_boosted_until: focus_boost_until,
              last_updated: now
          }
      end

    # Update the nested maps
    updated_attributes = Map.put(attributes, attribute_id, updated_attr_state)
    new_attention_state = Map.put(state.attention_state, sensor_id, updated_attributes)

    %{state | attention_state: new_attention_state}
  end

  # Schedule a timer for boost decay
  defp schedule_boost_decay(state, sensor_id, attribute_id, boost_type) do
    timer_key = {sensor_id, attribute_id, boost_type}

    duration =
      case boost_type do
        :focus -> @focus_boost_duration
        :hover -> @hover_boost_duration
      end

    # Cancel any existing timer for this key
    case Map.get(state.boost_timers, timer_key) do
      nil -> :ok
      existing_ref -> Process.cancel_timer(existing_ref)
    end

    # Schedule new timer
    timer_ref =
      Process.send_after(self(), {:boost_decay, sensor_id, attribute_id, boost_type}, duration)

    new_boost_timers = Map.put(state.boost_timers, timer_key, timer_ref)
    %{state | boost_timers: new_boost_timers}
  end

  # Clear boost expiry from attribute state
  defp clear_boost_expiry(state, sensor_id, attribute_id, boost_type) do
    case get_in(state.attention_state, [sensor_id, attribute_id]) do
      nil ->
        state

      attr_state ->
        field =
          case boost_type do
            :focus -> :focus_boosted_until
            :hover -> :hover_boosted_until
          end

        updated_attr_state = Map.put(attr_state, field, nil)

        updated_attributes =
          Map.put(state.attention_state[sensor_id], attribute_id, updated_attr_state)

        new_attention_state = Map.put(state.attention_state, sensor_id, updated_attributes)
        %{state | attention_state: new_attention_state}
    end
  end

  defp new_attribute_state(now) do
    %{
      viewers: MapSet.new(),
      hovered: MapSet.new(),
      focused: MapSet.new(),
      focus_boosted_until: nil,
      hover_boosted_until: nil,
      last_updated: now
    }
  end

  defp do_get_attention_level(state, sensor_id, attribute_id) do
    # Check if sensor is pinned
    if is_sensor_pinned?(state, sensor_id) do
      :high
    else
      case get_in(state.attention_state, [sensor_id, attribute_id]) do
        nil ->
          :none

        attr_state ->
          calculate_attr_attention_level(attr_state)
      end
    end
  end

  defp do_get_sensor_attention_level(state, sensor_id) do
    # Check if sensor is pinned
    if is_sensor_pinned?(state, sensor_id) do
      :high
    else
      case Map.get(state.attention_state, sensor_id) do
        nil ->
          :none

        attributes ->
          # Get highest attention level across all attributes
          Enum.reduce(attributes, :none, fn {_attr_id, attr_state}, acc ->
            level = calculate_attr_attention_level(attr_state)
            highest_level(acc, level)
          end)
      end
    end
  end

  # Calculate attention level for a single attribute, including boost decay
  defp calculate_attr_attention_level(attr_state) do
    now = DateTime.utc_now()

    # Handle both old state (without hovered) and new state (with hovered)
    focused = Map.get(attr_state, :focused, MapSet.new())
    hovered = Map.get(attr_state, :hovered, MapSet.new())
    viewers = Map.get(attr_state, :viewers, MapSet.new())

    # Check for active boosts
    focus_boosted = is_boost_active?(attr_state, :focus_boosted_until, now)
    hover_boosted = is_boost_active?(attr_state, :hover_boosted_until, now)

    cond do
      # Active focus or focus boost active
      MapSet.size(focused) > 0 -> :high
      focus_boosted -> :high
      # Active hover or hover boost active
      MapSet.size(hovered) > 0 -> :high
      hover_boosted -> :high
      # Just viewing
      MapSet.size(viewers) > 0 -> :medium
      true -> :low
    end
  end

  # Check if a boost is still active
  defp is_boost_active?(attr_state, boost_field, now) do
    case Map.get(attr_state, boost_field) do
      nil -> false
      boost_until -> DateTime.compare(now, boost_until) == :lt
    end
  end

  defp is_sensor_pinned?(state, sensor_id) do
    case Map.get(state.pinned_sensors, sensor_id) do
      nil -> false
      users -> MapSet.size(users) > 0
    end
  end

  defp highest_level(a, b) do
    priority = %{high: 3, medium: 2, low: 1, none: 0}
    if priority[a] >= priority[b], do: a, else: b
  end

  defp maybe_broadcast_change(old_state, new_state, sensor_id, attribute_id) do
    old_level = do_get_attention_level(old_state, sensor_id, attribute_id)
    new_level = do_get_attention_level(new_state, sensor_id, attribute_id)

    # Always update ETS cache (even if level unchanged, ensures consistency)
    update_ets_cache(sensor_id, attribute_id, new_level)

    if old_level != new_level do
      Logger.debug(
        "Attention changed for #{sensor_id}/#{attribute_id}: #{old_level} -> #{new_level}"
      )

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "attention:#{sensor_id}:#{attribute_id}",
        {:attention_changed,
         %{sensor_id: sensor_id, attribute_id: attribute_id, level: new_level}}
      )

      # Also broadcast sensor-level change
      old_sensor_level = do_get_sensor_attention_level(old_state, sensor_id)
      new_sensor_level = do_get_sensor_attention_level(new_state, sensor_id)

      if old_sensor_level != new_sensor_level do
        broadcast_sensor_attention_change(sensor_id, new_sensor_level)
      end
    end
  end

  defp update_ets_cache(sensor_id, attribute_id, level) do
    :ets.insert(@attention_levels_table, {{sensor_id, attribute_id}, level})
  end

  defp delete_ets_cache(sensor_id, attribute_id) do
    :ets.delete(@attention_levels_table, {sensor_id, attribute_id})
  end

  defp update_sensor_ets_cache(state, sensor_id) do
    # Update ETS cache for all attributes of this sensor
    case Map.get(state.attention_state, sensor_id) do
      nil ->
        :ok

      attributes ->
        for {attr_id, _} <- attributes do
          level = do_get_attention_level(state, sensor_id, attr_id)
          update_ets_cache(sensor_id, attr_id, level)
        end
    end
  end

  defp broadcast_sensor_attention_change(sensor_id, level) do
    Logger.debug("Sensor attention changed for #{sensor_id}: #{level}")

    # Update ETS cache for fast reads
    :ets.insert(@sensor_attention_table, {sensor_id, level})

    # Broadcast to sensor-specific topic
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "attention:#{sensor_id}",
      {:attention_changed, %{sensor_id: sensor_id, level: level}}
    )

    # Also broadcast to global lobby topic for UI updates
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "attention:lobby",
      {:attention_changed, %{sensor_id: sensor_id, level: level}}
    )
  end

  # Broadcast attention changes for all sensors a user is viewing
  # Called when battery state changes
  defp broadcast_battery_affected_sensors(state, user_id) do
    # Find all sensors where this user is a viewer
    Enum.each(state.attention_state, fn {sensor_id, attributes} ->
      user_is_viewing =
        Enum.any?(attributes, fn {_attr_id, attr_state} ->
          MapSet.member?(attr_state.viewers, user_id) or
            MapSet.member?(attr_state.focused, user_id)
        end)

      if user_is_viewing do
        # Recalculate and broadcast sensor-level attention
        level = do_get_sensor_attention_level(state, sensor_id)
        broadcast_sensor_attention_change(sensor_id, level)

        # Also broadcast for each attribute
        Enum.each(attributes, fn {attr_id, _attr_state} ->
          attr_level = do_get_attention_level(state, sensor_id, attr_id)
          update_ets_cache(sensor_id, attr_id, attr_level)

          Phoenix.PubSub.broadcast(
            Sensocto.PubSub,
            "attention:#{sensor_id}:#{attr_id}",
            {:attention_changed,
             %{sensor_id: sensor_id, attribute_id: attr_id, level: attr_level}}
          )
        end)
      end
    end)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
