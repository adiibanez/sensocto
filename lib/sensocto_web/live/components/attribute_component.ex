defmodule SensoctoWeb.Live.Components.AttributeComponent do
  import SensoctoWeb.Live.BaseComponents
  use Phoenix.LiveComponent
  require Logger
  import LiveSvelte

  attr :attribute_type, :string

  @impl true
  def render(%{:attribute_type => "ecg"} = assigns) do
    Logger.debug("AttributeComponent ecg render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_id}
          attribute_name={@attribute_id}
          lastvalue={@lastvalue}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <.svelte
            name="ECGVisualization"
            props={
              %{
                id: "cnt_#{@sensor_id}_#{@attribute_id}",
                sensor_id: @sensor_id,
                attribute_id: @attribute.attribute_id,
                samplingrate: @attribute.sampling_rate,
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
        </div>
      </.container>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "geolocation"} = assigns) do
    Logger.debug("AttributeComponent geolocation render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_id}
          attribute_name={@attribute_id}
          lastvalue={@lastvalue}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <p class="text-xs">
            Lat: {@lastvalue.payload.latitude}, Lon: {@lastvalue.payload.longitude}, {@lastvalue.payload.accuracy}m
          </p>
          <.svelte
            phx-update="ignore"
            name="Map"
            props={
              %{
                identifier: "map_#{@sensor_id}_#{@attribute_id}",
                position: %{
                  lat: @lastvalue.payload.latitude,
                  lng: @lastvalue.payload.longitude,
                  accuracy: @lastvalue.payload.accuracy
                }
              }
            }
            socket={@socket}
            class="w-full m-0 p-0"
          />
        </div>
      </.container>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "imu"} = assigns) do
    Logger.debug("AttributeComponent imu render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_id}
          attribute_name={@attribute_id}
          lastvalue={@lastvalue}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <p class="text-xs">
            imuData: {@lastvalue.payload}
          </p>
          <.svelte
            name="IMU"
            props={
              %{
                imuData: @lastvalue.payload
              }
            }
            socket={@socket}
            class="w-full m-0 p-0"
          />
        </div>
      </.container>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "battery"} = assigns) do
    Logger.debug("AttributeComponent battery render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_id}
          attribute_name={@attribute_id}
          lastvalue={@lastvalue}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex">
          <span class="text-xs">{@lastvalue.payload.level}%</span>
          <meter
            id={"fuel_#{@sensor_id}_#{@attribute_id}"}
            min="0"
            max="100"
            low="33"
            high="66"
            optimum="80"
            value={@lastvalue.payload.level}
          >
            at {@lastvalue.payload.level}/100
          </meter>

          <Heroicons.icon
            name={
              if @lastvalue.payload.charging == "yes" do
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

  @impl true
  def render(assigns) do
    Logger.debug("AttributeComponent default render #{inspect(assigns)}")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
        attribute={@attribute}
      >
        <.render_attribute_header
          sensor_id={@sensor_id}
          attribute_id={@attribute_id}
          attribute_name={@attribute_id}
          lastvalue={@lastvalue}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <.svelte
            name="SparklineWasm"
            props={
              %{
                height: 20,
                id: "cnt_#{@sensor_id}_#{@attribute_id}",
                sensor_id: @sensor_id,
                attribute_id: @attribute.attribute_id,
                samplingrate: @attribute.sampling_rate,
                timewindow: 10000,
                timemode: "relative",
                minvalue: 0,
                maxvalue: 0
              }
            }
            socket={@socket}
            class="w-full m-0 p-0"
          />
        </div>
      </.container>
      <!--<div>{inspect(@lastvalue)}</div>-->
    </div>
    """
  end

  def update(assigns, socket) do
    Logger.debug("attribute update attribute: #{inspect(assigns)}")

    {
      :ok,
      socket
      |> assign_new(:id, fn _ -> assigns.id end)
      |> assign_new(:attribute_id, fn _ -> assigns.attribute_id end)
      |> assign_new(:attribute_type, fn _ -> assigns.attribute_type end)
      |> assign_new(:sensor_id, fn _ -> assigns.sensor_id end)
      |> assign_new(:attribute, fn _ -> assigns.attribute end)
      |> assign_new(:lastvalue, fn _ -> assigns.attribute.lastvalue end)
      # measurements only contain lastvalue
      |> assign(:lastvalue, assigns.lastvalue)
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
