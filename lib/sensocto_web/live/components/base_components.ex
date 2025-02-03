defmodule SensoctoWeb.Live.BaseComponents do
  use Phoenix.Component
  require Logger
  use Timex
  import SensoctoWeb.Components.RangeField
  import Phoenix.Component

  use Gettext,
    backend: SensoctoWeb.Gettext

  def sensor(assigns) do
    assigns =
      assigns
      |> Map.put(:attribute_count, Enum.count(assigns.sensor.attributes))
      |> Map.put(:sensor_type, assigns.sensor.metadata.sensor_type)
      |> Map.put(:sampling_rate, assigns.sensor.metadata.sampling_rate)

    Logger.info("sensor #{assigns.sensor_id} #{inspect(assigns.__changed__)}")

    ~H"""
    <div id={"cnt_#{@sensor_id}"} class="">
      <.render_sensor_header sensor={@sensor}></.render_sensor_header>

      <div :if={@attribute_count == 0}>
        {render_loading(8, "#{@sensor_id}", assigns)}
      </div>

      <div
        :for={{attribute_id, attribute_data} <- @sensor.attributes}
        class="attribute"
        id={"#{@sensor_id}_#{attribute_id}"}
        class="bg-gray-800 text-xs m-0 p-1"
        phx-hook="SensorDataAccumulator"
        data-sensor_id={@sensor_id}
        data-attribute_id={attribute_id}
        data-sensor_type={attribute_id}
        phx-hook="SensorDataAccumulator"
      >
        <.attribute
          attribute_data={attribute_data}
          sensor_id={@sensor_id}
          sensor={@sensor}
          attribute_id={"#{attribute_id}"}
          sampling_rate={@sampling_rate}
        >
        </.attribute>
      </div>
    </div>
    """
  end

  def attribute(assigns) do
    assigns =
      assigns
      |> Map.put(:id, "viz_#{assigns.sensor_id}_#{assigns.attribute_id}")
      |> Map.put(:attribute_name, assigns.attribute_id)
      # |> Map.put(:attribute_id, assigns.attribute_id)
      |> Map.put(:windowsize, 10000)
      |> Map.put(
        :timestamp_formated,
        format_unix_timestamp(Enum.at(assigns.attribute_data, 0).timestamp)
      )
      |> Map.put(:payload, Enum.at(assigns.attribute_data, 0).payload)

    Logger.info(
      "attribute #{assigns.sensor_id} #{assigns.attribute_id} #{inspect(assigns.__changed__)}"
    )

    case assigns.sensor.metadata.sensor_type do
      "ecg" ->
        ~H"""
        <div>
          {render_attribute_header(assigns)}

          <sensocto-ecg-visualization
            is_loading="true"
            id={@id}
            sensor_id={@sensor_id}
            attribute_id={@attribute_id}
            samplingrate={@sampling_rate}
            phx-update="ignore"
            class="loading w-full m-0 p-0 resizeable"
            color="#ffc107"
            backgroundColor="transparent"
            highlighted_areas='{[
          {start: 250, end: 500, color: "lightgreen"},
          {start: 800, end: 1200, color: "lightgreen"},
          {start: 900, end: 1000, color: "red"},
         {start: 1400, end: 1600, color: "brown"}
        ]}'
          >
          </sensocto-ecg-visualization>
        </div>
        """

      "heartrate" ->
        ~H"""
        <div class="attribute flex-none">
          {render_attribute_header(assigns)}

          <div class="flex items-left">
            <p class="w-20 flex-none" style="border:0 solid white">
              {@payload}
            </p>

            <p class="flex-1">
              <sensocto-sparkline-wasm-svelte
                height="20"
                is_loading="true"
                id={@id}
                sensor_id={@sensor_id}
                attribute_id={@attribute_id}
                samplingrate={@sampling_rate}
                timewindow={@windowsize}
                timemode="relative"
                phx-update="ignore"
                class="resizeable loading w-full m-0 p-0"
                style="border:0 solid white"
              >
              </sensocto-sparkline-wasm-svelte>
            </p>
          </div>
          <div class="flex-none">
            <.range_field
              appearance="custom"
              value={@windowsize}
              color="warning"
              size="extra_small"
              min="1000"
              id="custom-range-1"
              max="60000"
              name="custom-range"
              step="500"
              rest={
                %{
                  "phx-hook" => "Formless",
                  "data-event" => "update-parameter",
                  "data-parameter" => "windowsize",
                  # "phx-debounce" => "500",
                  "data-sensor_id" => @sensor_id,
                  "data-attribute_id" => @attribute_id
                }
              }
            >
              <:range_value position="start">1sec</:range_value>
              <:range_value position="end">60sec</:range_value>
            </.range_field>

            <input
              type="number"
              value={@windowsize}
              class="w-20"
              phx-keyup="test"
              phx-value-sensor_id={@sensor_id}
              phx-value-attribute_id={@attribute_id}
            />
          </div>
        </div>
        """

      _ ->
        ~H"""
        <h2>Default Attribute</h2>
        <div>{inspect(assigns)}</div>
        <!--<p>Sensor: {inspect(assigns.sensor)}</p>
        <p>Attribute Data: {inspect(assigns.attribute_data)}</p>
        <p>Sensor_type: {assigns.sensor.metadata.sensor_type}</p>
        <p>Attribute_id: {assigns.attribute_id}</p>-->
        """
    end
  end

  def render_sensor_header(assigns) do
    assigns =
      assigns
      |> Map.put(:sensor_name, assigns.sensor.metadata.sensor_name)
      |> Map.put(:highlighted, get_in(assigns.sensor, [:highlighted]))
      |> Map.put(:sensor_id, assigns.sensor.metadata.sensor_id)

    Logger.info("sensor_header #{@sensor_id} #{inspect(assigns.__changed__)}")

    ~H"""
    <div class="flex items-right m-0 p-0" id={"sensor_header_#{@sensor_id}"}>
      <p class="flex-none font-bold text-s" style="border:0 solid white">
        {@sensor_name}
      </p>
      <p class="flex-1 float-left items-right">
        <Heroicons.icon
          id={"highlight_button_#{@sensor_id}"}
          name={
            if @highlighted do
              "magnifying-glass-minus"
            else
              "magnifying-glass-plus"
            end
          }
          type="outline"
          class="h-4 w-4"
          phx-click="toggle_highlight"
          phx-value-sensor_id={@sensor_id}
          style="border:0 solid white"
        />
      </p>
    </div>
    """
  end

  def render_attribute_header(assigns) do
    Logger.info("sensor_header #{@sensor_id} #{@attribute_id} #{inspect(assigns.__changed__)}")

    ~H"""
    <p class="text-xs text-gray-500" id="attribute_header{@sensor_id}_{@attribute_id}">
      {@attribute_name}
      <Heroicons.icon
        id={"trash_#{@sensor_id}_#{@attribute_id}"}
        name="trash"
        type="outline"
        class="h-4 w-4 float-right"
        phx-click="clear-attribute"
        phx-value-sensor_id={@sensor_id}
        phx-value-attribute_id={@attribute_id}
      />
    </p>
    """
  end

  def render_loading(_size, identifier, assigns) do
    assigns = assigns |> Map.put(:identifier, identifier)

    ~H"""
    <svg
      id={"loading_spinner_#{@identifier}"}
      aria-hidden="true"
      class="w-8 h-8 text-gray-200 animate-spin dark:text-gray-600 fill-blue-600"
      viewBox="0 0 100 101"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
        fill="currentColor"
      />
      <path
        d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
        fill="currentFill"
      />
    </svg>
    """
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
              Logger.info("invalid format unix timestamp #{inspect(timestamp_string)}")
              nil
          end

        _ ->
          Logger.info("invalid format unix timestamp #{inspect(timestamp)}")
          nil
      end

    # IO.inspect(timestamp_int, label: "Timestamp")

    if timestamp_int do
      try do
        {:ok, formatted_timestamp} =
          timestamp_int
          |> Timex.from_unix(:milliseconds)
          |> Timex.format("%FT%T%:z", :strftime)

        formatted_timestamp
      rescue
        _ ->
          Logger.info("invalid format unix timestamp #{inspect(timestamp)}")
          "Invalid Date"
      end
    else
      "Invalid Date"
    end
  end

  def viewdata_ready_attribute(attribute_data) do
    # TODO list vs map
    first_attribute_data = Enum.at(attribute_data, 0)

    #  Map.has_key?(first_attribute_data, :timestamp_formated)
    case is_list(attribute_data) and Map.has_key?(first_attribute_data, :payload) and
           Map.has_key?(first_attribute_data, :timestamp) do
      true ->
        # Logger.info("Viewdata ready attr YEP")
        true

      false ->
        # Logger.info("Viewdata ready attr NOPE")
        false
    end
  end

  def viewdata_ready_sensor(sensor) do
    # Logger.info("Viewdata ready sensor: #{Map.has_key?(sensor, :metadata)}")

    if is_map(sensor) do
      case Map.has_key?(sensor, :metadata) do
        true ->
          # Logger.info("Viewdata ready sensor YEP: #{Map.has_key?(sensor, :metadata)}")
          true

        false ->
          # Logger.info("Viewdata ready sensor NOPE: #{Map.has_key?(sensor, :metadata)}")
          false
      end
    else
      false
    end
  end
end
