defmodule Sensocto.Otp.RepoReplicatorWorker do
  @moduledoc """
  Individual worker in the RepoReplicator pool.

  Each worker handles a subset of sensors and batches database writes
  for better throughput at scale.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  # Alias kept for when database writes are enabled
  # alias Sensocto.Sensors.SensorAttributeData

  # Batch settings for database writes
  @batch_size 100
  @batch_timeout_ms 1000

  defstruct [:index, :subscribed_sensors, :pending_writes, :batch_timer_ref]

  ## Public API

  def start_link(opts) do
    index = Keyword.fetch!(opts, :index)
    GenServer.start_link(__MODULE__, opts, name: worker_name(index))
  end

  @doc """
  Generate the worker name for a given index.
  """
  def worker_name(index) do
    :"repo_replicator_worker_#{index}"
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    index = Keyword.fetch!(opts, :index)
    Logger.debug("RepoReplicatorWorker #{index} starting")

    state = %__MODULE__{
      index: index,
      subscribed_sensors: MapSet.new(),
      pending_writes: [],
      batch_timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:sensor_up, sensor_id}, state) do
    PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
    Logger.debug("Worker #{state.index}: Subscribed to sensor #{sensor_id}")

    new_sensors = MapSet.put(state.subscribed_sensors, sensor_id)
    {:noreply, %{state | subscribed_sensors: new_sensors}}
  end

  @impl true
  def handle_cast({:sensor_down, sensor_id}, state) do
    PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")
    Logger.debug("Worker #{state.index}: Unsubscribed from sensor #{sensor_id}")

    new_sensors = MapSet.delete(state.subscribed_sensors, sensor_id)
    {:noreply, %{state | subscribed_sensors: new_sensors}}
  end

  ## Handle single measurement - add to batch
  @impl true
  def handle_info(
        {:measurement,
         %{
           payload: payload,
           timestamp: timestamp,
           attribute_id: attribute_id,
           sensor_id: sensor_id
         }},
        state
      ) do
    record = build_record(sensor_id, attribute_id, timestamp, payload)
    state = add_to_batch(state, record)
    {:noreply, state}
  end

  ## Handle batch measurements
  @impl true
  def handle_info({:measurements_batch, {sensor_id, attributes}}, state) do
    records =
      Enum.flat_map(attributes, fn attr ->
        case build_record_from_map(sensor_id, attr) do
          {:ok, record} -> [record]
          :error -> []
        end
      end)

    state = Enum.reduce(records, state, &add_to_batch(&2, &1))
    {:noreply, state}
  end

  ## Flush batch timer
  @impl true
  def handle_info(:flush_batch, state) do
    state = flush_pending_writes(state)
    {:noreply, %{state | batch_timer_ref: nil}}
  end

  ## Catch-all for unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.warning("Worker #{state.index}: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Stats request
  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      index: state.index,
      subscribed_sensors: MapSet.size(state.subscribed_sensors),
      pending_writes: length(state.pending_writes)
    }

    {:reply, stats, state}
  end

  ## Private helpers

  defp add_to_batch(state, record) do
    pending = [record | state.pending_writes]

    cond do
      length(pending) >= @batch_size ->
        flush_pending_writes(%{state | pending_writes: pending})

      is_nil(state.batch_timer_ref) ->
        timer_ref = Process.send_after(self(), :flush_batch, @batch_timeout_ms)
        %{state | pending_writes: pending, batch_timer_ref: timer_ref}

      true ->
        %{state | pending_writes: pending}
    end
  end

  defp flush_pending_writes(%{pending_writes: []} = state), do: state

  defp flush_pending_writes(state) do
    # Cancel timer if set
    if state.batch_timer_ref do
      Process.cancel_timer(state.batch_timer_ref)
    end

    records = Enum.reverse(state.pending_writes)
    count = length(records)

    # Uncomment to enable database writes:
    # case Ash.bulk_create(records, SensorAttributeData, :create,
    #        return_errors?: true,
    #        return_records?: false) do
    #   %{status: :success} ->
    #     Logger.debug("Worker #{state.index}: Batch insert of #{count} records successful")
    #
    #   %{errors: errors} ->
    #     Logger.error("Worker #{state.index}: Batch insert failed: #{inspect(errors)}")
    # end

    Logger.debug("Worker #{state.index}: Would flush #{count} records (writes disabled)")

    %{state | pending_writes: [], batch_timer_ref: nil}
  end

  defp build_record(sensor_id, attribute_id, timestamp, payload) do
    {:ok, datetime} = DateTime.from_unix(timestamp, :millisecond)

    %{
      sensor_id: sensor_id,
      attribute_id: attribute_id,
      timestamp: datetime,
      payload: ensure_map(payload)
    }
  end

  defp build_record_from_map(sensor_id, attr) do
    with attribute_id when is_binary(attribute_id) <- attr["attribute_id"],
         timestamp when is_integer(timestamp) <- attr["timestamp"],
         {:ok, datetime} <- DateTime.from_unix(timestamp, :millisecond) do
      {:ok,
       %{
         sensor_id: sensor_id,
         attribute_id: attribute_id,
         timestamp: datetime,
         payload: ensure_map(attr["payload"])
       }}
    else
      _ -> :error
    end
  end

  defp ensure_map(nil), do: %{}
  defp ensure_map(value) when is_map(value), do: value

  defp ensure_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp ensure_map(_), do: %{}
end
