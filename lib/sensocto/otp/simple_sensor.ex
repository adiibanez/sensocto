defmodule Sensocto.SimpleSensor do
  use GenServer
  require Logger
  alias Sensocto.AttributeStoreTiered, as: AttributeStore
  alias Sensocto.SimpleSensorRegistry
  alias Sensocto.Sensors.Sensor
  alias Sensocto.Sensors.SensorAttributeData
  alias Sensocto.Otp.RepoReplicatorPool

  # Add interval for mps calculation
  # 1 second
  @mps_interval 1_000

  @spec start_link(%{:sensor_id => any(), optional(any()) => any()}) ::
          :ignore | {:error, any()} | {:ok, pid()}
  def start_link(%{:sensor_id => sensor_id} = configuration) do
    Logger.debug("SimpleSensor start_link: #{inspect(configuration)}")
    GenServer.start_link(__MODULE__, configuration, name: via_tuple(sensor_id))
  end

  @impl true
  @spec init(map()) :: {:ok, %{:message_timestamps => [], optional(any()) => any()}}
  def init(%{:sensor_id => sensor_id, :sensor_name => sensor_name} = state) do
    Logger.debug("SimpleSensor state: #{inspect(state)}")

    schedule_mps_calculation()

    Sensor
    |> Ash.Changeset.for_create(:create, %{name: sensor_id})
    |> Ash.create()

    RepoReplicatorPool.sensor_up(sensor_id)

    {:ok,
     state
     |> Map.put(:attributes, state.attributes || %{})
     |> Map.merge(%{message_timestamps: []})
     |> Map.put(:mps_interval, 5000)}
  end

  def terminate(_reason, %{:sensor_id => sensor_id} = _state) do
    # Notify repo replicator pool (using correct pool API)
    RepoReplicatorPool.sensor_down(sensor_id)

    # Cleanup ETS warm tier tables
    AttributeStore.cleanup(sensor_id)

    # Note: Removed Ash sensor destroy - it was causing crashes due to incorrect API usage
    # The sensor record cleanup can be handled by the repo_replicator if needed
    :ok
  end

  # client
  def get_state(sensor_id, values \\ 1) do
    GenServer.call(
      via_tuple(sensor_id),
      {:get_state, values}
    )
  end

  def get_view_state(sensor_id, values \\ 1) do
    get_state(sensor_id, values) |> transform_state()
    # |> dbg()
  end

  defp transform_state(state) do
    metadata = state.metadata
    attributes = state.attributes

    transformed_attributes =
      metadata.attributes
      |> Enum.map(fn {attribute_name, attribute_metadata} ->
        # Handle both atom and string keys (string is now preferred for safety)
        attribute_name_string =
          if is_atom(attribute_name) do
            Atom.to_string(attribute_name)
          else
            to_string(attribute_name)
          end

        # Grab the values from the original attributes
        # Handle missing attribute gracefully
        # Use string key here
        values =
          Map.get(attributes, attribute_name_string, [])
          |> List.wrap()

        # Get last value from original attributes
        last_value = List.first(values)

        # Normalize attribute_type to atom key (templates expect this)
        attribute_type = get_attribute_type(attribute_metadata)

        {
          # Use string key to prevent atom exhaustion
          attribute_name_string,
          %{
            values: values,
            lastvalue: last_value,
            attribute_id: attribute_name_string,
            attribute_type: attribute_type,
            sampling_rate: get_in_flexible(attribute_metadata, [:sampling_rate, "sampling_rate"])
          }
        }
      end)
      |> Enum.into(%{})

    %{
      sensor_id: metadata.sensor_id,
      sensor_name: metadata.sensor_name,
      sensor_type: metadata.sensor_type,
      sampling_rate: metadata.sampling_rate,
      batch_size: metadata.batch_size,
      connector_id: metadata.connector_id,
      connector_name: metadata.connector_name,
      attributes: transformed_attributes
    }
  end

  def update_attribute_registry(
        sensor_id,
        action,
        attribute_id,
        metadata
      ) do
    Logger.debug(
      "Client: update_attribute_registry #{inspect(sensor_id)} #{inspect(action)} #{inspect(attribute_id)} #{inspect(metadata)} "
    )

    GenServer.cast(
      via_tuple(sensor_id),
      {:update_attribute_registry, action, attribute_id, metadata}
    )
  end

  def put_attribute(sensor_id, attribute) do
    GenServer.cast(
      via_tuple(sensor_id),
      {:put_attribute, attribute}
    )
  end

  def put_batch_attributes(sensor_id, attributes) do
    GenServer.cast(
      via_tuple(sensor_id),
      {:put_batch_attributes, attributes}
    )
  end

  def clear_attribute(sensor_id, attribute_id) do
    GenServer.cast(
      via_tuple(sensor_id),
      {:clear_attribute, attribute_id}
    )
  end

  def get_attribute(sensor_id, attribute_id, limit) do
    GenServer.cast(
      via_tuple(sensor_id),
      {:get_attribute, attribute_id, limit}
    )
  end

  def get_attribute(sensor_id, attribute_id, from \\ 0, to \\ :infinity, limit \\ :infinity) do
    GenServer.call(
      via_tuple(sensor_id),
      {:get_attribute, attribute_id, from, to, limit}
    )
  end

  # server
  @impl true
  def handle_call({:get_state, values}, _from, %{sensor_id: sensor_id} = state) do
    sensor_state = %{
      metadata: state |> Map.delete(:message_timestamps) |> Map.delete(:mps_interval),
      attributes:
        AttributeStore.get_attributes(sensor_id, values)
        # |> Enum.map(fn x -> cleanup(x) end)
        |> Enum.into(%{})
      #        |> dbg()
    }

    # Logger.debug("Sensor state: #{inspect(sensor_state)}")

    {:reply, sensor_state, state}
  end

  @impl true
  def handle_call({:get_attribute, attribute_id, limit}, _from, %{sensor_id: sensor_id} = state) do
    {:ok, attributes} = AttributeStore.get_attribute(sensor_id, attribute_id, limit)

    Logger.debug(
      "Server: :get_attribute (attribute_id, limit)  #{attribute_id}  with limit #{limit}  from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_call(
        {:get_attribute, attribute_id, from, to, limit},
        _from,
        %{sensor_id: sensor_id} = state
      ) do
    {:ok, attributes} =
      AttributeStore.get_attribute(sensor_id, attribute_id, from, to, limit)

    Logger.debug(
      "Server: :get_attribute (attribute_id, from, to, limit)  #{attribute_id} from: #{from} to: #{to} limit: #{limit} from : #{inspect(sensor_id)}, payloads: #{inspect(attributes)}"
    )

    {:reply, attributes, state}
  end

  @impl true
  def handle_cast(
        {:update_attribute_registry, action, attribute_id, metadata},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug(
      "Server: :update_attribute_registry sensor_id: #{sensor_id} action: #{action} attribute_id:  #{attribute_id}"
    )

    new_attributes =
      case action do
        :register ->
          Map.put(state.attributes, attribute_id, metadata)

        :unregister ->
          Map.delete(state.attributes, attribute_id)
          # TODO cleanup state data
      end

    new_state = state |> update_in([:attributes], fn _ -> new_attributes end)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "signal:#{sensor_id}",
      {
        :new_state,
        sensor_id
      }
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(
        {:put_attribute,
         %{:attribute_id => attribute_id, :payload => payload, :timestamp => timestamp} =
           attribute},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :put_attribute #{inspect(attribute)} state: #{inspect(state)}")

    AttributeStore.put_attribute(sensor_id, attribute_id, timestamp, payload)

    now = System.system_time(:millisecond)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "data:#{sensor_id}",
      {
        :measurement,
        attribute
        |> Map.put(:sensor_id, sensor_id)
      }
    )

    {:noreply,
     state
     |> Map.update!(:message_timestamps, &[now | &1])}
  end

  @impl true
  def handle_cast(
        {:put_batch_attributes, attributes},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :put_batch_attributes #{length(attributes)} state: #{inspect(state)}")

    # attributes |> dbg()

    broadcast_messages_list =
      Enum.map(attributes, fn attribute ->
        AttributeStore.put_attribute(
          sensor_id,
          attribute.attribute_id,
          attribute.timestamp,
          attribute.payload
        )

        attribute
        |> Map.put(:sensor_id, sensor_id)
      end)

    now = System.system_time(:millisecond)

    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "data:#{sensor_id}",
      {
        :measurements_batch,
        {sensor_id, broadcast_messages_list}
      }
    )

    {:noreply,
     state
     |> Map.update!(:message_timestamps, &[now | &1])}
  end

  @impl true
  def handle_cast(
        {:clear_attribute, attribute_id},
        %{sensor_id: sensor_id} = state
      ) do
    Logger.debug("Server: :clear_attribute #{sensor_id}:#{attribute_id} state: #{inspect(state)}")
    AttributeStore.remove_attribute(sensor_id, attribute_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        :calculate_mps,
        %{sensor_id: sensor_id, message_timestamps: timestamps, mps_interval: mps_interval} =
          state
      ) do
    now = System.system_time(:millisecond)
    interval_ago = now - mps_interval

    # Filter timestamps within the interval
    recent_timestamps = Enum.filter(timestamps, fn timestamp -> timestamp >= interval_ago end)
    mps = length(recent_timestamps) / (mps_interval / 1000)

    # Logger.debug("Server: :calculate_mps #{inspect(mps)}")

    # Emit telemetry event with MPS
    :telemetry.execute(
      [:sensocto, :sensors, :messages, :mps],
      %{value: mps},
      %{sensor_id: sensor_id}
    )

    # Schedule next calculation
    schedule_mps_calculation()
    {:noreply, %{state | message_timestamps: recent_timestamps}}
  end

  defp schedule_mps_calculation do
    Process.send_after(self(), :calculate_mps, @mps_interval)
  end

  # Helper to get attribute_type from mixed key maps
  defp get_attribute_type(metadata) do
    # Try atom key first, then string key
    case Map.get(metadata, :attribute_type) do
      nil -> Map.get(metadata, "attribute_type")
      val -> val
    end
  end

  # Helper to get value from map with either atom or string key
  defp get_in_flexible(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key)
    end)
  end

  def cleanup(entry) do
    case entry do
      {attribute_id, [entry]} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}

      {attribute_id, %{}} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}
    end
  end

  def via_tuple(sensor_id) do
    {:via, Registry, {SimpleSensorRegistry, sensor_id}}
    # {:via, Horde.Registry, {SimpleSensorRegistry, sensor_id}}
  end
end
