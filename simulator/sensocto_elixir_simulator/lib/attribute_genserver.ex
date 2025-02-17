defmodule Sensocto.Simulator.AttributeGenServer do
  use GenServer
  require Logger

  @enforce_keys [:attribute_id]
  defstruct @enforce_keys ++
              [
                :state_data,
                :connector_id,
                :sensor_pid,
                :sensor_id,
                :paused,
                :config,
                :messages_queue,
                :batch_push_messages
              ]

  @type state :: %__MODULE__{
          attribute_id: String.t(),
          sensor_pid: pid(),
          sensor_id: String.t(),
          connector_id: String.t(),
          paused: boolean(),
          config: map(),
          messages_queue: list(),
          batch_push_messages: list()
        }

  # Public API
  def start_link(
        %{connector_id: connector_id, sensor_id: sensor_id, attribute_id: attribute_id} = config
      ) do
    Logger.info("Starting AttributeGenServer with config: #{inspect(config)}")

    GenServer.start_link(__MODULE__, config,
      name: via_tuple("#{connector_id}_#{sensor_id}_#{attribute_id}")
    )
  end

  def get_state(attribute_id) do
    GenServer.call(via_tuple(attribute_id), :get_state)
  end

  # GenServer Callbacks
  @impl true
  def init(%{attribute_id: attribute_id} = config) do
    Logger.info(
      "#{config.connector_id}:#{config.sensor_id}:#{attribute_id} AttributeGenServer for #{attribute_id}"
    )

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

    Process.send_after(
      self(),
      :process_queue,
      0
    )

    Process.send_after(self(), :batch_window, config.batch_window)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:delay_done, %{:attribute_id => attribute_id} = state) do
    Logger.debug("#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  Delay done")
    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  @impl true
  def handle_info({:process_queue, delay}, %{:attribute_id => attribute_id} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} handle_info:process_queue delayed #{delay} ms"
    )

    Process.send_after(self(), :delay_done, delay)
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_queue, %{:attribute_id => attribute_id} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} handle_info:process_queue"
    )

    GenServer.cast(self(), :process_queue)
    {:noreply, state}
  end

  # empty queue handling

  @impl true
  def handle_cast(:process_queue, %{:attribute_id => attribute_id, :messages_queue => []} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} Empty queue, get new data"
    )

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
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} Got message, HEAD: #{inspect(head)} TAIL: #{Enum.count(tail)}"
    )

    # fetch new data if only 20% of the duration is left
    # if(Enum.count(tail) < state.config.sampling_rate * (state.config.duration * 0.2)) do
    #   Logger.debug(
    #     "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  Low on messages, :get_data"
    #   )

    #   Process.send_after(
    #     self(),
    #     :get_data,
    #     0
    #   )
    # end

    Process.send_after(
      self(),
      {:push_message, head},
      0
    )

    {:noreply, state |> Map.put(:messages_queue, tail)}
  end

  def handle_info(:get_config, %{:attribute_id => attribute_id} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} handle_info:get_config"
    )

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

    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} handle_info:set_config #{config_key} New: #{config_value}, Old: #{old_value}"
    )

    {:noreply, state |> Map.put(config_key, config_value)}
  end

  def handle_info(:get_data, %{:attribute_id => attribute_id} = state) do
    # Logger.debug("#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  handle_info:get_data")

    case Map.get(state, :get_data_updating_data) do
      true -> {:noreply, state}
      _ -> GenServer.cast(self(), :get_data)
    end

    {:noreply, state}
  end

  def handle_info({:get_data_result, data}, %{:attribute_id => attribute_id} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} got data: #{Enum.count(data)}"
    )

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
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  :get_data cast received"
    )

    Process.send_after(
      :"biosense_data_server_#{:rand.uniform(4) + 1}",
      {:get_data, self(), state.config},
      0
    )

    {:noreply, state}
  end

  def handle_info({:push_message, message}, %{:attribute_id => attribute_id} = state) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} handle_info:push_message"
    )

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

    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  push message: #{inspect(message)}"
    )

    # + delay_ms
    new_queue =
      batch_push_messages ++
        [message |> Map.put(:timestamp, :os.system_time(:milli_seconds))]

    batch_size = state.config.batch_size || 10
    batch_window = state.config.batch_window || 5000

    Process.send_after(
      self(),
      {:process_queue, delay_ms_tmp},
      delay_ms_tmp
    )

    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  #{length(new_queue)}, batch_size: #{batch_size}, batch_window: #{batch_window}"
    )

    if length(new_queue) >= batch_size do
      Logger.debug(
        "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} send_batch, pushing #{length(new_queue)}"
      )

      GenServer.cast(self: {:push_batch, new_queue})
      {:no_reply, state}
    else
      Logger.debug(
        "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id} adding messages to queue #{length(new_queue)}"
      )

      {:noreply,
       state
       |> Map.put(:batch_push_messages, new_queue)}
    end
  end

  def handle_cast(
        {:push_batch, messages},
        %{:attribute_id => attribute_id, :batch_push_messages => batch_push_messages} = state
      ) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  Send batch: #{length(messages)}"
    )

    if not state.paused do
      push_messages =
        Enum.map(messages, fn message ->
          %{
            "payload" => message.payload,
            "timestamp" => message.timestamp,
            "attribute_id" => state.config.sensor_type
          }
        end)

      Process.send_after(state.sensor_pid, {:push_batch, attribute_id, push_messages}, 0)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        :batch_window,
        %{
          :attribute_id => attribute_id,
          :batch_push_messages => batch_push_messages,
          :config => config
        } = state
      ) do
    Logger.debug(
      "#{state.connector_id}:#{state.sensor_id}:#{state.attribute_id}  batch timeout #{config.batch_window}ms batch_push_messages: #{length(batch_push_messages)}"
    )

    Process.send_after(self(), :batch_window, config.batch_window)

    if length(batch_push_messages) > 0 do
      GenServer.cast(self(), {:push_batch, batch_push_messages})

      {:noreply,
       state
       |> Map.put(:batch_push_messages, [])}
    else
      {:noreply, state}
    end
  end

  defp via_tuple(identifier),
    do: {:via, Registry, {Sensocto.Registry, "#{__MODULE__}_#{identifier}"}}
end
