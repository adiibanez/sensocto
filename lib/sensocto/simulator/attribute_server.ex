defmodule Sensocto.Simulator.AttributeServer do
  @moduledoc """
  Generates simulated data for a sensor attribute.
  Fetches data from DataServer, batches it, and sends to the parent SensorServer.
  """

  use GenServer
  require Logger

  @enforce_keys [:attribute_id]
  defstruct @enforce_keys ++
              [
                :sensor_pid,
                :sensor_id,
                :connector_id,
                :paused,
                :config,
                :messages_queue,
                :batch_push_messages
              ]

  @type t :: %__MODULE__{
          attribute_id: String.t(),
          sensor_pid: pid(),
          sensor_id: String.t(),
          connector_id: String.t(),
          paused: boolean(),
          config: map(),
          messages_queue: list(),
          batch_push_messages: list()
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
    Logger.info("AttributeServer init: #{config.connector_id}/#{config.sensor_id}/#{attribute_id}")

    state = %__MODULE__{
      attribute_id: attribute_id,
      sensor_pid: Map.get(config, :sensor_pid),
      sensor_id: Map.get(config, :sensor_id),
      connector_id: Map.get(config, :connector_id),
      paused: false,
      config: config,
      messages_queue: [],
      batch_push_messages: []
    }

    # Start processing and batch window timer
    Process.send_after(self(), :process_queue, 100)
    Process.send_after(self(), :batch_window, config[:batch_window] || 500)

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
  @impl true
  def handle_cast({:push_message, message}, state) do
    {delay_s, _} = Float.parse("#{message.delay}")
    delay_ms = round(delay_s * 1000.0)

    timestamp = :os.system_time(:millisecond)
    new_message = Map.put(message, :timestamp, timestamp)

    new_batch = state.batch_push_messages ++ [new_message]
    batch_size = state.config[:batch_size] || 10

    # Schedule next message processing with delay
    Process.send_after(self(), :process_queue, delay_ms)

    if length(new_batch) >= batch_size do
      GenServer.cast(self(), {:push_batch, new_batch})
      {:noreply, %{state | batch_push_messages: []}}
    else
      {:noreply, %{state | batch_push_messages: new_batch}}
    end
  end

  # Push batch to sensor
  @impl true
  def handle_cast({:push_batch, messages}, state) when length(messages) > 0 do
    unless state.paused do
      push_messages =
        Enum.map(messages, fn msg ->
          %{
            "payload" => msg.payload,
            "timestamp" => msg.timestamp,
            "attribute_id" => state.attribute_id
          }
        end)

      send(state.sensor_pid, {:push_batch, state.attribute_id, push_messages})
    end

    {:noreply, state}
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
    Logger.debug("#{state.connector_id}/#{state.sensor_id}/#{state.attribute_id} got #{length(data)} data points")

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
  def handle_info(:batch_window, %{batch_push_messages: messages, config: config} = state) do
    batch_window = config[:batch_window] || 500
    Process.send_after(self(), :batch_window, batch_window)

    if length(messages) > 0 do
      GenServer.cast(self(), {:push_batch, messages})
      {:noreply, %{state | batch_push_messages: []}}
    else
      {:noreply, state}
    end
  end

  defp via_tuple(identifier) do
    {:via, Registry, {Sensocto.Simulator.Registry, "attribute_#{identifier}"}}
  end
end
