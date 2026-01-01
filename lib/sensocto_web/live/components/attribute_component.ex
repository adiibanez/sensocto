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
      <span :if={@lastvalue} class="text-white flex items-center gap-1">
        <Heroicons.icon name="heart" type="solid" class="h-3 w-3 animate-pulse" />
        active
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
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
              href={"https://earth.google.com/web/@#{@lastvalue.payload.latitude},#{@lastvalue.payload.longitude},0a,1000d,35y,0h,0t,0r"}
              target="_blank"
              class="text-blue-400 hover:text-blue-300 flex items-center gap-1"
              title="Open in Google Earth"
            >
              <Heroicons.icon name="globe-alt" type="outline" class="h-3 w-3" />
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
          <div class="h-[150px]">
            <.svelte
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
              class="w-full h-full m-0 p-0"
            />
          </div>
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
      <.loading_spinner :if={is_nil(@lastvalue)} />
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
      <span class="text-white">{@attribute_id}</span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <span class="text-white text-[10px]">
          {Float.round(@battery_info.level, 0)}%
        </span>
        <meter
          id={"fuel_summary_#{@sensor_id}_#{@attribute_id}"}
          min="0"
          max="100"
          low="33"
          high="66"
          optimum="80"
          value={@battery_info.level}
          class="h-3 w-8"
        >
        </meter>
        <Heroicons.icon
          :if={@battery_info.charging != nil}
          name={if @battery_info.charging == "yes", do: "bolt", else: "bolt-slash"}
          type={if @battery_info.charging == "yes", do: "solid", else: "outline"}
          class={["h-3 w-3", if(@battery_info.charging == "yes", do: "text-yellow-400", else: "text-gray-500")]}
        />
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
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
      <.loading_spinner :if={is_nil(@lastvalue)} />
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

  # Summary mode for heartrate - shows pulsating heart with BPM (peak detection driven)
  @impl true
  def render(%{:attribute_type => "heartrate", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-white flex items-center gap-1">
        <.svelte
          name="HeartbeatVisualization"
          props={
            %{
              sensor_id: @sensor_id,
              attribute_id: @attribute_id,
              bpm: if(@lastvalue, do: @lastvalue.payload, else: 0),
              size: "small"
            }
          }
          socket={@socket}
        />
        {String.replace(to_string(@attribute_id), "_", " ")}
      </span>
      <span :if={@lastvalue} class="text-white font-mono flex items-center gap-1">
        {safe_round(@lastvalue.payload)} <span class="text-gray-400 text-[10px]">bpm</span>
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  # Normal/detailed mode for heartrate - larger pulsating heart with BPM display (peak detection driven)
  @impl true
  def render(%{:attribute_type => "heartrate"} = assigns) do
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

        <div :if={@lastvalue} class="flex items-center justify-center py-4">
          <div class="flex flex-col items-center gap-2">
            <.svelte
              name="HeartbeatVisualization"
              props={
                %{
                  sensor_id: @sensor_id,
                  attribute_id: @attribute_id,
                  bpm: @lastvalue.payload,
                  size: "large"
                }
              }
              socket={@socket}
            />
            <div class="text-center">
              <span class="text-3xl font-bold text-white">{safe_round(@lastvalue.payload)}</span>
              <span class="text-sm text-gray-400 ml-1">bpm</span>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  # Body sensor location - show human-readable location name
  # BLE Body Sensor Location characteristic (0x2A38) standard values
  @body_sensor_locations %{
    0 => "Other",
    1 => "Chest",
    2 => "Wrist",
    3 => "Finger",
    4 => "Hand",
    5 => "Ear Lobe",
    6 => "Foot"
  }

  @impl true
  def render(%{:attribute_type => "body_location", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="user" type="outline" class="h-3 w-3" />
        Location
      </span>
      <span :if={@lastvalue} class="text-white">
        {body_location_name(@lastvalue.payload)}
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "body_location"} = assigns) do
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
          attribute_name="Sensor Location"
          lastvalue={@lastvalue}
          socket={@socket}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center gap-2 py-2">
          <Heroicons.icon name="user" type="outline" class="h-5 w-5 text-blue-400" />
          <span class="text-lg text-white">{body_location_name(@lastvalue.payload)}</span>
        </div>
      </.container>
    </div>
    """
  end

  defp body_location_name(value) when is_integer(value) do
    Map.get(@body_sensor_locations, value, "Unknown (#{value})")
  end
  defp body_location_name(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> body_location_name(num)
      :error -> "Unknown"
    end
  end
  defp body_location_name(_), do: "Unknown"

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
      <.loading_spinner :if={is_nil(@lastvalue)} />
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

  @impl true
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

  # Helper to safely round payload values (handles both numbers and strings)
  defp safe_round(payload) when is_number(payload), do: round(payload)
  defp safe_round(payload) when is_binary(payload) do
    case Integer.parse(payload) do
      {num, _} -> num
      :error ->
        case Float.parse(payload) do
          {num, _} -> round(num)
          :error -> 0
        end
    end
  end
  defp safe_round(_), do: 0

  # Small inline loading spinner for summary mode
  defp loading_spinner(assigns) do
    ~H"""
    <span class="inline-flex items-center">
      <svg class="animate-spin h-3 w-3 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    </span>
    """
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
