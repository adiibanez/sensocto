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

  # Summary mode for ECG - show mini inline sparkline
  @impl true
  def render(%{:attribute_type => "ecg", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      id={"cnt_summary_#{@sensor_id}_#{@attribute_id}"}
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
      phx-hook="SensorDataAccumulator"
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="heart" type="solid" class="h-3 w-3 text-red-400" />
        {String.replace(to_string(@attribute_id), "_", " ")}
      </span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <.svelte
          name="MiniECGSparkline"
          props={
            %{
              id: "cnt_summary_#{@sensor_id}_#{@attribute_id}",
              sensor_id: @sensor_id,
              attribute_id: @attribute.attribute_id,
              samplingrate: @attribute.sampling_rate,
              timewindow: 3000,
              width: 60,
              height: 16,
              color: "#22c55e",
              showBackpressure: true,
              attentionLevel: "medium",
              batchWindow: 500
            }
          }
          socket={@socket}
        />
      </div>
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

  # Summary mode for IMU - shows tilt visualization, acceleration, and compass
  @impl true
  def render(%{:attribute_type => "imu", :view_mode => :summary} = assigns) do
    assigns = assign(assigns, :imu_data, parse_imu_payload(assigns[:lastvalue]))

    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="device-phone-mobile" type="outline" class="h-3 w-3 text-indigo-400" style={"transform: rotate(#{@imu_data.tilt_display}deg)"} />
        IMU
      </span>
      <div :if={@lastvalue} class="flex items-center gap-2">
        <%!-- Acceleration magnitude bar --%>
        <div class="flex items-center gap-1" title={"Acceleration: #{Float.round(@imu_data.accel_magnitude, 1)} m/s²"}>
          <div class="w-8 h-2 bg-gray-700 rounded-full overflow-hidden">
            <div class={"h-full rounded-full #{accel_color(@imu_data.accel_magnitude)}"} style={"width: #{min(100, @imu_data.accel_magnitude * 10)}%"}></div>
          </div>
        </div>
        <%!-- Tilt indicator (pitch/roll visualization) --%>
        <div class="relative w-5 h-5 rounded-full border border-gray-600 bg-gray-800" title={"Pitch: #{round(@imu_data.pitch)}° Roll: #{round(@imu_data.roll)}°"}>
          <div
            class="absolute w-2 h-2 bg-indigo-400 rounded-full"
            style={"top: 50%; left: 50%; transform: translate(#{@imu_data.roll_display}%, #{@imu_data.pitch_display}%) translate(-50%, -50%)"}
          />
        </div>
        <%!-- Compass direction --%>
        <div class="flex items-center gap-0.5" title={"Heading: #{round(@imu_data.heading)}°"}>
          <Heroicons.icon name="arrow-up" type="solid" class="h-3 w-3 text-cyan-400" style={"transform: rotate(#{@imu_data.heading}deg)"} />
          <span class="text-cyan-400 text-[10px] w-4">{heading_to_dir(@imu_data.heading)}</span>
        </div>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "imu"} = assigns) do
    Logger.debug("AttributeComponent imu render #{inspect(assigns)}")
    assigns = assign(assigns, :imu_data, parse_imu_payload(assigns[:lastvalue]))

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

        <div :if={@lastvalue} class="py-2">
          <%!-- Main visualization row: Tilt sphere, Compass, Acceleration --%>
          <div class="flex items-center justify-around gap-4 mb-3">
            <%!-- Tilt/Inclination sphere --%>
            <div class="flex flex-col items-center">
              <div class="relative w-16 h-16 rounded-full border-2 border-gray-600 bg-gray-800 overflow-hidden">
                <%!-- Cross hairs --%>
                <div class="absolute top-1/2 left-0 w-full h-px bg-gray-700"></div>
                <div class="absolute left-1/2 top-0 h-full w-px bg-gray-700"></div>
                <%!-- Tilt indicator ball --%>
                <div
                  class="absolute w-4 h-4 bg-indigo-500 rounded-full shadow-lg"
                  style={"top: 50%; left: 50%; transform: translate(#{@imu_data.roll_display * 0.7}%, #{@imu_data.pitch_display * 0.7}%) translate(-50%, -50%)"}
                />
              </div>
              <span class="text-[10px] text-gray-500 mt-1">Tilt</span>
            </div>

            <%!-- Compass --%>
            <div class="flex flex-col items-center">
              <div class="relative w-16 h-16">
                <div class="absolute inset-0 rounded-full border-2 border-gray-600">
                  <span class="absolute top-0.5 left-1/2 -translate-x-1/2 text-[10px] text-gray-400">N</span>
                  <span class="absolute bottom-0.5 left-1/2 -translate-x-1/2 text-[10px] text-gray-400">S</span>
                  <span class="absolute left-0.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400">W</span>
                  <span class="absolute right-0.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400">E</span>
                </div>
                <Heroicons.icon
                  name="arrow-up"
                  type="solid"
                  class="absolute top-1/2 left-1/2 w-6 h-6 text-cyan-400"
                  style={"transform: translate(-50%, -50%) rotate(#{@imu_data.heading}deg)"}
                />
              </div>
              <span class="text-[10px] text-gray-500 mt-1">{round(@imu_data.heading)}° {heading_to_dir(@imu_data.heading)}</span>
            </div>

            <%!-- Acceleration magnitude --%>
            <div class="flex flex-col items-center">
              <div class="relative w-16 h-16 flex items-center justify-center">
                <div class={"text-2xl font-bold #{accel_color(@imu_data.accel_magnitude)}"}>
                  {Float.round(@imu_data.accel_magnitude, 1)}
                </div>
                <span class="text-[10px] text-gray-500 absolute bottom-0">m/s²</span>
              </div>
              <span class="text-[10px] text-gray-500 mt-1">Accel</span>
            </div>
          </div>

          <%!-- Detailed values grid --%>
          <div class="grid grid-cols-3 gap-2 text-xs">
            <%!-- Pitch --%>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-red-400 text-[10px]">Pitch</div>
              <div class="text-white font-mono">{Float.round(@imu_data.pitch, 1)}°</div>
            </div>
            <%!-- Roll --%>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-green-400 text-[10px]">Roll</div>
              <div class="text-white font-mono">{Float.round(@imu_data.roll, 1)}°</div>
            </div>
            <%!-- Yaw --%>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-blue-400 text-[10px]">Yaw</div>
              <div class="text-white font-mono">{Float.round(@imu_data.yaw, 1)}°</div>
            </div>
          </div>

          <%!-- Acceleration components --%>
          <div class="grid grid-cols-3 gap-2 text-xs mt-2">
            <div class="bg-gray-800/50 rounded p-1.5 text-center">
              <div class="text-gray-500 text-[10px]">Ax</div>
              <div class="text-white font-mono text-[11px]">{Float.round(@imu_data.ax, 2)}</div>
            </div>
            <div class="bg-gray-800/50 rounded p-1.5 text-center">
              <div class="text-gray-500 text-[10px]">Ay</div>
              <div class="text-white font-mono text-[11px]">{Float.round(@imu_data.ay, 2)}</div>
            </div>
            <div class="bg-gray-800/50 rounded p-1.5 text-center">
              <div class="text-gray-500 text-[10px]">Az</div>
              <div class="text-white font-mono text-[11px]">{Float.round(@imu_data.az, 2)}</div>
            </div>
          </div>
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
          class={["h-3 w-3", if(@battery_info.charging == "yes", do: "text-white", else: "text-gray-400")]}
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

  # Summary mode for rich_presence - shows current media with artwork
  @impl true
  def render(%{:attribute_type => "rich_presence", :view_mode => :summary} = assigns) do
    assigns = assign(assigns, :presence, extract_rich_presence(assigns[:lastvalue]))

    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <%= case @presence.state do %>
          <% "playing" -> %>
            <Heroicons.icon name="play" type="solid" class="h-3 w-3 text-green-400" />
          <% "paused" -> %>
            <Heroicons.icon name="pause" type="solid" class="h-3 w-3 text-yellow-400" />
          <% _ -> %>
            <Heroicons.icon name="musical-note" type="outline" class="h-3 w-3 text-gray-500" />
        <% end %>
        Media
      </span>
      <div :if={@lastvalue} class="flex items-center gap-2 max-w-[180px]">
        <%= if @presence.title do %>
          <%= if @presence.state == "playing" do %>
            <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse flex-shrink-0"></span>
          <% else %>
            <span class="w-2 h-2 bg-yellow-400 rounded-full flex-shrink-0"></span>
          <% end %>
          <div class="truncate text-right">
            <span class="text-white text-[10px]">{@presence.title}</span>
            <%= if @presence.artist do %>
              <span class="text-gray-400 text-[10px]"> - {@presence.artist}</span>
            <% end %>
          </div>
        <% else %>
          <span class="text-gray-500 text-[10px] italic">Play media in browser</span>
        <% end %>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  # Detailed mode for rich_presence - shows album art and full info
  @impl true
  def render(%{:attribute_type => "rich_presence"} = assigns) do
    assigns = assign(assigns, :presence, extract_rich_presence(assigns[:lastvalue]))

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
          attribute_name="Rich Presence"
          lastvalue={@lastvalue}
          socket={@socket}
        >
        </.render_attribute_header>

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-start gap-3 p-2">
          <%!-- Album artwork or placeholder --%>
          <div class="w-12 h-12 rounded bg-gray-700 flex-shrink-0 overflow-hidden">
            <%= if @presence.artwork_url && @presence.artwork_url != "" do %>
              <img src={@presence.artwork_url} alt="Album art" class="w-full h-full object-cover" />
            <% else %>
              <div class="w-full h-full flex items-center justify-center">
                <Heroicons.icon name="musical-note" type="solid" class="h-6 w-6 text-gray-500" />
              </div>
            <% end %>
          </div>

          <%!-- Media info --%>
          <div class="flex-1 min-w-0">
            <%= if @presence.title do %>
              <p class="text-sm font-medium text-white truncate">{@presence.title}</p>
              <p :if={@presence.artist} class="text-xs text-gray-400 truncate">{@presence.artist}</p>
              <p :if={@presence.album} class="text-xs text-gray-500 truncate">{@presence.album}</p>
            <% else %>
              <p class="text-sm text-gray-500">No media playing</p>
            <% end %>

            <%!-- Playback state indicator --%>
            <div class="mt-1 flex items-center gap-1">
              <%= case @presence.state do %>
                <% "playing" -> %>
                  <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                  <span class="text-xs text-green-400">Playing</span>
                <% "paused" -> %>
                  <span class="w-2 h-2 bg-yellow-400 rounded-full"></span>
                  <span class="text-xs text-yellow-400">Paused</span>
                <% _ -> %>
                  <span class="w-2 h-2 bg-gray-500 rounded-full"></span>
                  <span class="text-xs text-gray-500">Idle</span>
              <% end %>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  # Extract rich presence data from payload
  defp extract_rich_presence(nil), do: %{title: nil, artist: nil, album: nil, artwork_url: nil, state: "none"}
  defp extract_rich_presence(%{payload: %{title: title, artist: artist, album: album, artwork_url: artwork, state: state}}) do
    %{
      title: if(title == "", do: nil, else: title),
      artist: if(artist == "", do: nil, else: artist),
      album: if(album == "", do: nil, else: album),
      artwork_url: artwork,
      state: state || "none"
    }
  end
  defp extract_rich_presence(%{payload: payload}) when is_map(payload) do
    %{
      title: Map.get(payload, :title) || Map.get(payload, "title"),
      artist: Map.get(payload, :artist) || Map.get(payload, "artist"),
      album: Map.get(payload, :album) || Map.get(payload, "album"),
      artwork_url: Map.get(payload, :artwork_url) || Map.get(payload, "artwork_url"),
      state: Map.get(payload, :state) || Map.get(payload, "state") || "none"
    }
  end
  defp extract_rich_presence(_), do: %{title: nil, artist: nil, album: nil, artwork_url: nil, state: "none"}

  # Button colors for 8 buttons (hex values for inline styles)
  @button_colors %{
    1 => "#ef4444",  # red
    2 => "#f97316",  # orange
    3 => "#eab308",  # yellow
    4 => "#22c55e",  # green
    5 => "#14b8a6",  # teal
    6 => "#3b82f6",  # blue
    7 => "#6366f1",  # indigo
    8 => "#a855f7"   # purple
  }

  defp button_style(payload, button_id) do
    if payload == button_id do
      "background-color: #{@button_colors[button_id]}; color: white;"
    else
      "background-color: #4b5563; color: #9ca3af;"
    end
  end

  # Button style for multi-press support using MapSet
  defp button_style_multi(pressed_buttons, button_id) do
    if MapSet.member?(pressed_buttons, button_id) do
      "background-color: #{@button_colors[button_id]}; color: white;"
    else
      "background-color: #4b5563; color: #9ca3af;"
    end
  end

  # Summary mode for button - 8 colored buttons with vibrate feedback and multi-press support
  @impl true
  def render(%{:attribute_type => "button", :view_mode => :summary} = assigns) do
    # Get pressed buttons from assigns or compute from lastvalue
    pressed_buttons = Map.get(assigns, :pressed_buttons, MapSet.new())

    assigns = assign(assigns, :pressed_buttons, pressed_buttons)

    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      id={"vibrate_#{@sensor_id}_#{@attribute_id}"}
      phx-hook="Vibrate"
      data-value={@lastvalue && @lastvalue.payload}
      data-event={@lastvalue && @lastvalue[:event]}
      data-timestamp={@lastvalue && (@lastvalue[:timestamp] || @lastvalue[:received_at] || System.system_time(:millisecond))}
    >
      <span class="text-gray-400">{@attribute_id}</span>
      <div class="flex gap-0.5">
        <%= for btn_id <- 1..8 do %>
          <div
            class={"w-4 h-4 rounded text-center text-[10px] font-bold flex items-center justify-center transition-all duration-100 #{if MapSet.member?(@pressed_buttons, btn_id), do: "scale-90", else: ""}"}
            style={button_style_multi(@pressed_buttons, btn_id)}
          >
            {btn_id}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "button"} = assigns) do
    Logger.debug("AttributeComponent button render #{inspect(assigns)}")

    # Get pressed buttons from assigns or initialize empty
    pressed_buttons = Map.get(assigns, :pressed_buttons, MapSet.new())

    assigns = assign(assigns, :pressed_buttons, pressed_buttons)

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

        <div :if={is_nil(@lastvalue) and MapSet.size(@pressed_buttons) == 0} class="text-xs text-gray-400">No button pressed</div>

        <div
          class="flex gap-1 items-center"
          id={"vibrate_#{@sensor_id}_#{@attribute_id}"}
          phx-hook="Vibrate"
          data-value={@lastvalue && @lastvalue.payload}
          data-event={@lastvalue && @lastvalue[:event]}
          data-timestamp={@lastvalue && (@lastvalue[:timestamp] || @lastvalue[:received_at] || System.system_time(:millisecond))}
        >
          <div class="flex gap-1 flex-wrap">
            <%= for btn_id <- 1..8 do %>
              <div
                class={"w-6 h-6 rounded flex items-center justify-center text-xs font-bold transition-all duration-100 #{if MapSet.member?(@pressed_buttons, btn_id), do: "scale-90", else: ""}"}
                style={button_style_multi(@pressed_buttons, btn_id)}
              >
                {btn_id}
              </div>
            <% end %>
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

  # ============================================================================
  # TEMPERATURE - Thermometer gauge with color gradient
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "temperature", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="fire" type="outline" class="h-3 w-3 text-orange-400" />
        Temp
      </span>
      <span :if={@lastvalue} class="text-white font-mono flex items-center gap-1">
        {format_temperature(@lastvalue.payload)} <span class="text-gray-400 text-[10px]">°C</span>
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "temperature"} = assigns) do
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
          attribute_name="Temperature"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center gap-4 py-2">
          <div class="flex items-center gap-2">
            <div class={["w-3 h-12 rounded-full", temperature_gradient_class(@lastvalue.payload)]}></div>
            <div class="text-center">
              <span class="text-2xl font-bold text-white">{format_temperature(@lastvalue.payload)}</span>
              <span class="text-sm text-gray-400 ml-1">°C</span>
            </div>
          </div>
          <div class="text-xs text-gray-500">
            {temperature_comfort_label(@lastvalue.payload)}
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_temperature(%{value: value}) when is_number(value), do: Float.round(value * 1.0, 1)
  defp format_temperature(value) when is_number(value), do: Float.round(value * 1.0, 1)
  defp format_temperature(_), do: "--"

  defp temperature_gradient_class(%{value: value}) when is_number(value), do: temperature_gradient_class(value)
  defp temperature_gradient_class(value) when is_number(value) do
    cond do
      value < 10 -> "bg-gradient-to-t from-blue-600 to-blue-400"
      value < 18 -> "bg-gradient-to-t from-cyan-500 to-cyan-300"
      value < 24 -> "bg-gradient-to-t from-green-500 to-green-300"
      value < 30 -> "bg-gradient-to-t from-yellow-500 to-orange-400"
      true -> "bg-gradient-to-t from-red-600 to-red-400"
    end
  end
  defp temperature_gradient_class(_), do: "bg-gray-600"

  defp temperature_comfort_label(%{value: value}) when is_number(value), do: temperature_comfort_label(value)
  defp temperature_comfort_label(value) when is_number(value) do
    cond do
      value < 10 -> "Cold"
      value < 18 -> "Cool"
      value < 24 -> "Comfortable"
      value < 30 -> "Warm"
      true -> "Hot"
    end
  end
  defp temperature_comfort_label(_), do: ""

  # ============================================================================
  # HUMIDITY - Water drop gauge
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "humidity", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <svg class="h-3 w-3 text-blue-400" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z" />
        </svg>
        Humidity
      </span>
      <span :if={@lastvalue} class="text-white font-mono flex items-center gap-1">
        {format_humidity(@lastvalue.payload)} <span class="text-gray-400 text-[10px]">%</span>
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "humidity"} = assigns) do
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
          attribute_name="Humidity"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center gap-4 py-2">
          <div class="relative w-16 h-16">
            <svg class="w-full h-full text-blue-500" viewBox="0 0 24 24" fill="currentColor" style={"opacity: #{humidity_opacity(@lastvalue.payload)}"}>
              <path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z" />
            </svg>
            <div class="absolute inset-0 flex items-center justify-center">
              <span class="text-xs font-bold text-white">{format_humidity(@lastvalue.payload)}%</span>
            </div>
          </div>
          <div class="text-xs text-gray-500">
            {humidity_comfort_label(@lastvalue.payload)}
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_humidity(%{value: value}) when is_number(value), do: round(value)
  defp format_humidity(value) when is_number(value), do: round(value)
  defp format_humidity(_), do: "--"

  defp humidity_opacity(%{value: value}) when is_number(value), do: humidity_opacity(value)
  defp humidity_opacity(value) when is_number(value), do: max(0.3, min(1.0, value / 100))
  defp humidity_opacity(_), do: 0.5

  defp humidity_comfort_label(%{value: value}) when is_number(value), do: humidity_comfort_label(value)
  defp humidity_comfort_label(value) when is_number(value) do
    cond do
      value < 30 -> "Dry"
      value < 50 -> "Comfortable"
      value < 70 -> "Humid"
      true -> "Very Humid"
    end
  end
  defp humidity_comfort_label(_), do: ""

  # ============================================================================
  # PRESSURE - Barometric pressure gauge
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "pressure", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="arrow-down-on-square" type="outline" class="h-3 w-3 text-purple-400" />
        Pressure
      </span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <.svelte
          name="MiniPressureSparkline"
          props={
            %{
              id: "cnt_summary_#{@sensor_id}_#{@attribute_id}",
              sensor_id: @sensor_id,
              attribute_id: @attribute.attribute_id,
              samplingrate: @attribute.sampling_rate,
              timewindow: 60000,
              width: 60,
              height: 16,
              color: "#8b5cf6",
              showBackpressure: true,
              attentionLevel: "medium",
              batchWindow: 500
            }
          }
          socket={@socket}
        />
        <span class="text-white font-mono text-[11px]">
          {format_pressure(@lastvalue.payload)} <span class="text-gray-400 text-[10px]">hPa</span>
        </span>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "pressure"} = assigns) do
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
          attribute_name="Pressure"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue}>
          <div class="flex items-center gap-4 py-2 mb-2">
            <div class="text-center">
              <span class="text-2xl font-bold text-white">{format_pressure(@lastvalue.payload)}</span>
              <span class="text-sm text-gray-400 ml-1">hPa</span>
            </div>
            <div class="text-xs text-gray-500 flex flex-col">
              <span>{pressure_weather_indicator(@lastvalue.payload)}</span>
              <span class="text-gray-600">≈ {pressure_to_altitude(@lastvalue.payload)}m ASL</span>
            </div>
          </div>
          <.svelte
            name="PressureVisualization"
            props={
              %{
                id: "cnt_#{@sensor_id}_#{@attribute_id}",
                sensor_id: @sensor_id,
                attribute_id: @attribute.attribute_id,
                samplingrate: @attribute.sampling_rate,
                timewindow: 60,
                width: 300,
                height: 100,
                color: "#8b5cf6",
                backgroundColor: "transparent",
                minValue: 950,
                maxValue: 1050
              }
            }
            socket={@socket}
          />
        </div>
      </.container>
    </div>
    """
  end

  defp format_pressure(%{value: value}) when is_number(value), do: Float.round(value * 1.0, 1)
  defp format_pressure(value) when is_number(value), do: Float.round(value * 1.0, 1)
  defp format_pressure(_), do: "--"

  defp pressure_weather_indicator(%{value: value}) when is_number(value), do: pressure_weather_indicator(value)
  defp pressure_weather_indicator(value) when is_number(value) do
    cond do
      value < 1000 -> "Low pressure - stormy"
      value < 1013 -> "Below average"
      value < 1020 -> "Normal"
      true -> "High pressure - fair"
    end
  end
  defp pressure_weather_indicator(_), do: ""

  defp pressure_to_altitude(%{value: value}) when is_number(value), do: pressure_to_altitude(value)
  defp pressure_to_altitude(value) when is_number(value) do
    # Simplified barometric formula: h ≈ 44330 * (1 - (P/P0)^0.1903)
    # P0 = 1013.25 hPa (sea level)
    round(44330 * (1 - :math.pow(value / 1013.25, 0.1903)))
  end
  defp pressure_to_altitude(_), do: 0

  # ============================================================================
  # GAS / AIR QUALITY - eCO2 and TVOC display
  # ============================================================================

  @impl true
  def render(%{:attribute_type => attr, :view_mode => :summary} = assigns) when attr in ["gas", "air_quality"] do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="cloud" type="outline" class={"h-3 w-3 #{air_quality_color(@lastvalue)}"} />
        Air Quality
      </span>
      <div :if={@lastvalue} class="flex items-center gap-2">
        <span class={["font-mono", air_quality_color(@lastvalue)]}>{air_quality_label(@lastvalue.payload)}</span>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => attr} = assigns) when attr in ["gas", "air_quality"] do
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
          attribute_name="Air Quality"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-4 mb-2">
            <div class={["text-lg font-bold", air_quality_color(@lastvalue)]}>
              {air_quality_label(@lastvalue.payload)}
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4 text-xs">
            <div class="bg-gray-800 rounded p-2">
              <div class="text-gray-400">eCO₂</div>
              <div class="text-white font-mono text-lg">
                {get_in(@lastvalue, [:payload, :eco2]) || "--"}
                <span class="text-gray-400 text-xs">ppm</span>
              </div>
            </div>
            <div class="bg-gray-800 rounded p-2">
              <div class="text-gray-400">TVOC</div>
              <div class="text-white font-mono text-lg">
                {get_in(@lastvalue, [:payload, :tvoc]) || "--"}
                <span class="text-gray-400 text-xs">ppb</span>
              </div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp air_quality_label(%{eco2: eco2}) when is_number(eco2) do
    cond do
      eco2 < 600 -> "Excellent"
      eco2 < 800 -> "Good"
      eco2 < 1000 -> "Moderate"
      eco2 < 1500 -> "Poor"
      true -> "Bad"
    end
  end
  defp air_quality_label(_), do: "--"

  defp air_quality_color(%{payload: %{eco2: eco2}}) when is_number(eco2) do
    cond do
      eco2 < 600 -> "text-green-400"
      eco2 < 800 -> "text-green-300"
      eco2 < 1000 -> "text-yellow-400"
      eco2 < 1500 -> "text-orange-400"
      true -> "text-red-400"
    end
  end
  defp air_quality_color(_), do: "text-gray-400"

  # ============================================================================
  # COLOR - RGB color swatch with color temperature
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "color", :view_mode => :summary} = assigns) do
    assigns = assign(assigns, :color_data, extract_color_data(assigns[:lastvalue]))

    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="swatch" type="solid" class="h-3 w-3 text-pink-400" />
        Color
      </span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <div
          class="w-4 h-4 rounded border border-gray-600"
          style={"background-color: #{@color_data.hex}"}
        />
        <span class="text-gray-400 font-mono text-[10px]">{@color_data.hex}</span>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "color"} = assigns) do
    assigns = assign(assigns, :color_data, extract_color_data(assigns[:lastvalue]))

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
          attribute_name="Color Sensor"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-4 mb-3">
            <div
              class="w-16 h-16 rounded-lg border-2 border-gray-600 shadow-lg"
              style={"background-color: #{@color_data.hex}"}
            />
            <div>
              <div class="text-white font-mono text-lg">{@color_data.hex}</div>
              <div :if={@color_data.color_temperature} class="text-xs text-gray-400">
                ~{@color_data.color_temperature}K
              </div>
            </div>
          </div>
          <div class="grid grid-cols-4 gap-2 text-xs">
            <div class="text-center">
              <div class="text-red-400 font-mono">{@color_data.r}</div>
              <div class="text-gray-500">R</div>
            </div>
            <div class="text-center">
              <div class="text-green-400 font-mono">{@color_data.g}</div>
              <div class="text-gray-500">G</div>
            </div>
            <div class="text-center">
              <div class="text-blue-400 font-mono">{@color_data.b}</div>
              <div class="text-gray-500">B</div>
            </div>
            <div class="text-center">
              <div class="text-gray-300 font-mono">{@color_data.clear || "--"}</div>
              <div class="text-gray-500">Clear</div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  # Extract color data from various payload formats
  defp extract_color_data(nil), do: %{r: 0, g: 0, b: 0, clear: nil, hex: "#808080", color_temperature: nil}
  defp extract_color_data(%{payload: %{hex: hex} = payload}) when is_binary(hex) do
    %{
      r: Map.get(payload, :r, 0),
      g: Map.get(payload, :g, 0),
      b: Map.get(payload, :b, 0),
      clear: Map.get(payload, :clear),
      hex: hex,
      color_temperature: Map.get(payload, :color_temperature)
    }
  end
  defp extract_color_data(%{payload: %{r: r, g: g, b: b} = payload}) when is_integer(r) and is_integer(g) and is_integer(b) do
    hex = "#" <> Base.encode16(<<min(255, r), min(255, g), min(255, b)>>, case: :lower)
    %{
      r: r,
      g: g,
      b: b,
      clear: Map.get(payload, :clear),
      hex: hex,
      color_temperature: Map.get(payload, :color_temperature)
    }
  end
  defp extract_color_data(%{payload: value}) when is_integer(value) do
    # Raw integer - could be a palette index or single value
    %{r: value, g: value, b: value, clear: nil, hex: "#808080", color_temperature: nil}
  end
  defp extract_color_data(_), do: %{r: 0, g: 0, b: 0, clear: nil, hex: "#808080", color_temperature: nil}

  # ============================================================================
  # QUATERNION / EULER - 3D orientation visualization
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "quaternion", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="cube" type="outline" class="h-3 w-3 text-indigo-400" />
        Orientation
      </span>
      <span :if={@lastvalue} class="text-white font-mono text-[10px]">
        Q({format_quat_component(@lastvalue.payload, :w)}, {format_quat_component(@lastvalue.payload, :x)}, {format_quat_component(@lastvalue.payload, :y)}, {format_quat_component(@lastvalue.payload, :z)})
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "quaternion"} = assigns) do
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
          attribute_name="Quaternion"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="py-2">
          <div class="grid grid-cols-4 gap-2 text-xs">
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-gray-400">W</div>
              <div class="text-white font-mono">{format_quat_component(@lastvalue.payload, :w)}</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-red-400">X</div>
              <div class="text-white font-mono">{format_quat_component(@lastvalue.payload, :x)}</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-green-400">Y</div>
              <div class="text-white font-mono">{format_quat_component(@lastvalue.payload, :y)}</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-blue-400">Z</div>
              <div class="text-white font-mono">{format_quat_component(@lastvalue.payload, :z)}</div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_quat_component(payload, key) do
    case Map.get(payload, key) do
      nil -> "--"
      val when is_number(val) -> Float.round(val * 1.0, 3)
      _ -> "--"
    end
  end

  @impl true
  def render(%{:attribute_type => "euler", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="arrows-pointing-out" type="outline" class="h-3 w-3 text-indigo-400" />
        Euler
      </span>
      <span :if={@lastvalue} class="text-white font-mono text-[10px]">
        R:{format_euler(@lastvalue.payload, :roll)}° P:{format_euler(@lastvalue.payload, :pitch)}° Y:{format_euler(@lastvalue.payload, :yaw)}°
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "euler"} = assigns) do
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
          attribute_name="Euler Angles"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="py-2">
          <div class="grid grid-cols-3 gap-2 text-xs">
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-red-400">Roll</div>
              <div class="text-white font-mono text-lg">{format_euler(@lastvalue.payload, :roll)}°</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-green-400">Pitch</div>
              <div class="text-white font-mono text-lg">{format_euler(@lastvalue.payload, :pitch)}°</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-blue-400">Yaw</div>
              <div class="text-white font-mono text-lg">{format_euler(@lastvalue.payload, :yaw)}°</div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_euler(payload, key) do
    case Map.get(payload, key) do
      nil -> "--"
      val when is_number(val) -> round(val)
      _ -> "--"
    end
  end

  # ============================================================================
  # HEADING - Compass display
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "heading", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="arrow-up" type="solid" class="h-3 w-3 text-cyan-400" style={"transform: rotate(#{heading_rotation(@lastvalue)}deg)"} />
        Heading
      </span>
      <span :if={@lastvalue} class="text-white font-mono flex items-center gap-1">
        {format_heading(@lastvalue.payload)}° <span class="text-cyan-400">{heading_direction(@lastvalue.payload)}</span>
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "heading"} = assigns) do
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
          attribute_name="Compass Heading"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center justify-center py-4">
          <div class="relative w-24 h-24">
            <div class="absolute inset-0 rounded-full border-2 border-gray-600">
              <div class="absolute top-1 left-1/2 -translate-x-1/2 text-[10px] text-gray-400">N</div>
              <div class="absolute bottom-1 left-1/2 -translate-x-1/2 text-[10px] text-gray-400">S</div>
              <div class="absolute left-1 top-1/2 -translate-y-1/2 text-[10px] text-gray-400">W</div>
              <div class="absolute right-1 top-1/2 -translate-y-1/2 text-[10px] text-gray-400">E</div>
            </div>
            <Heroicons.icon
              name="arrow-up"
              type="solid"
              class="absolute top-1/2 left-1/2 w-8 h-8 text-cyan-400 -translate-x-1/2 -translate-y-1/2"
              style={"transform: translate(-50%, -50%) rotate(#{heading_rotation(@lastvalue)}deg)"}
            />
          </div>
          <div class="ml-4 text-center">
            <div class="text-2xl font-bold text-white">{format_heading(@lastvalue.payload)}°</div>
            <div class="text-cyan-400">{heading_direction(@lastvalue.payload)}</div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_heading(%{value: value}) when is_number(value), do: round(value)
  defp format_heading(value) when is_number(value), do: round(value)
  defp format_heading(_), do: 0

  defp heading_rotation(%{payload: %{value: value}}) when is_number(value), do: value
  defp heading_rotation(%{payload: value}) when is_number(value), do: value
  defp heading_rotation(_), do: 0

  defp heading_direction(%{value: _value, direction: dir}) when is_binary(dir), do: dir
  defp heading_direction(%{value: value}) when is_number(value), do: heading_to_dir(value)
  defp heading_direction(value) when is_number(value), do: heading_to_dir(value)
  defp heading_direction(_), do: "N"

  defp heading_to_dir(heading) do
    cond do
      heading >= 337.5 or heading < 22.5 -> "N"
      heading >= 22.5 and heading < 67.5 -> "NE"
      heading >= 67.5 and heading < 112.5 -> "E"
      heading >= 112.5 and heading < 157.5 -> "SE"
      heading >= 157.5 and heading < 202.5 -> "S"
      heading >= 202.5 and heading < 247.5 -> "SW"
      heading >= 247.5 and heading < 292.5 -> "W"
      heading >= 292.5 and heading < 337.5 -> "NW"
      true -> "?"
    end
  end

  # ============================================================================
  # STEPS - Step counter display
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "steps", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="user" type="outline" class="h-3 w-3 text-green-400" />
        Steps
      </span>
      <span :if={@lastvalue} class="text-white font-mono">
        {format_steps(@lastvalue.payload)}
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "steps"} = assigns) do
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
          attribute_name="Step Counter"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center justify-center py-4">
          <Heroicons.icon name="user" type="outline" class="h-8 w-8 text-green-400 mr-3" />
          <div class="text-center">
            <div class="text-3xl font-bold text-white">{format_steps(@lastvalue.payload)}</div>
            <div class="text-sm text-gray-400">steps</div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_steps(%{count: count}) when is_integer(count), do: Integer.to_string(count)
  defp format_steps(count) when is_integer(count), do: Integer.to_string(count)
  defp format_steps(_), do: "0"

  # ============================================================================
  # TAP - Tap detection indicator
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "tap", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="hand-raised" type="outline" class="h-3 w-3 text-amber-400" />
        Tap
      </span>
      <span :if={@lastvalue} class="text-amber-400 font-mono">
        {tap_direction(@lastvalue.payload)}
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "tap"} = assigns) do
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
          attribute_name="Tap Detection"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="text-xs text-gray-400">No tap detected</div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-3">
            <Heroicons.icon name="hand-raised" type="solid" class="h-8 w-8 text-amber-400" />
            <div>
              <div class="text-white font-bold">{tap_direction(@lastvalue.payload)}</div>
              <div class="text-xs text-gray-400">
                Tap count: {get_in(@lastvalue, [:payload, :count]) || 1}
              </div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp tap_direction(%{direction: dir}) when is_binary(dir), do: dir
  defp tap_direction(_), do: "--"

  # ============================================================================
  # ORIENTATION - Device orientation (portrait/landscape/face up/down)
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "orientation", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="device-phone-mobile" type="outline" class={"h-3 w-3 text-teal-400 #{orientation_rotation(@lastvalue)}"} />
        Orientation
      </span>
      <span :if={@lastvalue} class="text-white">
        {orientation_label(@lastvalue.payload)}
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "orientation"} = assigns) do
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
          attribute_name="Device Orientation"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="flex items-center justify-center py-4">
          <Heroicons.icon name="device-phone-mobile" type="outline" class={"h-12 w-12 text-teal-400 #{orientation_rotation(@lastvalue)}"} />
          <div class="ml-4 text-center">
            <div class="text-xl font-bold text-white">{orientation_label(@lastvalue.payload)}</div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp orientation_label(%{orientation: orient}) when is_binary(orient) do
    orient
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp orientation_label(_), do: "Unknown"

  defp orientation_rotation(%{payload: %{orientation: orient}}) do
    case orient do
      "landscape" -> "rotate-90"
      "reverse_landscape" -> "-rotate-90"
      "reverse_portrait" -> "rotate-180"
      _ -> ""
    end
  end
  defp orientation_rotation(_), do: ""

  # ============================================================================
  # LED - RGB LED control (bidirectional)
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "led", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="light-bulb" type="solid" class="h-3 w-3 text-yellow-400" />
        LED
      </span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <div
          class="w-4 h-4 rounded-full border border-gray-600"
          style={"background-color: rgb(#{get_in(@lastvalue, [:payload, :r]) || 0}, #{get_in(@lastvalue, [:payload, :g]) || 0}, #{get_in(@lastvalue, [:payload, :b]) || 0})"}
        />
        <span class="text-gray-400">{get_in(@lastvalue, [:payload, :mode]) || "off"}</span>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "led"} = assigns) do
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
          attribute_name="RGB LED Control"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="text-xs text-gray-400">LED state unknown</div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-4 mb-3">
            <div
              class="w-12 h-12 rounded-full border-2 border-gray-600 shadow-lg"
              style={"background-color: rgb(#{get_in(@lastvalue, [:payload, :r]) || 0}, #{get_in(@lastvalue, [:payload, :g]) || 0}, #{get_in(@lastvalue, [:payload, :b]) || 0}); box-shadow: 0 0 15px rgb(#{get_in(@lastvalue, [:payload, :r]) || 0}, #{get_in(@lastvalue, [:payload, :g]) || 0}, #{get_in(@lastvalue, [:payload, :b]) || 0})"}
            />
            <div>
              <div class="text-white font-bold capitalize">{get_in(@lastvalue, [:payload, :mode]) || "off"}</div>
              <div class="text-xs text-gray-400">
                Intensity: {get_in(@lastvalue, [:payload, :intensity]) || 100}%
              </div>
            </div>
          </div>
          <div class="grid grid-cols-3 gap-2 text-xs">
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-red-400">R</div>
              <div class="text-white font-mono">{get_in(@lastvalue, [:payload, :r]) || 0}</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-green-400">G</div>
              <div class="text-white font-mono">{get_in(@lastvalue, [:payload, :g]) || 0}</div>
            </div>
            <div class="bg-gray-800 rounded p-2 text-center">
              <div class="text-blue-400">B</div>
              <div class="text-white font-mono">{get_in(@lastvalue, [:payload, :b]) || 0}</div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  # ============================================================================
  # SPEAKER - Speaker control (bidirectional)
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "speaker", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="speaker-wave" type="outline" class="h-3 w-3 text-violet-400" />
        Speaker
      </span>
      <span :if={@lastvalue} class="text-violet-400">
        {format_speaker_status(@lastvalue.payload)}
      </span>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "speaker"} = assigns) do
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
          attribute_name="Speaker"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="text-xs text-gray-400">Speaker idle</div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-3">
            <Heroicons.icon name="speaker-wave" type="outline" class="h-8 w-8 text-violet-400" />
            <div>
              <div class="text-white">{format_speaker_status(@lastvalue.payload)}</div>
              <div :if={get_in(@lastvalue, [:payload, :frequency])} class="text-xs text-gray-400">
                {get_in(@lastvalue, [:payload, :frequency])} Hz
              </div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_speaker_status(%{frequency: freq}) when is_number(freq), do: "#{freq} Hz"
  defp format_speaker_status(%{sample: sample}) when is_integer(sample), do: "Sample ##{sample}"
  defp format_speaker_status(_), do: "Idle"

  # ============================================================================
  # MICROPHONE - Audio level meter
  # ============================================================================

  @impl true
  def render(%{:attribute_type => "microphone", :view_mode => :summary} = assigns) do
    ~H"""
    <div
      class="flex items-center justify-between text-xs py-0.5"
      data-sensor_id={@sensor_id}
      data-attribute_id={@attribute_id}
    >
      <span class="text-gray-400 flex items-center gap-1">
        <Heroicons.icon name="microphone" type="outline" class="h-3 w-3 text-rose-400" />
        Mic
      </span>
      <div :if={@lastvalue} class="flex items-center gap-1">
        <meter
          min="0"
          max="100"
          value={mic_level_normalized(@lastvalue.payload)}
          class="h-2 w-12"
        />
        <span class="text-gray-400 font-mono text-[10px]">{format_mic_level(@lastvalue.payload)}</span>
      </div>
      <.loading_spinner :if={is_nil(@lastvalue)} />
    </div>
    """
  end

  @impl true
  def render(%{:attribute_type => "microphone"} = assigns) do
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
          attribute_name="Microphone"
          lastvalue={@lastvalue}
          socket={@socket}
        />

        <div :if={is_nil(@lastvalue)} class="loading"></div>

        <div :if={@lastvalue} class="py-2">
          <div class="flex items-center gap-4">
            <Heroicons.icon name="microphone" type="outline" class="h-8 w-8 text-rose-400" />
            <div class="flex-1">
              <meter
                min="0"
                max="100"
                low="33"
                high="66"
                optimum="50"
                value={mic_level_normalized(@lastvalue.payload)}
                class="w-full h-4"
              />
              <div class="text-xs text-gray-400 mt-1">
                {format_mic_level(@lastvalue.payload)} dB
              </div>
            </div>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  defp format_mic_level(%{level: level}) when is_number(level), do: round(level)
  defp format_mic_level(_), do: 0

  defp mic_level_normalized(%{level: level}) when is_number(level) do
    # Normalize dB to 0-100 range (assuming -60dB to 0dB range)
    normalized = (level + 60) / 60 * 100
    max(0, min(100, normalized))
  end
  defp mic_level_normalized(_), do: 0

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
    # Full mount passes :attribute map; partial updates pass :lastvalue directly
    if Map.has_key?(assigns, :attribute) do
      attribute = assigns.attribute
      Logger.debug("attribute update (full) attribute_id: #{attribute.attribute_id}")

      # Get render hints from AttributeType for dynamic visualization selection
      attribute_type = assigns.attribute_type || "unknown"
      render_hints = AttributeType.render_hints(attribute_type)
      view_mode = Map.get(assigns, :view_mode, :normal)

      {
        :ok,
        socket
        |> assign_new(:id, fn _ -> assigns.id end)
        |> assign_new(:attribute_id, fn _ -> attribute.attribute_id end)
        |> assign_new(:attribute_type, fn _ -> attribute_type end)
        |> assign_new(:sensor_id, fn _ -> assigns.sensor_id end)
        |> assign_new(:attribute, fn _ -> attribute end)
        |> assign_new(:render_hints, fn _ -> render_hints end)
        # Use lastvalue from attribute on full mount
        |> assign(:lastvalue, attribute.lastvalue)
        |> assign(:view_mode, view_mode)
      }
    else
      # Partial update - only update lastvalue (and view_mode/pressed_buttons if present)
      Logger.debug("attribute update (partial) id: #{assigns.id}")

      socket = assign(socket, :lastvalue, assigns.lastvalue)
      socket = if Map.has_key?(assigns, :view_mode), do: assign(socket, :view_mode, assigns.view_mode), else: socket
      socket = if Map.has_key?(assigns, :pressed_buttons), do: assign(socket, :pressed_buttons, assigns.pressed_buttons), else: socket
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

  # ============================================================================
  # IMU Data Parsing and Visualization Helpers
  # ============================================================================

  # Default IMU data structure
  @default_imu_data %{
    ax: 0.0, ay: 0.0, az: 0.0,
    rx: 0.0, ry: 0.0, rz: 0.0,
    qw: 1.0, qx: 0.0, qy: 0.0, qz: 0.0,
    pitch: 0.0, roll: 0.0, yaw: 0.0,
    heading: 0.0,
    accel_magnitude: 0.0,
    pitch_display: 0.0, roll_display: 0.0, tilt_display: 0.0
  }

  # Parse IMU payload from comma-separated string:
  # timestamp,ax,ay,az,rx,ry,rz,qw,qx,qy,qz
  defp parse_imu_payload(nil), do: @default_imu_data
  defp parse_imu_payload(%{payload: payload}) when is_binary(payload) do
    parts = String.split(payload, ",")

    if length(parts) >= 11 do
      # Parse values (skip timestamp at index 0)
      ax = parse_float_at(parts, 1)
      ay = parse_float_at(parts, 2)
      az = parse_float_at(parts, 3)
      rx = parse_float_at(parts, 4)
      ry = parse_float_at(parts, 5)
      rz = parse_float_at(parts, 6)
      qw = parse_float_at(parts, 7)
      qx = parse_float_at(parts, 8)
      qy = parse_float_at(parts, 9)
      qz = parse_float_at(parts, 10)

      # Calculate acceleration magnitude
      accel_magnitude = :math.sqrt(ax * ax + ay * ay + az * az)

      # Convert quaternion to Euler angles (in degrees)
      {pitch, roll, yaw} = quaternion_to_euler(qw, qx, qy, qz)

      # Calculate heading from yaw (0-360 degrees, where 0 is North)
      heading = normalize_heading(yaw)

      # Calculate display values for tilt indicator (-100% to 100%)
      pitch_display = clamp(pitch / 90 * 100, -100, 100)
      roll_display = clamp(roll / 90 * 100, -100, 100)
      tilt_display = clamp(roll / 2, -45, 45)

      %{
        ax: ax, ay: ay, az: az,
        rx: rx, ry: ry, rz: rz,
        qw: qw, qx: qx, qy: qy, qz: qz,
        pitch: pitch, roll: roll, yaw: yaw,
        heading: heading,
        accel_magnitude: accel_magnitude,
        pitch_display: pitch_display, roll_display: roll_display, tilt_display: tilt_display
      }
    else
      @default_imu_data
    end
  end
  defp parse_imu_payload(_), do: @default_imu_data

  defp parse_float_at(parts, index) do
    case Enum.at(parts, index) do
      nil -> 0.0
      str ->
        case Float.parse(str) do
          {val, _} -> val
          :error -> 0.0
        end
    end
  end

  # Convert quaternion to Euler angles (pitch, roll, yaw) in degrees
  defp quaternion_to_euler(qw, qx, qy, qz) do
    # Roll (x-axis rotation)
    sinr_cosp = 2.0 * (qw * qx + qy * qz)
    cosr_cosp = 1.0 - 2.0 * (qx * qx + qy * qy)
    roll = :math.atan2(sinr_cosp, cosr_cosp) * 180.0 / :math.pi()

    # Pitch (y-axis rotation)
    sinp = 2.0 * (qw * qy - qz * qx)
    pitch = if abs(sinp) >= 1.0 do
      sign(sinp) * 90.0
    else
      :math.asin(sinp) * 180.0 / :math.pi()
    end

    # Yaw (z-axis rotation)
    siny_cosp = 2.0 * (qw * qz + qx * qy)
    cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
    yaw = :math.atan2(siny_cosp, cosy_cosp) * 180.0 / :math.pi()

    {pitch, roll, yaw}
  end

  defp sign(x) when x >= 0, do: 1.0
  defp sign(_), do: -1.0

  defp normalize_heading(yaw) do
    # Convert yaw (-180 to 180) to heading (0 to 360)
    if yaw < 0, do: yaw + 360.0, else: yaw
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  # Acceleration color based on magnitude
  defp accel_color(magnitude) when magnitude < 2, do: "text-green-400 bg-green-500"
  defp accel_color(magnitude) when magnitude < 5, do: "text-yellow-400 bg-yellow-500"
  defp accel_color(magnitude) when magnitude < 10, do: "text-orange-400 bg-orange-500"
  defp accel_color(_), do: "text-red-400 bg-red-500"

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
