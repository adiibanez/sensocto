defmodule SensoctoWeb.Live.Components.AttributeComponent do
  alias SensoctoWeb.Live.BaseComponents
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent
  require Logger
  import BaseComponents
  import LiveSvelte

  # def update(assigns, socket) do
  #  Logger.debug("StatefulSensorLiveview.update")
  #  Logger.debug("assigns: #{inspect(assigns)}")
  #  {:ok, socket}
  # end

  attr :attribute_type, :string

  # battery: <meter id="fuel" min="0" max="100" low="33" high="66" optimum="80" value="50">at 50/100</meter>
  def render(%{:attribute_type => "ecg"} = assigns) do
    assigns =
      assign(assigns, :id, "cnt_#{assigns.sensor_id}_#{assigns.attribute.attribute_id}")

    # |> dbg()

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
        name="ECGVisualization"
        props={
          %{
            height: 20,
            id: @id,
            sensor_id: @sensor_id,
            attribute_id: @attribute.attribute_id,
            samplingrate: 50,
            timewindow: 10000,
            timemode: "relative",
            minvalue: 0,
            maxvalue: 0,
            height: 100,
            color: "#ffc107",
            class: "loading w-full m-0 p-0 resizeable"
          }
        }
        socket={@socket}
        class="loading w-full m-0 p-0"
      />
    </div>
    """
  end

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
    </div>
    """
  end

  def update(assigns, socket) do
    Logger.debug("attribute update #{inspect(assigns)}")

    send(self(), :attributes_loaded)

    # assigns.attribute |> dbg()

    # attribute_type =
    #   case Map.has_key?(assigns, :attribute_type) do
    #     true -> assigns.attribute_type
    #     false -> socket.assigns.attribute_type
    #   end

    # sensor_id =
    #   case Map.has_key?(assigns, :sensor_id) do
    #     true -> assigns.sensor_id
    #     false -> socket.assigns.sensor_id
    #   end

    {
      :ok,
      socket
      |> assign_new(:attribute_type, fn _ -> assigns.attribute_type end)
      |> assign_new(:sensor_id, fn _ -> assigns.sensor_id end)
      |> assign(:attribute, assigns.attribute)
      # |> assign(:attribute_type, attribute_type)
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
