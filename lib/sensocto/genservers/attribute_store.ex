defmodule Sensocto.AttributeStore do
  use Agent
  require Logger

  @default_limit 100_000

  def start_link(%{:sensor_id => sensor_id} = configuration) do
    Logger.debug("SimpleSensor start_link2: #{inspect(configuration)}")
    # IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for sensor")
    Agent.start_link(fn -> %{} end, name: via_tuple(sensor_id))
  end

  def put_attribute(sensor_id, attribute_id, timestamp, payload) do
    Agent.update(via_tuple(sensor_id), fn state ->
      srv_put_attribute_state(state, attribute_id, timestamp, payload)
    end)
  end

  # def get_attributes(sensor_id) do
  #   # Logger.debug("Agent client get_attributes #{sensor_id}")
  #   Agent.get(via_tuple(sensor_id), & &1)
  # end

  def get_attributes(sensor_id, limit \\ @default_limit) do
    # Logger.debug("Agent client get_attributes #{sensor_id} limit: #{limit}")
    Agent.get(via_tuple(sensor_id), fn state ->
      Enum.reduce(state, %{}, fn {attribute_id, attr}, acc ->
        limited_payloads =
          case attr do
            %{payloads: payloads} -> Enum.take(Enum.reverse(payloads), limit)
            _ -> []
          end

        Map.put(acc, attribute_id, limited_payloads)
      end)
    end)
  end

  @spec get_attribute(any(), any(), any(), any(), any()) :: any()
  def get_attribute(
        sensor_id,
        attribute_id,
        from_timestamp,
        to_timestamp \\ :infinity,
        limit \\ @default_limit
      ) do
    Agent.get(via_tuple(sensor_id), fn state ->
      case Map.get(state, attribute_id) do
        nil ->
          Logger.debug("No attribute data for #{sensor_id}")
          {:ok, []}

        %{payloads: payloads} ->
          payloads
          |> maybe_filter(from_timestamp, to_timestamp)
          |> maybe_limit(limit)

          Logger.debug(
            "Agent: attribute data for #{sensor_id} #{is_nil(limit)} from: #{from_timestamp} to: #{to_timestamp} #{inspect(limit)} #{inspect(payloads)}"
          )

          {:ok, payloads}
      end
    end)
  end

  defp maybe_filter(payloads, from_timestamp, to_timestamp)
       when not is_nil(from_timestamp) and not is_nil(to_timestamp) do
    Enum.filter(payloads, fn %{timestamp: timestamp} ->
      timestamp >= from_timestamp && timestamp <= to_timestamp
    end)
  end

  defp maybe_filter(payloads, from_timestamp, to_timestamp)
       when not is_nil(from_timestamp) do
    Enum.filter(payloads, fn %{timestamp: timestamp} ->
      timestamp >= from_timestamp
    end)
  end

  defp maybe_filter(payloads, from_timestamp, to_timestamp) do
    payloads
  end

  defp maybe_limit(payloads, limit) when not is_nil(limit) do
    Enum.take(payloads, limit)
  end

  defp maybe_limit(payloads, limit) do
    payloads
  end

  def remove_attribute(sensor_id, attribute_id) do
    Agent.update(via_tuple(sensor_id), fn state ->
      # 1. Delete attribute and capture the result
      new_state = Map.delete(state, attribute_id)

      # 2. Log based on the presence of the attribute after deletion
      if Map.has_key?(new_state, attribute_id) do
        Logger.debug("Map delete failed or did not exist: #{sensor_id}:#{attribute_id}")
      else
        Logger.debug("Map delete success: #{sensor_id}:#{attribute_id}")
      end

      # 3. Log the attribute history after deletion
      case Map.get(new_state, attribute_id) do
        nil ->
          Logger.debug("Map get success, nil value after delete: #{sensor_id}:#{attribute_id}")

        _ ->
          Logger.debug("Map get failed, value still exists: #{sensor_id}:#{attribute_id}")
      end

      # 4. Return new state for Agent
      new_state
    end)
  end

  defp srv_put_attribute_state(state, attribute_id, timestamp, payload) do
    new_attribute =
      case Map.get(state, attribute_id) do
        # nil -> %{payloads: [], sampling_rate: sampling_rate}
        nil -> %{payloads: []}
        attribute -> attribute
      end

    new_payloads = [%{payload: payload, timestamp: timestamp} | new_attribute.payloads]
    limited_payloads = Enum.take(new_payloads, -10000)

    Map.put(state, attribute_id, %{new_attribute | payloads: limited_payloads})
  end

  defp via_tuple(sensor_id) do
    # Sensocto.RegistryUtils.via_dynamic_registry(Sensocto.SimpleAttributeRegistry, sensor_id)

    {:via, Registry, {Sensocto.SimpleAttributeRegistry, sensor_id}}
  end
end
