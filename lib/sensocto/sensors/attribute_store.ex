defmodule Sensocto.AttributeStore do
  use Agent
  require Logger

  def start_link(%{:sensor_id => sensor_id} = configuration) do
    IO.puts("SimpleSensor start_link2: #{inspect(configuration)}")
    # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
    Agent.start_link(fn -> %{} end, name: via_tuple(sensor_id))
  end

  def put_attribute(sensor_id, attribute_id, timestamp, payload) do
    Agent.update(via_tuple(sensor_id), fn state ->
      srv_put_attribute_state(state, attribute_id, timestamp, payload)
    end)
  end

  def get_attributes(sensor_id) do
    Logger.debug("Agent client get_attributes #{sensor_id}")
    Agent.get(via_tuple(sensor_id), & &1)
  end

  @spec get_attribute(any(), any(), any()) :: any()
  def get_attribute(sensor_id, attribute_id, limit) do
    Logger.debug("Agent client get_attribute #{sensor_id}")
    Agent.get(via_tuple(sensor_id), fn state ->
      case Map.get(state, attribute_id) do
        nil -> []
        %{payloads: payloads} -> Enum.take(Enum.reverse(payloads), limit)
      end
    end)
  end

  def get_attribute(sensor_id, attribute_id, from_timestamp, to_timestamp) do
    Agent.get(via_tuple(sensor_id), fn state ->
      case Map.get(state, attribute_id) do
        nil ->
          []

        %{payloads: payloads} ->
          Enum.filter(payloads, fn %{timestamp: timestamp} ->
            timestamp >= from_timestamp && timestamp <= to_timestamp
          end)
      end
    end)
  end

  def remove_attribute(sensor_id, attribute_id) do
    Agent.update(via_tuple(sensor_id), fn state ->
      Map.delete(state, attribute_id)
    end)
  end

  defp srv_put_attribute_state(state, attribute_id, timestamp, payload) do
    new_attribute =
      case Map.get(state, attribute_id) do
        #nil -> %{payloads: [], sampling_rate: sampling_rate}
        nil -> %{payloads: []}
        attribute -> attribute
      end

    new_payloads = [%{payload: payload, timestamp: timestamp} | new_attribute.payloads]
    limited_payloads = Enum.take(new_payloads, -10000)

    Map.put(state, attribute_id, %{new_attribute | payloads: limited_payloads})
  end

  defp via_tuple(sensor_id),
    do: {:via, Registry, {Sensocto.SimpleAttributeRegistry, sensor_id}}
end
