defmodule SensoctoWeb.IndexLive do
  @moduledoc """
  Main index page showing:
  - Lobby preview (sensors)
  - My Rooms section
  - Public Rooms section
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.Live.Components.StatefulSensorComponent
  alias SensoctoWeb.Live.Components.MediaPlayerComponent
  alias Sensocto.Rooms
  alias Sensocto.AttentionTracker
  alias Sensocto.Lenses.PriorityLens

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @lobby_preview_options [10, 20, 30]
  @default_lobby_limit 10

  @attention_debounce_ms 200

  # Maximum send_update calls per batch to prevent overwhelming the system
  @max_updates_per_batch 10

  @impl true
  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:lobby")
    # Subscribe to lobby media player events
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "media_player:lobby")

    user = socket.assigns.current_user
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)

    # Get lobby preview limit with attention-based sorting
    lobby_limit = @default_lobby_limit
    lobby_sensor_ids = get_sorted_sensor_ids(sensors, lobby_limit)

    # Fetch rooms
    my_rooms = Rooms.list_user_rooms(user)
    public_rooms = Rooms.list_public_rooms()

    # Filter out user's rooms from public rooms to avoid duplicates
    my_room_ids = MapSet.new(my_rooms, & &1.id)

    public_rooms_filtered =
      Enum.reject(public_rooms, fn room -> MapSet.member?(my_room_ids, room.id) end)

    new_socket =
      socket
      |> assign(
        current_path: "/",
        sensors_online_count: sensors_count,
        sensors_online: %{},
        sensors_offline: %{},
        sensors: sensors,
        lobby_sensor_ids: lobby_sensor_ids,
        lobby_limit: lobby_limit,
        lobby_limit_options: @lobby_preview_options,
        my_rooms: my_rooms,
        public_rooms: public_rooms_filtered,
        global_view_mode: :summary,
        attention_debounce_ref: nil,
        priority_lens_registered: false,
        priority_lens_topic: nil
      )

    # Schedule PriorityLens registration after mount to handle timing issues
    # Sensors may not be fully available during the initial mount
    new_socket =
      if connected?(new_socket) do
        # Delay registration to allow sensors to be ready
        Process.send_after(self(), :register_priority_lens, 100)
        new_socket
      else
        new_socket
      end

    :telemetry.execute(
      [:sensocto, :live, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    Logger.debug(
      "presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
    )

    # Update online/offline immediately with payload data (fast)
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

    # Schedule async refresh of full sensor state to avoid blocking parent LiveView
    # This prevents child mount timeouts when get_all_sensors_state is slow
    send(self(), :refresh_sensors)

    # If not registered with PriorityLens yet and we have new sensors, try to register
    if not socket.assigns[:priority_lens_registered] and map_size(payload.joins) > 0 do
      send(self(), :register_priority_lens)
    end

    {
      :noreply,
      socket
      |> assign(:sensors_online, sensors_online)
      |> assign(:sensors_offline, payload.leaves)
    }
  end

  # Register with PriorityLens - called after mount to ensure sensors are available
  @impl true
  def handle_info(:register_priority_lens, socket) do
    # Skip if already registered
    if socket.assigns[:priority_lens_registered] do
      {:noreply, socket}
    else
      # Use sensors already assigned during mount, or refresh if empty
      lobby_sensor_ids = socket.assigns.lobby_sensor_ids

      # If no sensors in assigns, try to fetch fresh
      {lobby_sensor_ids, socket} =
        if lobby_sensor_ids == [] do
          sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
          lobby_limit = socket.assigns.lobby_limit
          new_ids = get_sorted_sensor_ids(sensors, lobby_limit)

          socket =
            socket
            |> assign(:sensors, sensors)
            |> assign(:lobby_sensor_ids, new_ids)
            |> assign(:sensors_online_count, Enum.count(sensors))

          {new_ids, socket}
        else
          {lobby_sensor_ids, socket}
        end

      if lobby_sensor_ids != [] do
        user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

        # Register attention for each sensor so data flows to global topic
        # Without this, SimpleSensor won't broadcast to data:global
        Enum.each(lobby_sensor_ids, fn sensor_id ->
          AttentionTracker.register_view(sensor_id, "index_preview", user_id)
        end)

        # Subscribe to signal topics for attribute change notifications
        Enum.each(lobby_sensor_ids, fn sensor_id ->
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
        end)

        # Register with PriorityLens for adaptive data streaming
        case PriorityLens.register_socket(socket.id, lobby_sensor_ids, quality: :high) do
          {:ok, topic} ->
            Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)

            {:noreply,
             socket
             |> assign(:priority_lens_registered, true)
             |> assign(:priority_lens_topic, topic)}

          {:error, _reason} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(:refresh_sensors, socket) do
    # Fetch full sensor state asynchronously - this won't block child mounts
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)
    lobby_limit = socket.assigns.lobby_limit

    # Get sorted sensor IDs with attention-based sorting
    new_sensor_ids = get_sorted_sensor_ids(sensors, lobby_limit)
    current_sensor_ids = socket.assigns.lobby_sensor_ids

    updated_socket =
      socket
      |> assign(:sensors_online_count, sensors_count)
      |> assign(:sensors, sensors)

    # Only assign new sensor_ids if they actually changed
    updated_socket =
      if new_sensor_ids != current_sensor_ids do
        # Update PriorityLens with new sensor list
        updated_socket = update_priority_lens_sensors(updated_socket, new_sensor_ids)
        assign(updated_socket, :lobby_sensor_ids, new_sensor_ids)
      else
        updated_socket
      end

    {:noreply, updated_socket}
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    Logger.debug("IndexLive handled signal: #{inspect(msg)}")

    {:noreply, put_flash(socket, :info, "You clicked the button!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  # Handle attention changes from any sensor - debounce to avoid excessive re-sorting
  @impl true
  def handle_info({:attention_changed, %{sensor_id: _sensor_id, level: _level}}, socket) do
    # Cancel any pending debounce timer
    if socket.assigns.attention_debounce_ref do
      Process.cancel_timer(socket.assigns.attention_debounce_ref)
    end

    # Schedule debounced resort
    ref = Process.send_after(self(), :resort_lobby_by_attention, @attention_debounce_ms)
    {:noreply, assign(socket, :attention_debounce_ref, ref)}
  end

  # Perform the actual resort after debounce period
  @impl true
  def handle_info(:resort_lobby_by_attention, socket) do
    sensors = socket.assigns.sensors
    lobby_limit = socket.assigns.lobby_limit
    new_sensor_ids = get_sorted_sensor_ids(sensors, lobby_limit)
    current_sensor_ids = socket.assigns.lobby_sensor_ids

    updated_socket =
      if new_sensor_ids != current_sensor_ids do
        assign(socket, :lobby_sensor_ids, new_sensor_ids)
      else
        socket
      end

    {:noreply, assign(updated_socket, :attention_debounce_ref, nil)}
  end

  # Handle media player state updates from PubSub
  @impl true
  def handle_info({:media_player_state, state}, socket) do
    send_update(MediaPlayerComponent,
      id: "index-media-player",
      player_state: state.state,
      position_seconds: state.position_seconds,
      current_item: state.current_item,
      playlist_items: state.playlist_items,
      controller_user_id: state.controller_user_id,
      controller_user_name: state.controller_user_name
    )

    {:noreply, socket}
  end

  # ==========================================================================
  # PriorityLens Message Handlers (realtime sensor data)
  # ==========================================================================

  # Handle PriorityLens batch data - forward to visible sensor components
  @impl true
  def handle_info({:lens_batch, batch_data}, socket) do
    visible_sensor_ids = socket.assigns.lobby_sensor_ids

    # Filter to sensors that are in our lobby preview and have data in this batch
    sensors_with_data = Map.keys(batch_data) |> MapSet.new()

    sensors_to_update =
      visible_sensor_ids
      |> Enum.filter(&MapSet.member?(sensors_with_data, &1))
      |> Enum.take(@max_updates_per_batch)

    # Forward measurements to each visible sensor component
    Enum.each(sensors_to_update, fn sensor_id ->
      attrs = Map.get(batch_data, sensor_id, %{})

      # Transform to measurements_batch format expected by StatefulSensorComponent
      # IMPORTANT: Preserve the event field for button press/release events
      # NOTE: Each attribute may contain a list of measurements or a single measurement
      measurements =
        Enum.flat_map(attrs, fn {attr_id, measurements_or_single} ->
          # Handle both list of measurements and single measurement
          measurements_list =
            case measurements_or_single do
              list when is_list(list) -> list
              single when is_map(single) -> [single]
              _other -> []
            end

          Enum.map(measurements_list, fn measurement ->
            timestamp = Map.get(measurement, :timestamp, System.system_time(:millisecond))
            payload = Map.get(measurement, :payload, measurement)
            event = Map.get(measurement, :event)

            base = %{
              attribute_id: attr_id,
              timestamp: timestamp,
              payload: payload
            }

            # Add event field if present (for button press/release)
            if event, do: Map.put(base, :event, event), else: base
          end)
        end)

      send_update(StatefulSensorComponent,
        id: "sensor_#{sensor_id}",
        measurements_batch: measurements
      )
    end)

    {:noreply, socket}
  end

  # Handle PriorityLens digest data (low quality mode)
  @impl true
  def handle_info({:lens_digest, _digests}, socket) do
    # For index page, we can ignore digest mode - just show last known state
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("IndexLive unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_all_view_mode", _params, socket) do
    new_mode = if socket.assigns.global_view_mode == :summary, do: :normal, else: :summary

    # Broadcast to all sensor LiveViews to update their view mode
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "ui:view_mode",
      {:global_view_mode_changed, new_mode}
    )

    {:noreply, assign(socket, :global_view_mode, new_mode)}
  end

  @impl true
  def handle_event("set_lobby_limit", %{"limit" => limit_str}, socket) do
    limit = String.to_integer(limit_str)
    sensors = socket.assigns.sensors
    new_sensor_ids = get_sorted_sensor_ids(sensors, limit)

    # Update PriorityLens with new sensor list
    socket = update_priority_lens_sensors(socket, new_sensor_ids)

    {:noreply,
     socket
     |> assign(:lobby_limit, limit)
     |> assign(:lobby_sensor_ids, new_sensor_ids)}
  end

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Unregister attention for the lobby sensors
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id
    lobby_sensor_ids = socket.assigns[:lobby_sensor_ids] || []

    Enum.each(lobby_sensor_ids, fn sensor_id ->
      AttentionTracker.unregister_view(sensor_id, "index_preview", user_id)
    end)

    # Unregister from PriorityLens to clean up per-socket state
    if socket.assigns[:priority_lens_registered] do
      PriorityLens.unregister_socket(socket.id)
    end

    :ok
  end

  # Update PriorityLens subscription when sensor list changes
  defp update_priority_lens_sensors(socket, new_sensor_ids) do
    if socket.assigns[:priority_lens_registered] do
      # Update the sensor list in PriorityLens
      PriorityLens.set_sensors(socket.id, new_sensor_ids)
    end

    socket
  end

  # Sort sensors by attention level (highest first) and take the limit
  defp get_sorted_sensor_ids(sensors, limit) do
    attention_priority = %{high: 4, medium: 3, low: 2, none: 1}

    sensors
    |> Map.keys()
    |> Enum.map(fn sensor_id ->
      attention_level = AttentionTracker.get_sensor_attention_level(sensor_id)
      priority = Map.get(attention_priority, attention_level, 0)
      {sensor_id, priority}
    end)
    |> Enum.sort_by(fn {sensor_id, priority} -> {-priority, sensor_id} end)
    |> Enum.take(limit)
    |> Enum.map(fn {sensor_id, _priority} -> sensor_id end)
  end

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
