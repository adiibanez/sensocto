defmodule SensoctoWeb.IndexLive do
  @moduledoc """
  Main index page showing:
  - Sigma graph preview of lobby sensors (adaptive to system load)
  - My Rooms section
  - Public Rooms section
  """
  use SensoctoWeb, :live_view
  use LiveSvelte.Components
  require Logger
  alias Sensocto.Rooms
  alias Sensocto.SystemLoadMonitor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.LiveHelpers.SensorBackground
  import SensoctoWeb.LiveHelpers.SensorData

  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @snapshot_intervals %{
    normal: 3_000,
    elevated: 5_000,
    high: 15_000
  }

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")

    user = socket.assigns.current_user
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensor_ids = Map.keys(sensors)

    sensors_by_user = group_sensors_by_user(sensors)
    enriched_sensors = enrich_sensors_with_attention(sensors)

    my_rooms = Rooms.list_user_rooms(user)
    public_rooms = Rooms.list_public_rooms()
    my_room_ids = MapSet.new(my_rooms, & &1.id)
    public_rooms_filtered = Enum.reject(public_rooms, &MapSet.member?(my_room_ids, &1.id))

    load_level = SystemLoadMonitor.get_load_level()

    socket =
      assign(socket,
        page_title: "Home",
        current_path: "/",
        sensors_online_count: map_size(sensors),
        my_rooms: my_rooms,
        public_rooms: public_rooms_filtered,
        sensors: sensors,
        sensor_ids: sensor_ids,
        sensors_by_user: sensors_by_user,
        enriched_sensors: enriched_sensors,
        load_level: load_level,
        data_mode: :static,
        snapshot_timer: nil,
        preview_mode: :graph,
        sensor_activity: %{},
        sensor_bg_count: 8,
        sensor_bg_theme: "constellation",
        bg_tick_timer: nil
      )

    socket =
      if connected?(socket) and sensor_ids != [] do
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:load")

        AttentionTracker.register_views_bulk(sensor_ids, "composite_index_graph", socket.id)

        setup_data_mode(socket, load_level, sensor_ids)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    sensor_ids = socket.assigns[:sensor_ids] || []

    if sensor_ids != [] do
      AttentionTracker.unregister_views_bulk(sensor_ids, "composite_index_graph", socket.id)
    end

    if socket.assigns[:preview_mode] == :animation do
      SensorBackground.unsubscribe()
    end

    :ok
  end

  # --- Data mode management ---
  # Homepage uses snapshot-only strategy (no PriorityLens) to avoid
  # overwhelming the client with push_events on a preview widget.

  defp setup_data_mode(socket, load_level, _sensor_ids) do
    case Map.get(@snapshot_intervals, load_level) do
      nil ->
        assign(socket, data_mode: :static)

      interval ->
        timer = Process.send_after(self(), :snapshot_refresh, interval)

        assign(socket,
          data_mode: :snapshot,
          snapshot_timer: timer
        )
    end
  end

  defp teardown_data_mode(socket) do
    if socket.assigns[:snapshot_timer] do
      Process.cancel_timer(socket.assigns.snapshot_timer)
    end

    assign(socket, snapshot_timer: nil, data_mode: :static)
  end

  # --- Handle info callbacks ---

  @impl true
  def handle_info({:system_load_changed, %{level: new_level}}, socket) do
    if new_level == socket.assigns.load_level do
      {:noreply, socket}
    else
      socket =
        socket
        |> teardown_data_mode()
        |> setup_data_mode(new_level, socket.assigns.sensor_ids)
        |> assign(:load_level, new_level)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:memory_protection_changed, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:snapshot_refresh, socket) do
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensor_ids = Map.keys(sensors)

    sensors_by_user = group_sensors_by_user(sensors)
    enriched_sensors = enrich_sensors_with_attention(sensors)

    interval = Map.get(@snapshot_intervals, socket.assigns.load_level, 15_000)
    timer = Process.send_after(self(), :snapshot_refresh, interval)

    {:noreply,
     assign(socket,
       sensors: sensors,
       sensor_ids: sensor_ids,
       sensors_by_user: sensors_by_user,
       enriched_sensors: enriched_sensors,
       sensors_online_count: map_size(sensors),
       snapshot_timer: timer
     )}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload},
        socket
      ) do
    joins = map_size(payload.joins)
    leaves = map_size(payload.leaves)
    new_count = socket.assigns.sensors_online_count + joins - leaves

    {:noreply, assign(socket, :sensors_online_count, max(new_count, 0))}
  end

  # --- Animation mode handle_info (guarded on preview_mode: :animation) ---

  @impl true
  def handle_info(
        {:measurement, %{sensor_id: sid}},
        %{assigns: %{preview_mode: :animation}} = socket
      ) do
    activity = SensorBackground.handle_measurement(socket.assigns.sensor_activity, sid)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info(
        {:measurements_batch, {sid, measurements}},
        %{assigns: %{preview_mode: :animation}} = socket
      ) do
    activity =
      SensorBackground.handle_measurements_batch(
        socket.assigns.sensor_activity,
        sid,
        length(measurements)
      )

    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info(
        {:sensor_online, sensor_id, _config},
        %{assigns: %{preview_mode: :animation}} = socket
      ) do
    activity = SensorBackground.handle_sensor_online(socket.assigns.sensor_activity, sensor_id)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info({:sensor_offline, sensor_id}, %{assigns: %{preview_mode: :animation}} = socket) do
    activity = SensorBackground.handle_sensor_offline(socket.assigns.sensor_activity, sensor_id)
    {:noreply, assign(socket, sensor_activity: activity)}
  end

  @impl true
  def handle_info(:bg_tick, %{assigns: %{preview_mode: :animation}} = socket) do
    {sensors, decayed} =
      SensorBackground.compute_tick(
        socket.assigns.sensor_activity,
        socket.assigns.sensor_bg_count
      )

    timer = SensorBackground.start_bg_tick()

    {:noreply,
     socket
     |> assign(sensor_activity: decayed, bg_tick_timer: timer)
     |> push_event("sensor_bg_update", %{sensors: sensors})}
  end

  @impl true
  def handle_info(:bg_tick, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Event handlers ---

  @valid_themes ~w(constellation waveform aurora particles)

  @impl true
  def handle_event("set_preview_mode", %{"mode" => "animation"}, socket) do
    {:noreply, activate_animation_mode(socket)}
  end

  @impl true
  def handle_event("set_preview_mode", %{"mode" => "graph"}, socket) do
    {:noreply, deactivate_animation_mode(socket)}
  end

  def handle_event("set_preview_mode", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_preview_theme", %{"theme" => theme}, socket)
      when theme in @valid_themes do
    {:noreply,
     socket
     |> assign(:sensor_bg_theme, theme)
     |> push_event("sensor_bg_theme_change", %{theme: theme})}
  end

  def handle_event("set_preview_theme", _params, socket), do: {:noreply, socket}

  # --- Animation mode helpers ---

  defp activate_animation_mode(socket) do
    SensorBackground.subscribe()
    activity = SensorBackground.init_activity()
    timer = SensorBackground.start_bg_tick()

    assign(socket,
      preview_mode: :animation,
      sensor_activity: activity,
      bg_tick_timer: timer
    )
  end

  defp deactivate_animation_mode(socket) do
    SensorBackground.unsubscribe()

    if socket.assigns[:bg_tick_timer] do
      Process.cancel_timer(socket.assigns.bg_tick_timer)
    end

    assign(socket,
      preview_mode: :graph,
      sensor_activity: %{},
      bg_tick_timer: nil
    )
  end

  # --- Components ---

  attr :room, :map, required: true

  defp room_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/rooms/#{@room.id}"}
      class="block bg-gray-800 rounded-lg p-4 hover:bg-gray-700 transition-colors"
    >
      <div class="flex items-start justify-between mb-2">
        <h3 class="text-lg font-semibold truncate text-white">{@room.name}</h3>
        <div class="flex gap-1 flex-shrink-0">
          <%= if @room.is_public do %>
            <span class="px-2 py-0.5 text-xs bg-green-600/20 text-green-400 rounded">Public</span>
          <% else %>
            <span class="px-2 py-0.5 text-xs bg-yellow-600/20 text-yellow-400 rounded">Private</span>
          <% end %>
          <%= if not Map.get(@room, :is_persisted, true) do %>
            <span class="px-2 py-0.5 text-xs bg-purple-600/20 text-purple-400 rounded">Temp</span>
          <% end %>
        </div>
      </div>
      <%= if @room.description do %>
        <p class="text-gray-400 text-sm mb-3 line-clamp-2">{@room.description}</p>
      <% end %>
      <div class="flex items-center gap-4 text-sm text-gray-500">
        <span class="flex items-center gap-1">
          <Heroicons.icon name="cpu-chip" type="outline" class="h-4 w-4" />
          {Map.get(@room, :sensor_count, 0)} sensors
        </span>
      </div>
    </.link>
    """
  end
end
