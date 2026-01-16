defmodule Sensocto.Otp.RepoReplicator do
  use GenServer
  require Logger
  alias Phoenix.PubSub
  alias Sensocto.Sensors.SensorAttributeData
  alias Ash.Changeset

  ## Public API

  def start_link(_args) do
    Logger.debug("RepoReplicator starting...")
    GenServer.start_link(__MODULE__, %{}, name: :sensocto_repo_replicator)
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    Logger.info("RepoReplicator started, waiting for sensor subscriptions")
    {:ok, state}
  end

  ## Handle sensor subscription requests
  @impl true
  def handle_cast({:sensor_up, sensor_id}, state) do
    PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
    Logger.info("Subscribed to sensor: #{sensor_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:sensor_down, sensor_id}, state) do
    PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")
    Logger.info("Unsubscribed from sensor: #{sensor_id}")
    {:noreply, state}
  end

  ## Handle single measurement inserts
  @impl true
  def handle_info(
        {:measurement,
         %{
           :payload => payload,
           :timestamp => timestamp,
           :attribute_id => attribute_id,
           :sensor_id => sensor_id
         } =
           attribute},
        state
      ) do
    Logger.debug("Received measurement for sensor #{sensor_id}: #{inspect(attribute)}")

    {:ok, datetime} = DateTime.from_unix(timestamp, :millisecond)

    _changeset =
      SensorAttributeData
      |> Changeset.for_create(:create, %{
        sensor_id: sensor_id,
        attribute_id: attribute_id,
        timestamp: datetime,
        payload: ensure_map(payload)
      })

    # case Ash.create(changeset) do
    #   {:ok, _record} ->
    #     Logger.info("✅ Measurement inserted successfully for sensor #{sensor_id}")

    #   {:error, reason} ->
    #     Logger.error("❌ Failed to insert measurement: #{inspect(reason)}")
    # end

    {:noreply, state}
  end

  ## Handle batch measurement inserts
  @impl true
  def handle_info({:measurements_batch, {sensor_id, attributes}}, state) do
    Logger.debug("Received batch of #{length(attributes)} measurements for sensor #{sensor_id}")

    _records =
      Enum.flat_map(attributes, fn attr ->
        with {:ok, attribute_id} <- attr["attribute_id"],
             {:ok, datetime} <- DateTime.from_unix(attr["timestamp"], :millisecond),
             {:ok, timestamp} <- datetime,
             payload <- ensure_map(attr["payload"]) do
          [
            %{
              sensor_id: sensor_id,
              attribute_id: attribute_id,
              timestamp: timestamp,
              payload: payload
            }
          ]
        else
          _ -> []
        end
      end)

    # case Ash.bulk_create(records, SensorAttributeData, :create) do
    #   {:ok, _result} ->
    #     Logger.info(
    #       "✅ Batch insert successful for #{length(records)} measurements (Sensor #{sensor_id})"
    #     )

    #   {:error, reason} ->
    #     Logger.error("❌ Batch insert failed: #{inspect(reason)}")
    # end

    {:noreply, state}
  end

  ## Catch-all for unexpected messages
  def handle_info(msg, state) do
    Logger.warning("⚠️ Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Helper functions

  # defp parse_datetime(nil), do: {:error, "Missing timestamp"}

  # defp parse_datetime(value) when is_integer(value) do
  #   {:ok, DateTime.from_unix(value, :millisecond)}
  # end

  # defp parse_datetime(value) when is_binary(value) do
  #   case DateTime.from_iso8601(value) do
  #     {:ok, datetime, _} -> {:ok, datetime}
  #     _ -> {:error, "Invalid datetime format"}
  #   end
  # end

  # defp parse_datetime(value) when is_struct(value, DateTime), do: {:ok, value}
  # defp parse_datetime(_), do: {:error, "Unrecognized datetime format"}

  defp ensure_map(nil), do: %{}
  defp ensure_map(value) when is_map(value), do: value

  defp ensure_map(value) when is_binary(value) do
    Logger.debug("ensure_map #{inspect(value)}")

    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp ensure_map(_), do: %{}
end
