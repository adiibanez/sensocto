defmodule Sensocto.AttentionTracker do
  @moduledoc """
  Tracks user attention on sensors and attributes to enable back-pressure.

  Attention levels:
  - :high - User has attribute focused (clicked, interacting)
  - :medium - User has attribute in viewport
  - :low - Sensor connected but no users viewing
  - :none - No active connections

  The tracker aggregates attention across all users and uses the highest
  attention level to determine data transmission rates.
  """

  use GenServer
  require Logger

  @cleanup_interval :timer.seconds(30)
  @stale_threshold :timer.seconds(60)

  # ETS table names for fast concurrent reads
  @attention_levels_table :attention_levels_cache
  @attention_config_table :attention_config_cache

  # Batch window multipliers based on attention level
  @attention_config %{
    high: %{window_multiplier: 0.2, min_window: 100, max_window: 500},
    medium: %{window_multiplier: 1.0, min_window: 500, max_window: 2000},
    low: %{window_multiplier: 4.0, min_window: 2000, max_window: 10000},
    none: %{window_multiplier: 10.0, min_window: 5000, max_window: 30000}
  }

  defstruct [
    :attention_state,
    :pinned_sensors,
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
  """
  def get_sensor_attention_level(sensor_id) do
    GenServer.call(__MODULE__, {:get_sensor_attention_level, sensor_id})
  end

  @doc """
  Get batch configuration based on attention level.
  Returns %{window_multiplier, min_window, max_window}

  Uses ETS for fast concurrent reads - no GenServer bottleneck.
  """
  def get_attention_config(sensor_id, attribute_id) do
    level = get_attention_level(sensor_id, attribute_id)

    case :ets.lookup(@attention_config_table, level) do
      [{_, config}] -> config
      [] -> @attention_config.none
    end
  end

  @doc """
  Calculate the adjusted batch window based on base window and attention.
  """
  def calculate_batch_window(base_window, sensor_id, attribute_id) do
    config = get_attention_config(sensor_id, attribute_id)
    adjusted = trunc(base_window * config.window_multiplier)
    max(config.min_window, min(adjusted, config.max_window))
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

    # Pre-populate config table (static values)
    for {level, config} <- @attention_config do
      :ets.insert(@attention_config_table, {level, config})
    end

    schedule_cleanup()

    state = %__MODULE__{
      attention_state: %{},
      pinned_sensors: %{},
      last_cleanup: DateTime.utc_now()
    }

    Logger.info("AttentionTracker started with ETS caching")
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
  def handle_cast({:register_focus, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :add_focus)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_focus, sensor_id, attribute_id, user_id}, state) do
    new_state = update_attention(state, sensor_id, attribute_id, user_id, :remove_focus)
    maybe_broadcast_change(state, new_state, sensor_id, attribute_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:pin_sensor, sensor_id, user_id}, state) do
    pinned = Map.update(state.pinned_sensors, sensor_id, MapSet.new([user_id]), &MapSet.put(&1, user_id))
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
        nil -> state.pinned_sensors
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
              new_attr_state = %{
                attr_state |
                viewers: MapSet.delete(attr_state.viewers, user_id),
                focused: MapSet.delete(attr_state.focused, user_id)
              }

              if MapSet.size(new_attr_state.viewers) == 0 and MapSet.size(new_attr_state.focused) == 0 do
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
    pinned = Map.update(state.pinned_sensors, sensor_id, MapSet.new(), &MapSet.delete(&1, user_id))
    pinned = if MapSet.size(Map.get(pinned, sensor_id, MapSet.new())) == 0, do: Map.delete(pinned, sensor_id), else: pinned

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

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp update_attention(state, sensor_id, attribute_id, user_id, action) do
    now = DateTime.utc_now()

    # Get existing attributes for this sensor, or empty map
    attributes = Map.get(state.attention_state, sensor_id, %{})

    # Get existing attribute state, or create new one
    attr_state = Map.get(attributes, attribute_id, new_attribute_state(now))

    # Apply the action
    updated_attr_state =
      case action do
        :add_viewer ->
          %{attr_state | viewers: MapSet.put(attr_state.viewers, user_id), last_updated: now}

        :remove_viewer ->
          %{attr_state | viewers: MapSet.delete(attr_state.viewers, user_id), last_updated: now}

        :add_focus ->
          %{attr_state |
            focused: MapSet.put(attr_state.focused, user_id),
            viewers: MapSet.put(attr_state.viewers, user_id),
            last_updated: now
          }

        :remove_focus ->
          %{attr_state | focused: MapSet.delete(attr_state.focused, user_id), last_updated: now}
      end

    # Update the nested maps
    updated_attributes = Map.put(attributes, attribute_id, updated_attr_state)
    new_attention_state = Map.put(state.attention_state, sensor_id, updated_attributes)

    %{state | attention_state: new_attention_state}
  end

  defp new_attribute_state(now) do
    %{
      viewers: MapSet.new(),
      focused: MapSet.new(),
      last_updated: now
    }
  end

  defp do_get_attention_level(state, sensor_id, attribute_id) do
    # Check if sensor is pinned
    if is_sensor_pinned?(state, sensor_id) do
      :high
    else
      case get_in(state.attention_state, [sensor_id, attribute_id]) do
        nil -> :none
        %{focused: focused, viewers: viewers} ->
          cond do
            MapSet.size(focused) > 0 -> :high
            MapSet.size(viewers) > 0 -> :medium
            true -> :low
          end
      end
    end
  end

  defp do_get_sensor_attention_level(state, sensor_id) do
    # Check if sensor is pinned
    if is_sensor_pinned?(state, sensor_id) do
      :high
    else
      case Map.get(state.attention_state, sensor_id) do
        nil -> :none
        attributes ->
          # Get highest attention level across all attributes
          Enum.reduce(attributes, :none, fn {_attr_id, attr_state}, acc ->
            level = cond do
              MapSet.size(attr_state.focused) > 0 -> :high
              MapSet.size(attr_state.viewers) > 0 -> :medium
              true -> :low
            end
            highest_level(acc, level)
          end)
      end
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
      Logger.debug("Attention changed for #{sensor_id}/#{attribute_id}: #{old_level} -> #{new_level}")

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "attention:#{sensor_id}:#{attribute_id}",
        {:attention_changed, %{sensor_id: sensor_id, attribute_id: attribute_id, level: new_level}}
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
      nil -> :ok
      attributes ->
        for {attr_id, _} <- attributes do
          level = do_get_attention_level(state, sensor_id, attr_id)
          update_ets_cache(sensor_id, attr_id, level)
        end
    end
  end

  defp broadcast_sensor_attention_change(sensor_id, level) do
    Logger.debug("Sensor attention changed for #{sensor_id}: #{level}")

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "attention:#{sensor_id}",
      {:attention_changed, %{sensor_id: sensor_id, level: level}}
    )
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
