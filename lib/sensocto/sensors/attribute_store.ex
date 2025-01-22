defmodule Sensocto.AttributeStore do
  use Agent

  def start_link(configuration) do
    IO.inspect(via_tuple(configuration.sensor_id), label: "via tuple for attributestore")

    IO.puts(
      "AttributeStore #{inspect(via_tuple(configuration.sensor_id))} #{inspect(configuration.sensor_id)}"
    )

    Agent.start_link(fn -> %{} end, name: via_tuple(configuration.sensor_id))
  end

  def put_attribute(sensor_id, attribute_id, timestamp, value) do
    pid = get_pid(sensor_id)

    IO.puts(
      "AttributeStore put_attribute sensor_id: #{sensor_id}, #{inspect(pid)}, #{inspect(attribute_id)}, #{inspect(timestamp)}, #{inspect(value)}"
    )

    Agent.update(pid, fn state ->
      Map.put(state, attribute_id, value)
    end)
  end

  def get_attributes(sensor_id) do
    pid = get_pid(sensor_id)
    IO.puts("AttributeStore get_attributes sensor_id: #{sensor_id}, #{inspect(pid)}")
    Agent.get(pid, & &1)
  end

  def get_pid(sensor_id) do
    case Registry.lookup(Sensocto.SimpleAttributeRegistry, sensor_id) do
      [{pid, _}] ->
        pid

      _ ->
        :error
    end
  end

  defp via_tuple(sensor_id), do: {:via, Registry, {Sensocto.SimpleAttributeRegistry, sensor_id}}
end
