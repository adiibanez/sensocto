defmodule SensoctoWeb.Live.BaseComponents do
  use Phoenix.Component
  require Logger
  use Timex
  alias Timex.DateTime

  alias SensoctoWeb.Components.SensorTypes.HeartrateComponent
  alias SensoctoWeb.Components.SensorTypes.EcgSensorComponent
  alias SensoctoWeb.Components.SensorTypes.HighSamplingRateSensorComponent
  alias SensoctoWeb.Components.SensorTypes.GenericSensorComponent

  use Gettext,
    backend: SensoctoWeb.Gettext

  def render_sensor_header(assigns) do
    ~H"""
    <div class="m-0 p-2">
      <p class="font-bold text-s">
        {@sensor.sensor_name}
      </p>
    </div>
    """
  end

  def render_attribute_header(assigns) do
    ~H"""
    <p>Type: {@sensor.sensor_type}</p>
    <p class="text-xs text-gray-500">{assigns.sensor_data.timestamp_formated}</p>
    """
  end

  def render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
      when sensor_type in ["ecg"] do
    ~H"""
    <.live_component id={sensor_data.id} module={EcgSensorComponent} sensor_data={sensor_data} />
    """
  end

  def render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
      when sensor_type in ["pressure", "flex", "eda", "emg", "rsp"] do
    ~H"""
    <.live_component
      id={sensor_data.id}
      module={HighSamplingRateSensorComponent}
      sensor_data={sensor_data}
    />
    """
  end

  def render_sensor_by_type(%{sensor_type: "heartrate"} = sensor_data, assigns) do
    ~H"""
    <p class="hidden">Attribute data: {inspect(sensor_data)}</p>
    <.live_component id={sensor_data.id} module={HeartrateComponent} sensor_data={sensor_data} />
    """
  end

  def render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns) do
    ~H"""
    <.live_component id={sensor_data.id} module={GenericSensorComponent} sensor_data={sensor_data} />
    """
  end

  def render_sensor_by_type(sensor_data, assigns) do
    ~H"""
    <div>Unknown sensor_type {inspect(sensor_data)}</div>
    """
  end

  def get_attribute_view_data(id, sensor_metadata, attribute_data) do
    # TODO check format list vs map
    first_attribute_data = Enum.at(attribute_data, 0)

    %{
      :sensor_type => id,
      :payload => first_attribute_data.payload,
      :timestamp_formated => format_unix_timestamp(first_attribute_data.timestamp),
      :sampling_rate => sensor_metadata.sampling_rate,
      :id => "#{sensor_metadata.sensor_id}_#{id}"
    }
  end

  def format_unix_timestamp(timestamp) do
    timestamp_int =
      case timestamp do
        timestamp_int when is_integer(timestamp_int) ->
          timestamp_int

        timestamp_string when is_binary(timestamp_string) ->
          case Integer.parse(timestamp_string) do
            {timestamp_int, _} ->
              timestamp_int

            _ ->
              Logger.debug("invalid format unix timestamp #{inspect(timestamp_string)}")
              nil
          end

        _ ->
          Logger.debug("invalid format unix timestamp #{inspect(timestamp)}")
          nil
      end

    # IO.inspect(timestamp_int, label: "Timestamp")

    timestamp_formatted =
      if timestamp_int do
        try do
          {:ok, formatted_timestamp} =
            timestamp_int
            |> Timex.from_unix(:milliseconds)
            |> Timex.format("%FT%T%:z", :strftime)

          formatted_timestamp
        rescue
          _ ->
            Logger.debug("invalid format unix timestamp #{inspect(timestamp)}")
            "Invalid Date"
        end
      else
        "Invalid Date"
      end
  end
end
