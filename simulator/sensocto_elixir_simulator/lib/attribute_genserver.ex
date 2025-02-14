defmodule Sensocto.Simulator.AttributeGenServer do
  use GenServer
  require Logger

  @enforce_keys [:attribute_id]
  defstruct @enforce_keys ++
              [
                :state_data,
                :connector_pid,
                :connector_id,
                :paused,
                :config,
                :messages_queue,
                :batch_push_messages,
                :batch_window_scheduled
              ]

  @type state :: %__MODULE__{
          attribute_id: String.t(),
          connector_pid: pid(),
          connector_id: String.t(),
          paused: boolean(),
          config: map(),
          messages_queue: list(),
          batch_push_messages: list(),
          batch_window_scheduled: boolean()
        }

  # Public API
  def start_link(%{attribute_id: attribute_id} = config) do
    Logger.info("Starting AttributeGenServer with config: #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple(attribute_id))
  end

  def get_state(attribute_id) do
    GenServer.call(via_tuple(attribute_id), :get_state)
  end

  # GenServer Callbacks
  @impl true
  def init(%{attribute_id: attribute_id} = config) do
    Logger.info("Initializing AttributeGenServer for #{attribute_id}")

    state = %__MODULE__{
      attribute_id: attribute_id,
      connector_pid: Map.get(config, :connector_pid),
      connector_id: Map.get(config, :connector_id),
      paused: false,
      config: config,
      messages_queue: [],
      batch_push_messages: [],
      batch_window_scheduled: false
    }

    Process.send_after(
      self(),
      :process_queue,
      0
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:delay_done, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} Delay done")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  @impl true
  def handle_info({:process_queue, delay}, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} handle_info:process_queue delayed #{delay} ms")
    Process.send_after(self(), :delay_done, delay)
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_queue, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} handle_info:process_queue")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  # empty queue handling

  @impl true
  def handle_cast(:process_queue, %{:attribute_id => attribute_id, :messages_queue => []} = state) do
    Logger.info("#{attribute_id} Empty queue, get new data")

    Process.send_after(
      self(),
      :get_data,
      0
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{
          :attribute_id => attribute_id,
          :messages_queue => [head | tail]
        } = state
      ) do
    Logger.debug("#{state.connector_id} #{attribute_id} Got message, HEAD: #{inspect(head)} TAIL: #{Enum.count(tail)}")

    # fetch new data if only 20% of the duration is left
    if(Enum.count(tail) < state.config.sampling_rate * (state.config.duration * 0.2)) do
      Logger.debug("#{state.connector_id} #{attribute_id} Low on messages, :get_data")

      Process.send_after(
        self(),
        :get_data,
        0
      )
    end

    Process.send_after(
      self(),
      {:push_message, head},
      0
    )

    {:noreply, state |> Map.put(:messages_queue, tail)}
  end

  @impl true
  def handle_cast(
        :process_queue,
        %{:attribute_id => attribute_id} = state
      ) do
    Logger.info("#{attribute_id} Default process_queue queue #{inspect(state)}")

    Process.send_after(
      self(),
      :process_queue,
      1000
    )

    {:noreply, state}
  end

  def get_config(attribute_id) do
    case Registry.lookup(SensorSimulatorRegistry, attribute_id) do
      [{pid, _}] ->
        Logger.debug("Client: get_config #{inspect(pid)} #{inspect(attribute_id)}")
        GenServer.call(pid, :get_config)

      [] ->
        Logger.debug("Client: get_config No sensor_found #{inspect(attribute_id)}")

      _ ->
        Logger.debug("Client: get_config ERROR #{inspect(attribute_id)}")
    end
  end

  def handle_info(:get_config, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} handle_info:get_config")
    {:ok, state}
  end

  def handle_call(:get_config, _from, %{attribute_id: attribute_id} = state) do
    {:reply, state, state}
  end

  def handle_info(
        {:set_config, config_key, config_value},
        %{:attribute_id => attribute_id} = state
      ) do
    old_value = Map.get(state, config_key)

    Logger.debug("#{state.connector_id} #{attribute_id} handle_info:set_config #{config_key} New: #{config_value}, Old: #{old_value}"
    )

    {:noreply, state |> Map.put(config_key, config_value)}
  end

  def handle_info(:get_data, %{:attribute_id => attribute_id} = state) do
    #Logger.debug("#{state.connector_id} #{attribute_id} handle_info:get_data")
    Logger.debug("Here")

    case Map.get(state, :get_data_updating_data) do
      true -> {:noreply, state}
      _ -> GenServer.cast(self(), :get_data)
    end

    {:noreply, state}
  end

  def handle_info({:get_data_result, data}, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} got data: #{Enum.count(data)}")
    newstate = Map.put(state, :messages_queue, Map.get(state, :messages_queue) ++ data)

    # Process.send_after(self(), :process_queue, 500)

    Process.send_after(
      self(),
      :process_queue,
      0
    )

    {:noreply, newstate |> Map.put(:get_data_updating_data, false)}
  end

  @impl true
  def handle_cast(:get_data, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} :get_data cast received")

    Process.send_after(
      :"biosense_data_server_#{:rand.uniform(4) + 1}",
      {:get_data, self(), state.config},
      0
    )

    {:noreply, state}
  end




  def handle_info({:push_message, message}, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id} #{attribute_id} handle_info:push_message")
    parent = self()
    GenServer.cast(parent, {:push_message, message})
    {:noreply, state}
  end

  def handle_cast(
        {:push_message, message},
        %{:attribute_id => attribute_id, :batch_push_messages => batch_push_messages} = state
      ) do
    {delay_s, _} = Float.parse("#{message.delay}")
    delay_ms_tmp = round(delay_s * 1000.0)
    {delay_ms, _} = Integer.parse("#{delay_ms_tmp}")

    Logger.debug("#{state.connector_id} : #{state.attribute_id} push message: #{inspect(message)}")
    #Logger.debug("Test")

    new_queue =
      batch_push_messages ++
        [message |> Map.put(:timestamp, :os.system_time(:milli_seconds) + delay_ms)]

    batch_size = state.config.batch_size || 10
    batch_window = state.config.batch_window || 5000

    Process.send_after(
      self(),
      {:process_queue, delay_ms_tmp},
      delay_ms_tmp
    )

    Logger.debug("#{state.connector_id} : #{state.attribute_id}  #{length(new_queue)}, batch_size: #{batch_size}, batch_window: #{batch_window} batch_window_scheduled: #{state.batch_window_scheduled}"
    )

    if length(new_queue) >= batch_size do
      Logger.debug("#{state.connector_id} : #{state.attribute_id} send_batch, pushing #{length(new_queue)}"
      )

      send_batch(new_queue, state)
    else
      Logger.debug("#{state.connector_id} : #{state.attribute_id} adding messages to queue #{length(new_queue)}")

      if not state.batch_window_scheduled do
        Logger.debug("#{state.connector_id} : #{state.attribute_id} Scheduling batch timeout")
        Process.send_after(self(), :batch_window, batch_window)
      end

      {:noreply,
       state
       |> Map.put(:batch_push_messages, new_queue)
       |> Map.put(:batch_window_scheduled, true)}
    end
  end

  defp send_batch(messages, %{:attribute_id => attribute_id} = state) do

    Logger.debug("#{state.connector_id}:#{state.attribute_id} Send batch: #{length(messages)}")

    {:noreply, state}

    if not state.paused do

      push_messages =
        Enum.map(messages, fn message ->
          %{
            "payload" => message.payload,
            # :os.system_time(:milli_seconds),
            "timestamp" => message.timestamp,
            "attribute_id" => state.config.sensor_type
          }
        end)

      Logger.debug("#{state.connector_id}:#{state.attribute_id} Push messages: #{length(push_messages)}")

      Process.send_after(state.connector_pid, {:push_batch, push_messages}, 0)

      {:noreply,
       state
       |> Map.put(:batch_push_messages, [])
       |> Map.put(:batch_window_scheduled, false)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:batch_window, %{:attribute_id => attribute_id, :batch_push_messages => batch_push_messages} = state) do
    Logger.debug("#{state.connector_id}:#{attribute_id} batch timeout #{length(batch_push_messages)}")

    if length(batch_push_messages) > 0 do
      send_batch(batch_push_messages, state)
    else
      {:noreply, state |> Map.put(:batch_window_scheduled, false)}
    end
  end






  defp via_tuple(attribute_id), do: {:via, Registry, {Sensocto.Registry, attribute_id}}
end
