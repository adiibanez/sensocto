defmodule SensoctoWeb.Components.SensorTypes do
  import SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger
end

defmodule SensoctoWeb.Components.SensorTypes.EcgSensorComponent do
  import SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  @impl true
  def render(assigns) do
    import SensoctoWeb.Live.BaseComponents

    assigns =
      assigns
      |> Map.put(:sensor_id, assigns.sensor_data.sensor_id)

    ~H"""
    <div>
      {render_attribute_header(assigns)}

      <sensocto-ecg-visualization
        is_loading="true"
        id={ "ecg-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
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
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HighSamplingRateSensorComponent do
  import SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    import SensoctoWeb.Live.BaseComponents

    ~H"""
    <div class="attribute">
      
    <!--<sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="500"
        timemode="absolute"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>-->

      {render_attribute_header(assigns)}

      <sensocto-chartjs
        width="300"
        height="30"
        color="#ffc107"
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="absolute"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-chartjs>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.HeartrateComponent do
  import SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    import SensoctoWeb.Live.BaseComponents

    assigns =
      assigns
      |> Map.put(:sensor_id, assigns.sensor_data.sensor_id)
      |> Map.put(:attribute_id, assigns.sensor_data.attribute_id)
      |> Map.put(:sampling_rate, assigns.sensor_data.sampling_rate)
      |> Map.put(:payload, assigns.sensor_data.payload)

    ~H"""
    <div class="attribute flex-none">
      {render_attribute_header(assigns)}
      <!--<sensocto-sparkline
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="relative"
        phx-update="ignore"
        class="loading w-full m-0 p-0"
      >
      </sensocto-sparkline>-->

      <!--<sensocto-chartjs
        is_loading="true"
        id={ "sparkline_element-" <> assigns.id }
        identifier={assigns.sensor_data.id}
        samplingrate={assigns.sensor_data.sampling_rate}
        timewindow="5000"
        timemode="relative"
        phx-update="ignore"
        class="resizeable loading w-full m-0 p-0"
      >
      </sensocto-chartjs>
      -->

      <div class="flex items-left">
        <p class="w-20 flex-none" style="border:0 solid white">
          {@payload}
        </p>

        <p class="flex-1">
          <sensocto-sparkline-wasm-svelte
            height="20"
            is_loading="true"
            id={"sparkline_element-" <> assigns.id}
            sensor_id={@sensor_id}
            attribute_id={@attribute_id}
            samplingrate={@sampling_rate}
            timewindow="5000"
            timemode="relative"
            phx-update="ignore"
            class="resizeable loading w-full m-0 p-0"
            style="border:0 solid white"
          >
          </sensocto-sparkline-wasm-svelte>
        </p>
      </div>
    </div>
    """
  end
end

defmodule SensoctoWeb.Components.SensorTypes.GenericSensorComponent do
  import SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger

  def render(assigns) do
    import SensoctoWeb.Live.BaseComponents

    ~H"""
    <div class="attribute">
      {render_attribute_header(assigns)}
      {render_payload(assigns.sensor_data.payload, assigns)}
    </div>
    """
  end

  defp render_payload(payload, assigns) do
    if is_integer(payload) do
      ~H"<p>{payload}</p>"
    else
      try do
        case Jason.decode(payload) do
          {:ok, %{} = json_obj} ->
            # Render JSON object
            output =
              Enum.map(json_obj, fn {key, value} ->
                "#{String.capitalize(inspect(key))}: #{inspect(value)}\n"
              end)
              |> Enum.join("")

            ~H"<pre>{output}</pre>"

          # aaaa

          _ ->
            # Render single value
            ~H"<p>#{inspect(payload)}</p>"
        end
      rescue
        Jason.DecodeError ->
          Logger.debug("Could not decode payload: #{inspect(payload)}")
          ~H"<p>{inspect(payload)}</p>"

        _ ->
          Logger.error("Could not decode payload: #{inspect(payload)}")
          ~H"<p>{inspect(payload)}</p>"
      end
    end
  end
end
