defmodule SensoctoWeb.Live.Components.AttributeComponent do
  alias SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger
  import BaseComponents
  import LiveSvelte

  # battery: <meter id="fuel" min="0" max="100" low="33" high="66" optimum="80" value="50">at 50/100</meter>

  def render(assigns) do
    ~H"""
    <div
      id={"cnt_#{@sensor_id}_#{@attribute.attribute_id}"}
      class="attribute"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute.attribute_id}
      data-sensor_type={@attribute.attribute_id}
      phx-hook="SensorDataAccumulator"
    >
      <.render_attribute_header
        sensor_id={@sensor_id}
        attribute_id={@attribute.attribute_id}
        attribute_name={@attribute.attribute_id}
      >
      </.render_attribute_header>
      
    <!--<p>AttributeComponent pid: {inspect(self())}</p>
      <p>
        Attribute: {@attribute.attribute_id} Timestamp: {@attribute.timestamp} Payload: {@attribute.payload}
      </p>-->

    <!--<sensocto-ecg-Visualization
        id={"viz_#{assigns.sensor_id}_#{@attribute.attribute_id}"}
        is_loading="true"
        sensor_id={@sensor_id}
        attribute_id={@attribute.attribute_id}
        samplingrate="10"
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
      </sensocto-ecg-Visualization>-->

      <.svelte
        name="SparklineWasm"
        props={
          %{
            height: 20,
            id: "cnt_#{@sensor_id}_#{@attribute.attribute_id}",
            sensor_id: @sensor_id,
            attribute_id: @attribute.attribute_id,
            samplingrate: 1,
            timewindow: 10000,
            timemode: "relative",
            minvalue: 0,
            maxvalue: 0
          }
        }
        socket={@socket}
        class="loading w-full m-0 p-0"
      />
      
    <!--<sensocto-sparkline-wasm-svelte
        height="20"
        id={"viz_#{assigns.sensor_id}_#{@attribute.attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute.attribute_id}
        samplingrate="1"
        timewindow="10000"
        timemode="relative"
        phx-update="ignore"
        minvalue="0"
        maxvalue="0"
        class="resizeable loading w-full m-0 p-0"
      >
      </sensocto-sparkline-wasm-svelte>-->
    </div>
    """
  end

  def update(assigns, socket) do
    Logger.debug("attribute update #{inspect(assigns)}")
    # user = Repo.get!(User, assigns.id)

    send(self(), :attributes_loaded)

    {
      :ok,
      socket
      |> assign(:attribute, assigns.attribute)
      |> assign(:sensor_id, assigns.sensor_id)
      #  |> assign(:timestamp, assigns.attribute[:timestamp])
      #  |> assign(:payload, assigns.attribute[:payload])
    }
  end

  # def update_many(assigns_sockets) do
  #   Logger.info("attribute #{inspect(assigns_sockets)} update_many")
  #   # list_of_ids = Enum.map(assigns_sockets, fn {assigns, _socket} -> assigns.id end)

  #   # users =
  #   #   from(u in User, where: u.id in ^list_of_ids, select: {u.id, u})
  #   #   |> Repo.all()
  #   #   |> Map.new()

  #   # Enum.map(assigns_sockets, fn {assigns, socket} ->
  #   #   assign(socket, :user, users[assigns.id])
  #   # end)
  #   {:ok, assigns_sockets}
  # end
end
