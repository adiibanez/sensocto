defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.StatefulSensorLive

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
        location_sensors: location_sensors
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

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Lobby Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end
end
