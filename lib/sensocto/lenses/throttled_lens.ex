defmodule Sensocto.Lenses.ThrottledLens do
  @moduledoc """
  Rate-limits sensor measurements to configurable frequencies.

  Broadcasts batched measurements at fixed intervals, keeping only the latest
  value per sensor/attribute when data arrives faster than the target rate.

  ## Topics

  Broadcasts to: `"lens:throttled:{rate_hz}"` where rate_hz is 5, 10, or 20

  ## Message Format

  Broadcasts `{:lens_batch, batch_data}` where batch_data is:
  ```
  %{
    sensor_id => %{
      attribute_id => %{
        payload: value,
        timestamp: unix_ms,
        sensor_id: sensor_id,
        attribute_id: attribute_id
      }
    }
  }
  ```

  ## Example Usage

  ```elixir
  # Subscribe to 10Hz throttled stream
  Phoenix.PubSub.subscribe(Sensocto.PubSub, "lens:throttled:10")

  # Receive batched measurements every 100ms
  def handle_info({:lens_batch, batch}, socket) do
    # batch contains latest measurements grouped by sensor_id => attribute_id
    {:noreply, push_event(socket, "measurements_batch", %{data: batch})}
  end
  ```
  """

  use GenServer
  require Logger

  # Supported throttle rates and their flush intervals
  @throttle_configs %{
    5 => %{interval_ms: 200, topic: "lens:throttled:5"},
    10 => %{interval_ms: 100, topic: "lens:throttled:10"},
    20 => %{interval_ms: 50, topic: "lens:throttled:20"}
  }

  defstruct [
    :buffers,
    :flush_timers
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Get the topic for a specific throttle rate.
  """
  def topic_for_rate(rate_hz) when rate_hz in [5, 10, 20] do
    @throttle_configs[rate_hz].topic
  end

  @doc """
  Get available throttle rates.
  """
  def available_rates, do: Map.keys(@throttle_configs)

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Register with the router to receive measurements
    Sensocto.Lenses.Router.register_lens(self())

    # Initialize buffers for each rate
    buffers =
      @throttle_configs
      |> Map.keys()
      |> Enum.into(%{}, fn rate -> {rate, %{}} end)

    # Schedule flush timers for each rate
    flush_timers =
      for {rate, config} <- @throttle_configs, into: %{} do
        timer_ref = schedule_flush(rate, config.interval_ms)
        {rate, timer_ref}
      end

    Logger.info("ThrottledLens started with rates: #{inspect(Map.keys(@throttle_configs))}")

    {:ok, %__MODULE__{buffers: buffers, flush_timers: flush_timers}}
  end

  # Single measurement from router
  @impl true
  def handle_info({:router_measurement, sensor_id, measurement}, state) do
    attribute_id = Map.get(measurement, :attribute_id)

    # Buffer to all rate tiers (each tier keeps latest)
    new_buffers =
      Enum.reduce(@throttle_configs, state.buffers, fn {rate, _config}, buffers ->
        buffer = Map.get(buffers, rate, %{})

        sensor_buffer =
          buffer
          |> Map.get(sensor_id, %{})
          |> Map.put(attribute_id, measurement)

        Map.put(buffers, rate, Map.put(buffer, sensor_id, sensor_buffer))
      end)

    {:noreply, %{state | buffers: new_buffers}}
  end

  # Batch measurements from router
  @impl true
  def handle_info({:router_measurements_batch, sensor_id, measurements}, state) do
    # Group by attribute_id and keep latest
    latest_by_attr =
      measurements
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.into(%{}, fn {attr_id, msgs} ->
        # Keep the one with highest timestamp
        latest = Enum.max_by(msgs, &(&1.timestamp || 0))
        {attr_id, latest}
      end)

    # Buffer to all rate tiers
    new_buffers =
      Enum.reduce(@throttle_configs, state.buffers, fn {rate, _config}, buffers ->
        buffer = Map.get(buffers, rate, %{})
        existing_sensor = Map.get(buffer, sensor_id, %{})
        merged_sensor = Map.merge(existing_sensor, latest_by_attr)
        Map.put(buffers, rate, Map.put(buffer, sensor_id, merged_sensor))
      end)

    {:noreply, %{state | buffers: new_buffers}}
  end

  # Flush timer for a specific rate
  @impl true
  def handle_info({:flush, rate}, state) do
    config = @throttle_configs[rate]
    buffer = Map.get(state.buffers, rate, %{})

    # Only broadcast if there's data
    if map_size(buffer) > 0 do
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        config.topic,
        {:lens_batch, buffer}
      )
    end

    # Clear buffer and reschedule
    new_buffers = Map.put(state.buffers, rate, %{})
    new_timer = schedule_flush(rate, config.interval_ms)
    new_flush_timers = Map.put(state.flush_timers, rate, new_timer)

    {:noreply, %{state | buffers: new_buffers, flush_timers: new_flush_timers}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Unregister from router
    Sensocto.Lenses.Router.unregister_lens(self())
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp schedule_flush(rate, interval_ms) do
    Process.send_after(self(), {:flush, rate}, interval_ms)
  end
end
