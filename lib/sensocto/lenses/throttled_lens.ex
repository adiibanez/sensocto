defmodule Sensocto.Lenses.ThrottledLens do
  @moduledoc """
  Rate-limits sensor measurements using ETS for zero-copy buffering.

  Uses a single ETS table shared across all rate tiers. Each measurement is
  written once to ETS (not copied). Flush operations read and clear atomically.

  ## Topics

  Broadcasts to: `"lens:throttled:{rate_hz}"` where rate_hz is 5, 10, or 20

  ## Design (KISS)

  - Single ETS table: `{sensor_id, attribute_id}` => measurement
  - Each rate tier has its own flush timer
  - On flush: read all, broadcast, clear - no per-rate buffering
  - Measurements overwrite previous (keeps latest only)

  ## Example Usage

  ```elixir
  # Subscribe to 10Hz throttled stream
  Phoenix.PubSub.subscribe(Sensocto.PubSub, "lens:throttled:10")

  # Receive batched measurements every 100ms
  def handle_info({:lens_batch, batch}, socket) do
    {:noreply, push_event(socket, "measurements_batch", %{data: batch})}
  end
  ```
  """

  use GenServer
  require Logger

  @table_name :throttled_lens_buffer

  # Supported throttle rates and their flush intervals
  @throttle_configs %{
    5 => %{interval_ms: 200, topic: "lens:throttled:5"},
    10 => %{interval_ms: 100, topic: "lens:throttled:10"},
    20 => %{interval_ms: 50, topic: "lens:throttled:20"}
  }

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
    # Create ETS table for buffering - :set ensures one entry per key
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Register with the router to receive measurements
    Sensocto.Lenses.Router.register_lens(self())

    # Schedule flush timers for each rate
    for {rate, config} <- @throttle_configs do
      schedule_flush(rate, config.interval_ms)
    end

    Logger.info("ThrottledLens started with rates: #{inspect(Map.keys(@throttle_configs))}")

    {:ok, %{}}
  end

  # Single measurement from router - write directly to ETS (no state mutation)
  @impl true
  def handle_info({:router_measurement, sensor_id, measurement}, state) do
    attribute_id = Map.get(measurement, :attribute_id)
    key = {sensor_id, attribute_id}

    # Single write to ETS - overwrites previous (keeps latest)
    :ets.insert(@table_name, {key, sensor_id, attribute_id, measurement})

    {:noreply, state}
  end

  # Batch measurements from router
  @impl true
  def handle_info({:router_measurements_batch, sensor_id, measurements}, state) do
    # Group by attribute, keep latest timestamp
    measurements
    |> Enum.group_by(& &1.attribute_id)
    |> Enum.each(fn {attribute_id, msgs} ->
      latest = Enum.max_by(msgs, &(&1.timestamp || 0))
      key = {sensor_id, attribute_id}
      :ets.insert(@table_name, {key, sensor_id, attribute_id, latest})
    end)

    {:noreply, state}
  end

  # Flush timer - read all from ETS, broadcast, then clear
  @impl true
  def handle_info({:flush, rate}, state) do
    config = @throttle_configs[rate]

    # Read all entries from ETS
    entries = :ets.tab2list(@table_name)

    if length(entries) > 0 do
      # Build batch grouped by sensor_id
      batch =
        entries
        |> Enum.reduce(%{}, fn {_key, sensor_id, attribute_id, measurement}, acc ->
          sensor_data = Map.get(acc, sensor_id, %{})
          updated_sensor = Map.put(sensor_data, attribute_id, measurement)
          Map.put(acc, sensor_id, updated_sensor)
        end)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        config.topic,
        {:lens_batch, batch}
      )

      # Clear the table after the FASTEST rate (20Hz) flushes
      # This ensures slower rates still see data accumulated between their flushes
      if rate == 20 do
        :ets.delete_all_objects(@table_name)
      end
    end

    # Reschedule
    schedule_flush(rate, config.interval_ms)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Sensocto.Lenses.Router.unregister_lens(self())
    # ETS table is automatically cleaned up when process dies
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp schedule_flush(rate, interval_ms) do
    Process.send_after(self(), {:flush, rate}, interval_ms)
  end
end
