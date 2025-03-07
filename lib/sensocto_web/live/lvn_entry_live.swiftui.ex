defmodule SensoctoWeb.Live.LvnEntryLive.SwiftUI do
  use SensoctoNative, [:render_component, format: :swiftui]
  require Logger

  def attribute(assigns, _interface) do
    ~LVN"""
    <Group>
      <ProgressView id={"loading_#{@sensor_id}_#{@attribute_id}"} :if={is_nil(@attribute.lastvalue) or is_nil(@attribute.lastvalue.timestamp)}/>

      <VStack alignment="left" :if={not is_nil(@attribute.lastvalue) and not is_nil(@attribute.lastvalue.timestamp)}>
      <Text style="font(.subheadline)">{@attribute_id}</Text>
      <HStack>
        <Text>Update:</Text>
        <Text style="font(.callout)">{time_ago_from_unix(@attribute.lastvalue.timestamp)}</Text>
      </HStack>
      <HStack id={"attribute_value_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Value:</Text>
        <Text style="font(.callout)">{render_attribute_payload(@attribute.lastvalue.payload)}</Text>
      </HStack>
      <HStack id={"attribute_type_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Type:</Text>
        <Text style="font(.callout)">{inspect(@attribute.attribute_type)}</Text>
      </HStack>
      <HStack id={"attribute_samplingrate_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Sampling rate:</Text>
        <Text style="font(.callout)">{inspect(@attribute.sampling_rate)}</Text>
      </HStack>
      </VStack>
    </Group>
    """
  end

  def ble_characteristic(assigns, _interface) do
    ~LVN"""
    <Group>
      <VStack alignment="left" :if={not is_nil(@attribute.lastvalue) and not is_nil(@attribute.lastvalue.timestamp)}>
      <Text style="font(.subheadline)">{@attribute_id}</Text>
      <HStack>
        <Text>Update:</Text>
        <Text style="font(.callout)">{time_ago_from_unix(@attribute.lastvalue.timestamp)}</Text>
      </HStack>
      <HStack id={"attribute_value_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Value:</Text>
        <Text style="font(.callout)">{render_attribute_payload(@attribute.lastvalue.payload)}</Text>
      </HStack>
      <HStack id={"attribute_type_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Type:</Text>
        <Text style="font(.callout)">{inspect(@attribute.attribute_type)}</Text>
      </HStack>
      <HStack id={"attribute_samplingrate_#{@sensor_id}_#{@attribute_id}"}>
        <Text>Sampling rate:</Text>
        <Text style="font(.callout)">{inspect(@attribute.sampling_rate)}</Text>
      </HStack>
      </VStack>
    </Group>
    """
  end

  def render_attribute_payload(payload) do
    case Sensocto.Utils.typeof(payload) do
      "integer" ->
        Integer.to_string(payload)

      "float" ->
        Float.to_string(payload)

      type ->
        "#{type} : #{inspect(payload)}"
    end
  end

  def time_ago_from_unix(timestamp) do
    # timestamp |> dbg()

    diff = Timex.diff(Timex.now(), Timex.from_unix(timestamp, :millisecond), :millisecond)

    case diff > 1000 do
      true ->
        timestamp
        |> Timex.from_unix(:milliseconds)
        |> Timex.format!("{relative}", :relative)

      _ ->
        "#{abs(diff)}ms ago"
    end
  end
end
