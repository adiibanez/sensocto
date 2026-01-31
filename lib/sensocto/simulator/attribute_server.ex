defmodule Sensocto.Simulator.AttributeServer do
  @moduledoc """
  Generates simulated data for a sensor attribute.
  Fetches data from DataServer, batches it, and sends to the parent SensorServer.

  Supports dynamic batch window adjustment based on:
  - User attention levels (viewport, focus, pinning)
  - System load (CPU/scheduler utilization, message queues, memory)

  This enables back-pressure when many sensors are active but few are being viewed,
  and when the system is under heavy load.
  """

  use GenServer
  require Logger

  alias Sensocto.AttentionTracker

  @enforce_keys [:attribute_id]
  defstruct @enforce_keys ++
              [
                :sensor_pid,
                :sensor_pid_ref,
                :sensor_id,
                :connector_id,
                :paused,
                :config,
                :messages_queue,
                :batch_push_messages,
                :attention_level,
                :system_load_level,
                :current_batch_window,
                :base_batch_window,
                # String version of attribute_id for consistent AttentionTracker lookups
                :attribute_id_str
              ]

  @type t :: %__MODULE__{
          attribute_id: String.t() | atom(),
          attribute_id_str: String.t(),
          sensor_pid: pid() | nil,
          sensor_pid_ref: reference() | nil,
          sensor_id: String.t(),
          connector_id: String.t(),
          paused: boolean(),
          config: map(),
          messages_queue: list(),
          batch_push_messages: list(),
          attention_level: atom(),
          current_batch_window: non_neg_integer(),
          base_batch_window: non_neg_integer()
        }

  def start_link(
        %{connector_id: connector_id, sensor_id: sensor_id, attribute_id: attribute_id} = config
      ) do
    Logger.info("Starting AttributeServer: #{connector_id}/#{sensor_id}/#{attribute_id}")

    GenServer.start_link(__MODULE__, config,
      name: via_tuple("#{connector_id}_#{sensor_id}_#{attribute_id}")
    )
  end

  def pause(pid), do: GenServer.cast(pid, :pause)
  def resume(pid), do: GenServer.cast(pid, :resume)
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @impl true
  def init(%{attribute_id: attribute_id} = config) do
    Logger.info(
      "AttributeServer init: #{config.connector_id}/#{config.sensor_id}/#{attribute_id}"
    )

    sensor_id = Map.get(config, :sensor_id)
    # Ensure attribute_id is a string for consistent AttentionTracker lookups
    # (AttentionTracker receives string IDs from JavaScript frontend)
    attribute_id_str = to_string(attribute_id)
    base_window = config[:batch_window] || 500

    # Subscribe to attention changes for this sensor/attribute
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}:#{attribute_id_str}")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}")

    # Subscribe to system load changes
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:load")

    # Get initial attention level and calculate batch window
    # Handle case where AttentionTracker might not be running yet
    {initial_attention, initial_batch_window} =
      try do
        attention = AttentionTracker.get_attention_level(sensor_id, attribute_id_str)

        batch_window =
          AttentionTracker.calculate_batch_window(base_window, sensor_id, attribute_id_str)

        {attention, batch_window}
      catch
        :exit, {:noproc, _} ->
          Logger.debug(
            "AttentionTracker not available, using defaults for #{sensor_id}/#{attribute_id_str}"
          )

          {:none, base_window * 10}
      end

    # Get initial system load level
    initial_load_level =
      try do
        Sensocto.SystemLoadMonitor.get_load_level()
      catch
        :exit, {:noproc, _} -> :normal
      end

    # Monitor the sensor PID so we know when it dies
    sensor_pid = Map.get(config, :sensor_pid)

    sensor_pid_ref =
      if is_pid(sensor_pid) and Process.alive?(sensor_pid) do
        Process.monitor(sensor_pid)
      else
        Logger.warning(
          "AttributeServer #{sensor_id}/#{attribute_id}: sensor_pid is not alive, will terminate"
        )

        nil
      end

    state = %__MODULE__{
      attribute_id: attribute_id,
      attribute_id_str: attribute_id_str,
      sensor_pid: sensor_pid,
      sensor_pid_ref: sensor_pid_ref,
      sensor_id: sensor_id,
      connector_id: Map.get(config, :connector_id),
      paused: false,
      config: config,
      messages_queue: [],
      batch_push_messages: [],
      attention_level: initial_attention,
      system_load_level: initial_load_level,
      base_batch_window: base_window,
      current_batch_window: initial_batch_window
    }

    Logger.debug(
      "AttributeServer #{sensor_id}/#{attribute_id} starting with attention=#{initial_attention}, batch_window=#{initial_batch_window}ms"
    )

    # Start processing and batch window timer
    Process.send_after(self(), :process_queue, 100)
    Process.send_after(self(), :batch_window, initial_batch_window)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:pause, state), do: {:noreply, %{state | paused: true}}

  @impl true
  def handle_cast(:resume, state) do
    Process.send_after(self(), :process_queue, 0)
    {:noreply, %{state | paused: false}}
  end

  # Process queue when empty - fetch more data
  @impl true
  def handle_cast(:process_queue, %{messages_queue: [], paused: false} = state) do
    Process.send_after(self(), :get_data, 0)
    {:noreply, state}
  end

  # Process queue with messages
  @impl true
  def handle_cast(:process_queue, %{messages_queue: [head | tail], paused: false} = state) do
    Process.send_after(self(), {:push_message, head}, 0)
    {:noreply, %{state | messages_queue: tail}}
  end

  @impl true
  def handle_cast(:process_queue, %{paused: true} = state), do: {:noreply, state}

  # Push message to batch
  # Applies backpressure by adjusting delay based on attention level
  @impl true
  def handle_cast({:push_message, message}, state) do
    {delay_s, _} = Float.parse("#{message.delay}")
    base_delay_ms = round(delay_s * 1000.0)

    # Apply backpressure: multiply delay by attention-based factor
    # This slows down data generation when no one is watching
    effective_delay_ms = apply_backpressure_delay(base_delay_ms, state.attention_level)

    timestamp = :os.system_time(:millisecond)
    new_message = Map.put(message, :timestamp, timestamp)

    new_batch = state.batch_push_messages ++ [new_message]
    batch_size = state.config[:batch_size] || 10

    # Schedule next message processing with backpressure-adjusted delay
    Process.send_after(self(), :process_queue, effective_delay_ms)

    if length(new_batch) >= batch_size do
      GenServer.cast(self(), {:push_batch, new_batch})
      {:noreply, %{state | batch_push_messages: []}}
    else
      {:noreply, %{state | batch_push_messages: new_batch}}
    end
  end

  # Push batch to sensor
  # Note: Uses attribute_id_str (string) for consistency with SimpleSensor/AttributeStore
  @impl true
  def handle_cast({:push_batch, messages}, state) when length(messages) > 0 do
    cond do
      state.paused ->
        {:noreply, state}

      not is_pid(state.sensor_pid) ->
        Logger.warning(
          "AttributeServer #{state.sensor_id}/#{state.attribute_id_str}: " <>
            "no sensor_pid, terminating"
        )

        {:stop, :no_sensor_pid, state}

      not Process.alive?(state.sensor_pid) ->
        Logger.warning(
          "AttributeServer #{state.sensor_id}/#{state.attribute_id_str}: " <>
            "sensor_pid is dead, terminating"
        )

        {:stop, :sensor_dead, state}

      true ->
        push_messages =
          Enum.map(messages, fn msg ->
            %{
              "payload" => msg.payload,
              "timestamp" => msg.timestamp,
              "attribute_id" => state.attribute_id_str
            }
          end)

        send(state.sensor_pid, {:push_batch, state.attribute_id_str, push_messages})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:push_batch, _}, state), do: {:noreply, state}

  # Fetch data from data server
  @impl true
  def handle_info(:get_data, state) do
    worker_id = :rand.uniform(5)
    worker_name = :"sim_data_server_#{worker_id}"

    send(worker_name, {:get_data, self(), state.config})
    {:noreply, state}
  end

  # Receive data from data server
  @impl true
  def handle_info({:get_data_result, data}, state) do
    Logger.debug(
      "#{state.connector_id}/#{state.sensor_id}/#{state.attribute_id} got #{length(data)} data points"
    )

    new_queue = state.messages_queue ++ data
    Process.send_after(self(), :process_queue, 0)

    {:noreply, %{state | messages_queue: new_queue}}
  end

  @impl true
  def handle_info(:process_queue, state) do
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  @impl true
  def handle_info({:push_message, message}, state) do
    GenServer.cast(self(), {:push_message, message})
    {:noreply, state}
  end

  # Batch window timeout - push whatever is in the batch
  @impl true
  def handle_info(
        :batch_window,
        %{batch_push_messages: messages, current_batch_window: batch_window} = state
      ) do
    Process.send_after(self(), :batch_window, batch_window)

    if length(messages) > 0 do
      GenServer.cast(self(), {:push_batch, messages})
      {:noreply, %{state | batch_push_messages: []}}
    else
      {:noreply, state}
    end
  end

  # Handle attention level changes from AttentionTracker
  # Note: PubSub messages use string attribute_id, so we match on attribute_id_str
  @impl true
  def handle_info(
        {:attention_changed, %{sensor_id: sensor_id, attribute_id: attr_id, level: new_level}},
        %{sensor_id: sensor_id, attribute_id_str: attr_id} = state
      ) do
    new_batch_window =
      AttentionTracker.calculate_batch_window(state.base_batch_window, sensor_id, attr_id)

    if new_level != state.attention_level do
      Logger.info(
        "AttributeServer #{sensor_id}/#{attr_id} attention changed: #{state.attention_level} -> #{new_level}, batch_window: #{state.current_batch_window}ms -> #{new_batch_window}ms"
      )
    end

    {:noreply, %{state | attention_level: new_level, current_batch_window: new_batch_window}}
  end

  # Handle sensor-level attention changes (for pinning)
  @impl true
  def handle_info(
        {:attention_changed, %{sensor_id: sensor_id, level: new_level}},
        %{sensor_id: sensor_id} = state
      ) do
    # Recalculate based on attribute-specific attention (which considers sensor pins)
    new_batch_window =
      AttentionTracker.calculate_batch_window(
        state.base_batch_window,
        sensor_id,
        state.attribute_id_str
      )

    new_attention = AttentionTracker.get_attention_level(sensor_id, state.attribute_id_str)

    if new_attention != state.attention_level do
      Logger.debug(
        "AttributeServer #{sensor_id}/#{state.attribute_id_str} sensor attention changed to #{new_level}, effective: #{new_attention}, batch_window: #{new_batch_window}ms"
      )
    end

    {:noreply, %{state | attention_level: new_attention, current_batch_window: new_batch_window}}
  end

  # Ignore attention changes for other sensors/attributes
  @impl true
  def handle_info({:attention_changed, _}, state), do: {:noreply, state}

  # Handle sensor PID death - terminate this AttributeServer
  # This fixes the "silent disconnect" bug where AttributeServer keeps running
  # but sends data to a dead PID
  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{sensor_pid_ref: ref, sensor_pid: pid} = state
      ) do
    Logger.warning(
      "AttributeServer #{state.sensor_id}/#{state.attribute_id_str}: " <>
        "SensorServer (#{inspect(pid)}) died with reason: #{inspect(reason)}, terminating"
    )

    {:stop, {:sensor_died, reason}, state}
  end

  # Ignore DOWN messages for other processes
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # Handle memory protection changes from SystemLoadMonitor
  # When memory pressure is high, the system activates memory protection mode
  @impl true
  def handle_info({:memory_protection_changed, %{active: _active}}, state) do
    # Memory protection is handled at the system level via load multipliers
    # AttributeServer doesn't need to take additional action
    {:noreply, state}
  end

  # Handle system load changes from SystemLoadMonitor
  @impl true
  def handle_info(
        {:system_load_changed, %{level: new_level, multiplier: _multiplier} = load_info},
        state
      ) do
    # Recalculate batch window with new system load
    new_batch_window =
      AttentionTracker.calculate_batch_window(
        state.base_batch_window,
        state.sensor_id,
        state.attribute_id_str
      )

    if new_level != state.system_load_level do
      Logger.info(
        "AttributeServer #{state.sensor_id}/#{state.attribute_id_str} system load changed: " <>
          "#{state.system_load_level} -> #{new_level}, " <>
          "batch_window: #{state.current_batch_window}ms -> #{new_batch_window}ms " <>
          "(scheduler: #{Float.round(load_info.scheduler_utilization * 100, 1)}%)"
      )
    end

    {:noreply, %{state | system_load_level: new_level, current_batch_window: new_batch_window}}
  end

  # Apply backpressure by multiplying the delay based on attention level
  # This effectively slows down data generation when users aren't watching
  defp apply_backpressure_delay(base_delay_ms, attention_level) do
    # Also incorporate system load multiplier
    load_multiplier = AttentionTracker.get_system_load_multiplier()

    attention_multiplier =
      case attention_level do
        :high -> 1.0
        :medium -> 1.0
        :low -> 4.0
        :none -> 10.0
        _ -> 1.0
      end

    # Combine both multipliers
    total_multiplier = attention_multiplier * load_multiplier

    # Ensure minimum delay when base is 0 (first message in batch has delay: 0.0)
    # Without this, backpressure has no effect when multiplying 0
    effective_base = if base_delay_ms == 0, do: 50, else: base_delay_ms

    round(effective_base * total_multiplier)
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sensocto.Simulator.Registry, "attribute_#{identifier}"}}
  end
end
