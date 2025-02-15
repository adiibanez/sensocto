defmodule SensoctoWeb.Live.Components.AttributeComponent do
  import SensoctoWeb.Live.BaseComponents
  use Phoenix.LiveComponent
  require Logger
  import LiveSvelte

  attr :attribute_type, :string

  def render(%{:attribute_type => "ecg"} = assigns) do
    Logger.debug("AttributeComponent ecg render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_metadata.attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_metadata.attribute_id}
          attribute_name={@attribute_metadata.attribute_id}
          timestamp={@attribute_data.timestamp}
        >
        </.render_attribute_header>

        <.svelte
          name="ECGVisualization"
          props={
            %{
              id: "cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}",
              sensor_id: @sensor_id,
              attribute_id: @attribute_metadata.attribute_id,
              samplingrate: @attribute_metadata.sampling_rate,
              timewindow: 10000,
              timemode: "relative",
              minvalue: 0,
              maxvalue: 0,
              height: 70,
              color: "#ffc107",
              class: "w-full m-0 p-0 resizeable"
            }
          }
          socket={@socket}
          class="w-full m-0 p-0"
        />
      </.container>
    </div>
    """
  end

  def render(%{:attribute_type => "geolocation"} = assigns) do
    Logger.debug("AttributeComponent geolocation render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_metadata.attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_metadata.attribute_id}
          attribute_name={@attribute_metadata.attribute_id}
          timestamp={@attribute_data.timestamp}
        >
        </.render_attribute_header>

        <p class="text-xs">
          Lat: {@attribute_data.payload.latitude}, Lon: {@attribute_data.payload.longitude}, {@attribute_data.payload.accuracy}m
        </p>
        <.svelte
          name="Map"
          props={
            %{
              position: %{
                lat: @attribute_data.payload.latitude,
                lng: @attribute_data.payload.longitude
              }
            }
          }
          socket={@socket}
          class="w-full m-0 p-0"
        />
      </.container>
    </div>
    """
  end

  def render(%{:attribute_type => "battery"} = assigns) do
    Logger.debug("AttributeComponent battery render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_metadata.attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_metadata.attribute_id}
          attribute_name={@attribute_metadata.attribute_id}
          timestamp={@attribute_data.timestamp}
        >
        </.render_attribute_header>

        <div class="flex">
          <span class="text-xs">{@attribute_data.payload.level}%</span>
          <meter
            id="fuel"
            min="0"
            max="100"
            low="33"
            high="66"
            optimum="80"
            value={@attribute_data.payload.level}
          >
            at {@attribute_data.payload.level}/100
          </meter>

          <Heroicons.icon
            name={
              if @attribute_data.payload.charging == "yes" do
                "bolt"
              else
                "bolt-slash"
              end
            }
            type="outline"
            class="h-4 w-4"
          />
        </div>
      </.container>
    </div>
    """
  end

  def render(assigns) do
    Logger.debug("AttributeComponent default render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_metadata.attribute_id}
        phx_hook="SensorDataAccumulator"
        attribute_metadata={@attribute_metadata}
        attribute_data={@attribute_data}
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_metadata.attribute_id}
          attribute_name={@attribute_metadata.attribute_id}
          timestamp={@attribute_data.timestamp}
        >
        </.render_attribute_header>

        <.svelte
          name="SparklineWasm"
          props={
            %{
              height: 20,
              id: "cnt_#{@sensor_id}_#{@attribute_metadata.attribute_id}",
              sensor_id: @sensor_id,
              attribute_id: @attribute_metadata.attribute_id,
              samplingrate: @attribute_metadata.sampling_rate,
              timewindow: 10000,
              timemode: "relative",
              minvalue: 0,
              maxvalue: 0
            }
          }
          socket={@socket}
          class="w-full m-0 p-0"
        />
      </.container>
    </div>
    """
  end

  def update(assigns, socket) do
    Logger.debug("attribute update attribute_data: #{inspect(assigns.attribute_data)}")

    {
      :ok,
      socket
      |> assign_new(:id, fn _ -> assigns.id end)
      |> assign_new(:attribute_type, fn _ -> assigns.attribute_type end)
      |> assign_new(:attribute_metadata, fn _ -> assigns.attribute_metadata end)
      |> assign_new(:sensor_id, fn _ -> assigns.sensor_id end)
      |> assign_new(:attribute_data, fn _ -> assigns.attribute_data end)
      |> assign(:attribute_data, assigns.attribute_data)
      # |> assign(:attribute_type, attribute_type)
    }
  end

  defp container(assigns) do
    assigns =
      assigns
      |> assign(:class, Map.get(assigns, :class, "attribute"))
      |> assign(:rest, Map.get(assigns, :rest, []))
      |> assign(:phx_hook, Map.get(assigns, :phx_hook, "Test"))

    ~H"""
    <div
      id={@identifier}
      class={@class}
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
      phx-hook={@phx_hook}
      {@rest}
    >
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
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
