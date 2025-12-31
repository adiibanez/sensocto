defmodule SensoctoWeb.Live.Components.AttributeComponent do
  @moduledoc """
  LiveComponent for rendering sensor attributes.

  Uses `Sensocto.Types.AttributeType` for render hints to determine
  the appropriate visualization for each attribute type. This provides
  a centralized, extensible way to add new attribute visualizations.

  ## Adding New Attribute Types

  To add a new attribute type visualization:
  1. Add the type to `Sensocto.Types.AttributeType.@attribute_types`
  2. Add render hints in `Sensocto.Types.AttributeType.render_hints/1`
  3. Create any needed Svelte component in `assets/svelte/`
  4. Optionally add a specific render clause here for complex layouts
  """

  import SensoctoWeb.Live.BaseComponents
  use Phoenix.LiveComponent
  require Logger
  import LiveSvelte

  alias Sensocto.Types.AttributeType

  attr :attribute_type, :string

  # Summary mode for ECG - show minimal indicator
  @impl true
  def render(%{:attribute_type => "ecg", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <span :if={@lastvalue} class="text-green-400 flex items-center gap-1">
        <Heroicons.icon name="heart" type="solid" class="h-3 w-3 animate-pulse" />
        active
      </span>
      <span :if={is_nil(@lastvalue)} class="text-gray-500">--</span>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "ecg"} = assigns) do
    Logger.debug("AttributeComponent ecg render")

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
          socket={@socket}
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
  def render(%{:attribute_type => "geolocation", :view_mode => :summary} = assigns) do
    Logger.debug("AttributeComponent geolocation summary render")

    ~H"""
    <div>
      <.container
        identifier={"cnt_#{@sensor_id}_#{@attribute_id}"}
        sensor_id={@sensor_id}
        attribute_id={@attribute_id}
        phx_hook="SensorDataAccumulator"
      >
        <div :if={is_nil(@lastvalue)} class="text-xs text-gray-400">No location</div>

        <div :if={@lastvalue} class="flex items-center justify-between text-xs">
          <span class="text-gray-400">
            {Float.round(@lastvalue.payload.latitude / 1, 3)}, {Float.round(@lastvalue.payload.longitude / 1, 3)}
          </span>
          <div class="flex items-center gap-2">
            <a
              href={"https://www.openstreetmap.org/?mlat=#{@lastvalue.payload.latitude}&mlon=#{@lastvalue.payload.longitude}&zoom=15"}
              target="_blank"
              class="text-blue-400 hover:text-blue-300 flex items-center gap-1"
              title="Open in OpenStreetMap"
            >
              <Heroicons.icon name="arrow-top-right-on-square" type="outline" class="h-3 w-3" />
            </a>
            <button
              class="text-blue-400 hover:text-blue-300"
              phx-click="show_map_modal"
              title="Show map"
            >
              <Heroicons.icon name="map" type="outline" class="h-4 w-4" />
            </button>
          </div>
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
          socket={@socket}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <p class="text-xs">
            Lat: {Float.round(@lastvalue.payload.latitude / 1, 3)}, Lon: {Float.round(@lastvalue.payload.longitude / 1, 3)}, {Float.round(@lastvalue.payload.accuracy / 1, 1)}m
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

  # Summary mode for IMU
  @impl true
  def render(%{:attribute_type => "imu", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <span :if={@lastvalue} class="text-blue-400">active</span>
      <span :if={is_nil(@lastvalue)} class="text-gray-500">--</span>
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
          socket={@socket}
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

  # Summary mode for battery
  @impl true
  def render(%{:attribute_type => "battery", :view_mode => :summary} = assigns) do
    assigns = assign(assigns, :battery_info, extract_battery_info(assigns[:lastvalue]))

    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <span class={[
          if(@battery_info.level < 20, do: "text-red-400", else: if(@battery_info.level < 50, do: "text-yellow-400", else: "text-green-400"))
        ]}>
          {Float.round(@battery_info.level, 0)}%
        </span>
        <Heroicons.icon
          :if={@battery_info.charging == "yes"}
          name="bolt"
          type="solid"
          class="h-3 w-3 text-yellow-400"
        />
      </div>
      <span :if={is_nil(@lastvalue)} class="text-gray-500">--</span>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "battery"} = assigns) do
    Logger.debug("AttributeComponent battery render #{inspect(assigns)}")

    # Extract battery level - handle both complex payload (%{level: x, charging: y}) and simple numeric payload
    assigns = assign(assigns, :battery_info, extract_battery_info(assigns[:lastvalue]))

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
          socket={@socket}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex">
          <span class="text-xs">{Float.round(@battery_info.level, 1)}%</span>
          <meter
            id={"fuel_#{@sensor_id}_#{@attribute_id}"}
            min="0"
            max="100"
            low="33"
            high="66"
            optimum="80"
            value={@battery_info.level}
          >
            at {Float.round(@battery_info.level, 1)}/100
          </meter>

          <Heroicons.icon
            :if={@battery_info.charging != nil}
            name={
              if @battery_info.charging == "yes" do
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

  # Extract battery level and charging status from various payload formats
  defp extract_battery_info(nil), do: %{level: 0.0, charging: nil}
  defp extract_battery_info(%{payload: %{level: level, charging: charging}}), do: %{level: level * 1.0, charging: charging}
  defp extract_battery_info(%{payload: %{level: level}}), do: %{level: level * 1.0, charging: nil}
  defp extract_battery_info(%{payload: level}) when is_number(level), do: %{level: level * 1.0, charging: nil}
  defp extract_battery_info(_), do: %{level: 0.0, charging: nil}

  # Summary mode for button
  @impl true
  def render(%{:attribute_type => "button", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      id={"vibrate_#{@sensor_id}_#{@attribute_id}"}
      phx-hook="Vibrate"
      data-value={@lastvalue && @lastvalue.payload}
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <div :if={@lastvalue} class="flex gap-0.5">
        <div class={["w-4 h-4 rounded text-center text-xs font-bold", if(@lastvalue.payload == 1, do: "bg-red-500 text-white", else: "bg-gray-600 text-gray-400")]}>1</div>
        <div class={["w-4 h-4 rounded text-center text-xs font-bold", if(@lastvalue.payload == 2, do: "bg-green-500 text-white", else: "bg-gray-600 text-gray-400")]}>2</div>
        <div class={["w-4 h-4 rounded text-center text-xs font-bold", if(@lastvalue.payload == 3, do: "bg-blue-500 text-white", else: "bg-gray-600 text-gray-400")]}>3</div>
      </div>
      <span :if={is_nil(@lastvalue)} class="text-gray-500">--</span>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "button"} = assigns) do
    Logger.debug("AttributeComponent button render #{inspect(assigns)}")

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
          socket={@socket}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="text-xs text-gray-400">No button pressed</div>

        <div
          :if={@lastvalue}
          class="flex gap-1 items-center"
          id={"vibrate_#{@sensor_id}_#{@attribute_id}"}
          phx-hook="Vibrate"
          data-value={@lastvalue.payload}
        >
          <div class="flex gap-1">
            <div class={[
              "w-6 h-6 rounded flex items-center justify-center text-xs font-bold",
              if(@lastvalue.payload == 1, do: "bg-red-500 text-white", else: "bg-gray-600 text-gray-400")
            ]}>
              1
            </div>
            <div class={[
              "w-6 h-6 rounded flex items-center justify-center text-xs font-bold",
              if(@lastvalue.payload == 2, do: "bg-green-500 text-white", else: "bg-gray-600 text-gray-400")
            ]}>
              2
            </div>
            <div class={[
              "w-6 h-6 rounded flex items-center justify-center text-xs font-bold",
              if(@lastvalue.payload == 3, do: "bg-blue-500 text-white", else: "bg-gray-600 text-gray-400")
            ]}>
              3
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  # Summary mode for default/generic attributes (sparkline types)
  @impl true
  def render(%{:view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <span :if={@lastvalue} class="text-white font-mono">
        {format_payload(@lastvalue.payload)}
      </span>
      <span :if={is_nil(@lastvalue)} class="text-gray-500">--</span>
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
          socket={@socket}
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
    # Handle partial updates (only lastvalue) vs full mount updates
    # When send_update is called with just id and lastvalue, we only update lastvalue
    if Map.has_key?(assigns, :attribute_id) do
      Logger.debug("attribute update (full) attribute_id: #{assigns.attribute_id}")

      # Get render hints from AttributeType for dynamic visualization selection
      attribute_type = assigns.attribute_type || "unknown"
      render_hints = AttributeType.render_hints(attribute_type)
      view_mode = Map.get(assigns, :view_mode, :normal)

      {
        :ok,
        socket
        |> assign_new(:id, fn _ -> assigns.id end)
        |> assign_new(:attribute_id, fn _ -> assigns.attribute_id end)
        |> assign_new(:attribute_type, fn _ -> attribute_type end)
        |> assign_new(:sensor_id, fn _ -> assigns.sensor_id end)
        |> assign_new(:attribute, fn _ -> assigns.attribute end)
        |> assign_new(:lastvalue, fn _ -> assigns.attribute.lastvalue end)
        |> assign_new(:render_hints, fn _ -> render_hints end)
        # measurements only contain lastvalue
        |> assign(:lastvalue, assigns.lastvalue)
        |> assign(:view_mode, view_mode)
      }
    else
      # Partial update - only update lastvalue (and view_mode if present)
      Logger.debug("attribute update (partial) id: #{assigns.id}")

      socket = assign(socket, :lastvalue, assigns.lastvalue)
      socket = if Map.has_key?(assigns, :view_mode), do: assign(socket, :view_mode, assigns.view_mode), else: socket
      {:ok, socket}
    end
  end

  # Helper to format payload values for summary display
  defp format_payload(payload) when is_number(payload) do
    if payload == trunc(payload) do
      Integer.to_string(trunc(payload))
    else
      :erlang.float_to_binary(payload * 1.0, decimals: 1)
    end
  end
  defp format_payload(payload) when is_map(payload), do: "..."
  defp format_payload(payload) when is_binary(payload), do: payload
  defp format_payload(_), do: "--"

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
