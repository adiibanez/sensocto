defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.StatefulSensorLive
  alias SensoctoWeb.Live.Components.MediaPlayerComponent

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 4
  @grid_cols_2xl_default 5

  # Threshold for switching to summary mode (<=3 sensors = normal, >3 = summary)
  # Kept for future use when dynamic view mode switching is implemented
  @summary_mode_threshold 3
  _ = @summary_mode_threshold

  @impl true
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:lobby")

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)
    # Extract stable list of sensor IDs - only changes when sensors are added/removed
    sensor_ids = sensors |> Map.keys() |> Enum.sort()

    # Subscribe to data topics for all sensors (for composite views)
    Enum.each(sensor_ids, fn sensor_id ->
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
    end)

    # Calculate max attributes across all sensors for view mode decision
    max_attributes = calculate_max_attributes(sensors)

    # Determine view mode: normal for <=3 sensors with few attributes, summary otherwise
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    # Extract composite visualization data
    {heartrate_sensors, imu_sensors, location_sensors} = extract_composite_data(sensors)

    # Get available rooms for join UI
    user = socket.assigns[:current_user]
    public_rooms = if user, do: Sensocto.Rooms.list_public_rooms(), else: []

    new_socket =
      socket
      |> assign(
        page_title: "Lobby",
        sensors_online_count: sensors_count,
        sensors_online: %{},
        sensors_offline: %{},
        sensor_ids: sensor_ids,
        global_view_mode: default_view_mode,
        grid_cols_sm: min(@grid_cols_sm_default, max(1, sensors_count)),
        grid_cols_lg: min(@grid_cols_lg_default, max(1, sensors_count)),
        grid_cols_xl: min(@grid_cols_xl_default, max(1, sensors_count)),
        grid_cols_2xl: min(@grid_cols_2xl_default, max(1, sensors_count)),
        heartrate_sensors: heartrate_sensors,
        imu_sensors: imu_sensors,
        location_sensors: location_sensors,
        public_rooms: public_rooms,
        show_join_modal: false,
        join_code: ""
      )

    :telemetry.execute(
      [:sensocto, :live, :lobby, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp calculate_max_attributes(sensors) do
    sensors
    |> Enum.map(fn {_id, sensor} -> map_size(sensor.attributes || %{}) end)
    |> Enum.max(fn -> 0 end)
  end

  defp determine_view_mode(_sensors_count, _max_attributes) do
    # Always start in summary mode - users can expand individual tiles as needed
    :summary
  end

  defp extract_composite_data(sensors) do
    heartrate_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}
        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type in ["heartrate", "hr"]
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        hr_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type in ["heartrate", "hr"]
        end)
        bpm = case hr_attr do
          {_attr_id, attr} -> attr.lastvalue && attr.lastvalue.payload || 0
          nil -> 0
        end
        %{sensor_id: sensor_id, bpm: bpm}
      end)

    imu_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}
        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "imu"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        imu_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type == "imu"
        end)
        orientation = case imu_attr do
          {_attr_id, attr} -> attr.lastvalue && attr.lastvalue.payload || %{}
          nil -> %{}
        end
        %{sensor_id: sensor_id, orientation: orientation}
      end)

    location_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}
        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "geolocation"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        geo_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type == "geolocation"
        end)
        position = case geo_attr do
          {_attr_id, attr} ->
            payload = attr.lastvalue && attr.lastvalue.payload || %{}
            %{
              lat: payload["latitude"] || payload[:latitude] || 0,
              lng: payload["longitude"] || payload[:longitude] || 0
            }
          nil -> %{lat: 0, lng: 0}
        end
        %{sensor_id: sensor_id, lat: position.lat, lng: position.lng}
      end)

    {heartrate_sensors, imu_sensors, location_sensors}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    # Only process if there are actual joins or leaves
    if Enum.empty?(payload.joins) and Enum.empty?(payload.leaves) do
      {:noreply, socket}
    else
      Logger.debug(
        "Lobby presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
      )

      sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
      sensors_count = Enum.count(sensors)

      # Only update sensor_ids if the set of sensors has changed
      # This prevents child LiveViews from being re-mounted when only sensor data changes
      new_sensor_ids = sensors |> Map.keys() |> Enum.sort()
      current_sensor_ids = socket.assigns.sensor_ids

      # Only update if sensor list actually changed
      if new_sensor_ids != current_sensor_ids do
        sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

        # Update composite visualization data
        {heartrate_sensors, imu_sensors, location_sensors} = extract_composite_data(sensors)

        updated_socket =
          socket
          |> assign(:sensors_online_count, sensors_count)
          |> assign(:sensors_online, sensors_online)
          |> assign(:sensor_ids, new_sensor_ids)
          |> assign(:heartrate_sensors, heartrate_sensors)
          |> assign(:imu_sensors, imu_sensors)
          |> assign(:location_sensors, location_sensors)

        # Only update sensors_offline if there are actual leaves
        updated_socket =
          if map_size(payload.leaves) > 0 do
            assign(updated_socket, :sensors_offline, payload.leaves)
          else
            updated_socket
          end

        {:noreply, updated_socket}
      else
        # Sensor list unchanged - only update count if it actually changed
        # Avoid updating sensors_online/sensors_offline maps to prevent template re-evaluation
        if sensors_count != socket.assigns.sensors_online_count do
          {:noreply, assign(socket, :sensors_online_count, sensors_count)}
        else
          {:noreply, socket}
        end
      end
    end
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Lobby handled signal")
    {:noreply, put_flash(socket, :info, "Signal received!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  # Handle single measurement for composite views
  @impl true
  def handle_info(
        {:measurement,
         %{
           :payload => payload,
           :timestamp => timestamp,
           :attribute_id => attribute_id,
           :sensor_id => sensor_id
         }},
        socket
      ) do
    # Only push events when on composite view tabs
    case socket.assigns.live_action do
      action when action in [:heartrate, :imu, :location] ->
        {:noreply,
         push_event(socket, "composite_measurement", %{
           sensor_id: sensor_id,
           attribute_id: attribute_id,
           payload: payload,
           timestamp: timestamp
         })}

      _ ->
        {:noreply, socket}
    end
  end

  # Handle batch measurements for composite views
  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements_list}}, socket)
      when is_list(measurements_list) do
    case socket.assigns.live_action do
      action when action in [:heartrate, :imu, :location] ->
        # Get latest measurement per attribute
        latest_by_attr =
          measurements_list
          |> Enum.group_by(& &1.attribute_id)
          |> Enum.map(fn {attr_id, measurements} ->
            latest = Enum.max_by(measurements, & &1.timestamp)
            %{
              sensor_id: sensor_id,
              attribute_id: attr_id,
              payload: latest.payload,
              timestamp: latest.timestamp
            }
          end)

        new_socket =
          Enum.reduce(latest_by_attr, socket, fn measurement, acc ->
            push_event(acc, "composite_measurement", measurement)
          end)

        {:noreply, new_socket}

      _ ->
        {:noreply, socket}
    end
  end

  # Media player events - forward to component via send_update AND push events to JS hook
  @impl true
  def handle_info({:media_state_changed, state}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      player_state: state.state,
      position_seconds: state.position_seconds,
      current_item: state.current_item
    )

    # Push sync event directly to JS hook from parent LiveView
    socket = push_event(socket, "media_sync", %{
      state: state.state,
      position_seconds: state.position_seconds
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_video_changed, %{item: item}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      current_item: item
    )

    # Push video change event directly to JS hook from parent LiveView
    socket = push_event(socket, "media_load_video", %{
      video_id: item.youtube_video_id,
      start_seconds: 0
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_playlist_updated, %{items: items}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      playlist_items: items
    )
    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_controller_changed, %{controller_user_id: user_id, controller_user_name: user_name}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      controller_user_id: user_id,
      controller_user_name: user_name
    )
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Lobby Unknown Message")
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_all_view_mode", _params, socket) do
    new_mode = if socket.assigns.global_view_mode == :summary, do: :normal, else: :summary

    # Broadcast to all sensor LiveViews to update their view mode
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "ui:view_mode", {:global_view_mode_changed, new_mode})

    {:noreply, assign(socket, :global_view_mode, new_mode)}
  end

  # Room join/leave events
  @impl true
  def handle_event("open_join_modal", _params, socket) do
    {:noreply, assign(socket, :show_join_modal, true)}
  end

  @impl true
  def handle_event("close_join_modal", _params, socket) do
    {:noreply, assign(socket, show_join_modal: false, join_code: "")}
  end

  @impl true
  def handle_event("update_join_code", %{"join_code" => code}, socket) do
    {:noreply, assign(socket, :join_code, String.upcase(code))}
  end

  @impl true
  def handle_event("join_room_by_code", %{"join_code" => code}, socket) do
    user = socket.assigns.current_user

    case Sensocto.Rooms.join_by_code(String.trim(code), user) do
      {:ok, room} ->
        # Join with sensors via Neo4j graph
        Sensocto.Rooms.join_room_with_sensors(room, user)

        socket =
          socket
          |> put_flash(:info, "Joined room: #{room.name}")
          |> push_navigate(to: ~p"/rooms/#{room.id}")

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Room not found with that code")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join room")}
    end
  end

  @impl true
  def handle_event("join_room", %{"room_id" => room_id}, socket) do
    user = socket.assigns.current_user

    case Sensocto.Rooms.get_room(room_id) do
      {:ok, room} ->
        case Sensocto.Rooms.join_room_with_sensors(room, user) do
          {:ok, _room} ->
            socket =
              socket
              |> put_flash(:info, "Joined room: #{room.name}")
              |> push_navigate(to: ~p"/rooms/#{room_id}")

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to join room")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Room not found")}
    end
  end

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Lobby Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end
end
