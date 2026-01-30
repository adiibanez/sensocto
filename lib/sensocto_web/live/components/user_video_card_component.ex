defmodule SensoctoWeb.Live.Components.UserVideoCardComponent do
  @moduledoc """
  Video-aware user card component for the Users tab.

  Displays user information with their video stream (if in call) at attention-based quality:
  - High attention (hovering): HD video stream
  - Medium attention (visible): SD/low FPS video
  - Low attention (off-screen): Periodic snapshots
  - No attention (tab hidden): No updates

  When user is not in call, shows their sensor data summary.
  """
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:attention_level, :medium)
     |> assign(:hover, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:user, assigns.user)
      |> assign(:in_call, assigns[:in_call] || false)
      |> assign(:video_tier, assigns[:video_tier] || :viewer)
      |> assign(:speaking, assigns[:speaking] || false)
      |> assign_new(:attention_level, fn -> :medium end)
      |> assign_new(:hover, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def handle_event("hover_enter", _, socket) do
    # Boost attention to high when hovering
    send(self(), {:user_attention_change, socket.assigns.user.connector_id, :high})
    {:noreply, assign(socket, hover: true, attention_level: :high)}
  end

  @impl true
  def handle_event("hover_leave", _, socket) do
    # Reduce attention when leaving hover
    send(self(), {:user_attention_change, socket.assigns.user.connector_id, :medium})
    {:noreply, assign(socket, hover: false, attention_level: :medium)}
  end

  @impl true
  def handle_event("focus_user", _, socket) do
    # User clicked to focus - highest attention
    send(self(), {:user_focus, socket.assigns.user.connector_id})
    {:noreply, assign(socket, :attention_level, :high)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"user-card-#{@user.connector_id}"}
      phx-hook="UserVideoTile"
      phx-target={@myself}
      phx-mouseenter="hover_enter"
      phx-mouseleave="hover_leave"
      phx-click="focus_user"
      data-connector-id={@user.connector_id}
      data-in-call={to_string(@in_call)}
      class={"bg-gray-800 rounded-lg border transition-all cursor-pointer " <>
        if(@hover, do: "border-blue-500 shadow-lg shadow-blue-500/20", else: "border-gray-700 hover:border-gray-600")}
    >
      <%= if @in_call do %>
        <.video_view
          user={@user}
          video_tier={@video_tier}
          speaking={@speaking}
          attention_level={@attention_level}
        />
      <% else %>
        <.sensor_view user={@user} />
      <% end %>
    </div>
    """
  end

  defp video_view(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Video container with aspect ratio --%>
      <div class="aspect-video bg-gray-900 rounded-t-lg overflow-hidden relative">
        <video
          id={"user-video-#{@user.connector_id}"}
          autoplay
          playsinline
          class="w-full h-full object-cover"
        >
        </video>

        <%!-- Snapshot fallback for viewer tier --%>
        <img
          id={"user-snapshot-#{@user.connector_id}"}
          class={"absolute inset-0 w-full h-full object-cover " <>
            if(@video_tier == :viewer, do: "", else: "hidden")}
          alt="Video snapshot"
        />

        <%!-- Tier badge --%>
        <div class="absolute top-2 right-2">
          <.tier_badge tier={@video_tier} />
        </div>

        <%!-- Speaking indicator --%>
        <%= if @speaking do %>
          <div class="absolute top-2 left-2">
            <span class="flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
            </span>
          </div>
          <div class="absolute inset-0 ring-2 ring-green-400 rounded-t-lg pointer-events-none"></div>
        <% end %>

        <%!-- Attention level indicator --%>
        <div class="absolute bottom-2 left-2">
          <.attention_indicator level={@attention_level} />
        </div>
      </div>

      <%!-- User info footer --%>
      <div class="p-3 border-t border-gray-700">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-bold text-sm">
            {@user.connector_name |> String.first() |> String.upcase()}
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-white font-medium truncate text-sm">{@user.connector_name}</p>
            <p class="text-gray-400 text-xs">
              {@user.sensor_count} sensor{if @user.sensor_count != 1, do: "s"}
            </p>
          </div>
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-500/20 text-green-400">
            <span class="w-1.5 h-1.5 rounded-full bg-green-400 mr-1 animate-pulse"></span> In Call
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp sensor_view(assigns) do
    ~H"""
    <div class="p-4">
      <%!-- User Header --%>
      <div class="flex items-center gap-3 mb-3 pb-3 border-b border-gray-700">
        <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-bold text-lg">
          {@user.connector_name |> String.first() |> String.upcase()}
        </div>
        <div class="flex-1 min-w-0">
          <h3 class="text-white font-semibold truncate text-base">{@user.connector_name}</h3>
          <p class="text-gray-400 text-xs">
            {@user.sensor_count} sensor{if @user.sensor_count != 1, do: "s"} · {@user.total_attributes} attributes
          </p>
        </div>
        <div class="flex-shrink-0">
          <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-600/50 text-gray-300">
            Offline
          </span>
        </div>
      </div>

      <%!-- Sensors List --%>
      <div class="mb-3">
        <p class="text-gray-500 text-xs uppercase tracking-wide mb-2">Sensors</p>
        <div class="flex flex-wrap gap-1.5">
          <%= for sensor <- @user.sensors do %>
            <.link
              navigate={~p"/lobby/sensors/#{sensor.sensor_id}"}
              class="inline-flex items-center px-2 py-0.5 rounded text-xs bg-gray-700 text-gray-300 hover:bg-gray-600 hover:text-white transition-colors"
            >
              {sensor.sensor_name}
            </.link>
          <% end %>
        </div>
      </div>

      <%!-- Attributes Summary --%>
      <div>
        <p class="text-gray-500 text-xs uppercase tracking-wide mb-2">Data Types</p>
        <div class="grid grid-cols-2 gap-2">
          <%= for attr <- Enum.take(@user.attributes_summary, 4) do %>
            <div class="bg-gray-700/50 rounded p-2">
              <div class="flex items-center gap-1.5 mb-1">
                <.attribute_icon type={attr.type} />
                <span class="text-xs text-gray-300 capitalize">
                  {String.replace(attr.type, "_", " ")}
                </span>
              </div>
              <div class="text-sm font-mono text-white">
                <.attribute_value attr={attr} />
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp tier_badge(assigns) do
    ~H"""
    <%= case @tier do %>
      <% :active -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-green-500/80 text-white"
          title="Active - HD video"
        >
          HD
        </span>
      <% :recent -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-blue-500/80 text-white"
          title="Recent - SD video"
        >
          SD
        </span>
      <% :viewer -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-gray-500/80 text-white"
          title="Viewer - snapshots"
        >
          📷
        </span>
      <% :idle -> %>
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded bg-gray-700/80 text-gray-300"
          title="Idle"
        >
          💤
        </span>
      <% _ -> %>
        <span></span>
    <% end %>
    """
  end

  defp attention_indicator(assigns) do
    ~H"""
    <%= case @level do %>
      <% :high -> %>
        <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-green-500/80 text-white">
          HIGH
        </span>
      <% :medium -> %>
        <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-blue-500/80 text-white">
          MED
        </span>
      <% :low -> %>
        <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-gray-500/80 text-white">
          LOW
        </span>
      <% _ -> %>
        <span></span>
    <% end %>
    """
  end

  defp attribute_icon(assigns) do
    ~H"""
    <%= case @type do %>
      <% type when type in ["heartrate", "hr"] -> %>
        <Heroicons.icon name="heart" type="solid" class="h-3.5 w-3.5 text-red-400" />
      <% "battery" -> %>
        <Heroicons.icon name="battery-50" type="solid" class="h-3.5 w-3.5 text-yellow-400" />
      <% "temperature" -> %>
        <Heroicons.icon name="fire" type="solid" class="h-3.5 w-3.5 text-orange-400" />
      <% "spo2" -> %>
        <Heroicons.icon name="beaker" type="solid" class="h-3.5 w-3.5 text-blue-400" />
      <% "ecg" -> %>
        <Heroicons.icon name="chart-bar" type="solid" class="h-3.5 w-3.5 text-green-400" />
      <% "imu" -> %>
        <Heroicons.icon name="cube" type="solid" class="h-3.5 w-3.5 text-indigo-400" />
      <% "geolocation" -> %>
        <Heroicons.icon name="map-pin" type="solid" class="h-3.5 w-3.5 text-emerald-400" />
      <% _ -> %>
        <Heroicons.icon name="signal" type="solid" class="h-3.5 w-3.5 text-gray-400" />
    <% end %>
    """
  end

  defp attribute_value(assigns) do
    ~H"""
    <%= cond do %>
      <% @attr.latest_value == nil -> %>
        <span class="text-gray-500">--</span>
      <% @attr.type in ["heartrate", "hr"] and is_number(@attr.latest_value) -> %>
        {"#{round(@attr.latest_value)} bpm"}
      <% @attr.type == "battery" and is_map(@attr.latest_value) -> %>
        {"#{round(@attr.latest_value[:level] || @attr.latest_value["level"] || 0)}%"}
      <% @attr.type == "battery" and is_number(@attr.latest_value) -> %>
        {"#{round(@attr.latest_value)}%"}
      <% @attr.type == "temperature" and is_number(@attr.latest_value) -> %>
        {"#{Float.round(@attr.latest_value * 1.0, 1)}°"}
      <% @attr.type == "spo2" and is_number(@attr.latest_value) -> %>
        {"#{round(@attr.latest_value)}%"}
      <% is_map(@attr.latest_value) -> %>
        <span class="text-gray-400 text-xs">data</span>
      <% is_number(@attr.latest_value) -> %>
        {"#{Float.round(@attr.latest_value * 1.0, 1)}"}
      <% true -> %>
        <span class="text-gray-400 text-xs">--</span>
    <% end %>
    """
  end
end
