defmodule SensoctoWeb.StatefulSensorLive do
  use SensoctoWeb, :live_view
  # LVN_ACTIVATION use SensoctoNative, :live_view
  import Phoenix.LiveView

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.Live.Components.AttributeComponent
  import SensoctoWeb.Live.BaseComponents

  require Logger

  # Throttle push_events to prevent WebSocket message queue buildup
  # Flush accumulated measurements every 100ms
  @push_throttle_interval 100

  @doc """
  Renders an attention level badge with appropriate color and icon.
  """
  attr :level, :atom, required: true

  def attention_badge(assigns) do
    {color_class, icon_name, label} =
      case assigns.level do
        :high -> {"text-green-400", "eye", "High"}
        :medium -> {"text-yellow-400", "eye", "Medium"}
        :low -> {"text-orange-400", "eye-slash", "Low"}
        :none -> {"text-gray-500", "eye-slash", "None"}
        _ -> {"text-gray-500", "eye-slash", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:color_class, color_class)
      |> assign(:icon_name, icon_name)
      |> assign(:label, label)

    ~H"""
    <span
      class={"flex items-center gap-1 text-xs #{@color_class}"}
      title={"Attention: #{@label} - affects data update frequency"}
    >
      <Heroicons.icon name={@icon_name} type="outline" class="h-3 w-3" />
      <span class="hidden sm:inline">{@label}</span>
    </span>
    """
  end

  @impl true
  def mount(_params, %{"parent_pid" => parent_pid, "sensor_id" => sensor_id} = _session, socket) do
    Logger.warning(">>> MOUNT StatefulSensorLive #{sensor_id} PID=#{inspect(self())}")

    # Subscribe to PubSub topics for this sensor
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
    # Subscribe to attention changes for this sensor
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}")
    # Subscribe to global UI view mode changes
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "ui:view_mode")

    # Fetch sensor state directly - session only contains sensor_id to avoid re-mounts
    # when sensor data changes (measurements, etc.)
    sensor_state =
      try do
        # Use Task with short timeout to prevent blocking
        task = Task.async(fn -> SimpleSensor.get_view_state(sensor_id) end)
        Task.await(task, 1000)
      catch
        :exit, _ ->
          # Sensor process no longer exists or timeout, create minimal state
          Logger.warning("Could not fetch sensor state for #{sensor_id}")
          %{sensor_id: sensor_id, sensor_name: sensor_id, sensor_type: "unknown", attributes: %{}}
      end

    # Get initial attention level - now uses ETS lookup (fast, no GenServer call)
    initial_attention = AttentionTracker.get_sensor_attention_level(sensor_id)

    # Schedule the first throttle flush
    if connected?(socket) do
      Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)
    end

    # Default to summary view mode - child manages its own view mode
    # Parent can broadcast view mode changes via PubSub "ui:view_mode" topic
    view_mode = :summary

    {:ok,
     socket
     |> assign(:parent_pid, parent_pid)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_state.sensor_id)
     |> assign(:sensor_name, sensor_state.sensor_name)
     |> assign(:sensor_type, sensor_state.sensor_type)
     |> assign(:highlighted, false)
     |> assign(:attention_level, initial_attention)
     |> assign(:attributes_loaded, true)
     |> assign(:battery_state, :normal)
     |> assign(:view_mode, view_mode)
     |> assign(:show_map_modal, false)
     |> assign(:show_detail_modal, false)
     # Throttle buffer: accumulate measurements, flush periodically
     |> assign(:pending_measurements, [])}
  end

  # def _render(assigns) do
  #   ~H"""
  #   {inspect(assigns)}
  #   """
  # end

  @impl true
  def handle_info(
        {:measurement,
         %{
           :payload => payload,
           :timestamp => timestamp,
           :attribute_id => attribute_id,
           :sensor_id => sensor_id
         } =
           _sensor_data},
        socket
      ) do
    # Buffer single measurements for throttled push
    measurement = %{
      :payload => payload,
      :timestamp => timestamp,
      :attribute_id => attribute_id,
      :sensor_id => sensor_id
    }

    # Update the LiveComponent immediately for UI responsiveness
    send_update(
      AttributeComponent,
      id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
      lastvalue: measurement
    )

    # Buffer measurement for throttled push to client (for JS charts)
    pending = [measurement | socket.assigns.pending_measurements]
    {:noreply, assign(socket, :pending_measurements, pending)}
  end

  @impl true
  def handle_info(
        {:measurements_batch, {sensor_id, measurements_list}},
        socket
      )
      when is_list(measurements_list) do
    # Get latest measurement per attribute for LiveComponent updates
    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attribute_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    # Update LiveComponents immediately for UI responsiveness
    Enum.each(latest_measurements, fn measurement ->
      send_update(
        AttributeComponent,
        id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
        lastvalue: measurement
      )
    end)

    # Buffer all measurements for throttled push to client (for JS charts)
    # Prepend batch (newer batch at front), reverse at flush for chronological order
    pending = measurements_list ++ socket.assigns.pending_measurements
    {:noreply, assign(socket, :pending_measurements, pending)}
  end

  @impl true
  def handle_info(
        {:new_state, _sensor_id},
        socket
      ) do
    Logger.debug("New state for sensor")

    # Handle case where sensor process may have been terminated
    try do
      new_sensor_state = SimpleSensor.get_view_state(socket.assigns.sensor_id)
      {:noreply, assign(socket, :sensor, new_sensor_state)}
    catch
      :exit, {:noproc, _} ->
        Logger.warning("Sensor #{socket.assigns.sensor_id} process not found during state update")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        :attributes_loaded,
        socket
      ) do
    {:noreply, socket |> assign(:attributes_loaded, true)}
  end

  # Handle sensor-level attention changes
  @impl true
  def handle_info(
        {:attention_changed, %{sensor_id: sensor_id, level: new_level}},
        %{assigns: %{sensor_id: sensor_id}} = socket
      ) do
    {:noreply, assign(socket, :attention_level, new_level)}
  end

  # Ignore attention changes for other sensors
  @impl true
  def handle_info({:attention_changed, _}, socket), do: {:noreply, socket}

  # Handle global view mode changes from parent pages
  # This allows the "All:" toggle button to update all sensor tiles without re-mounting
  @impl true
  def handle_info({:global_view_mode_changed, new_mode}, socket) do
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  # Throttled flush: push accumulated measurements to client in batches
  @impl true
  def handle_info(:flush_throttled_measurements, socket) do
    # Schedule next flush
    Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)

    case socket.assigns.pending_measurements do
      [] ->
        # Nothing to flush
        {:noreply, socket}

      measurements ->
        # Group by sensor_id (should all be the same, but be safe)
        sensor_id = socket.assigns.sensor_id

        # Sort by timestamp to ensure chronological order
        # (measurements may arrive in batches with mixed order due to prepend/concat)
        sorted_measurements = Enum.sort_by(measurements, & &1.timestamp)

        # Push single batch event with all measurements
        new_socket =
          socket
          |> push_event("measurements_batch", %{
            sensor_id: sensor_id,
            attributes: sorted_measurements
          })
          |> assign(:pending_measurements, [])

        {:noreply, new_socket}
    end
  end

  # defp list_to_map(list) do
  #   list
  #   |> Enum.group_by(& &1.attribute_id)
  #   |> Enum.map(fn {attribute_id, measurements} ->
  #     {attribute_id, Enum.max_by(measurements, & &1.timestamp)}
  #   end)
  #   |> Enum.into(%{})
  # end

  def handle_event("toggle_highlight", %{"sensor_id" => _sensor_id} = params, socket) do
    Logger.info(
      "Received toggle event: #{inspect(params)} Current: #{socket.assigns.highlighted}"
    )

    {:noreply,
     socket
     |> assign(:highlighted, not socket.assigns.highlighted)}
  end

  def handle_event("toggle_view_mode", _params, socket) do
    new_mode = if socket.assigns.view_mode == :normal, do: :summary, else: :normal
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  def handle_event("show_map_modal", _params, socket) do
    {:noreply, assign(socket, :show_map_modal, true)}
  end

  def handle_event("close_map_modal", _params, socket) do
    {:noreply, assign(socket, :show_map_modal, false)}
  end

  def handle_event("show_detail_modal", _params, socket) do
    {:noreply, assign(socket, :show_detail_modal, true)}
  end

  def handle_event("close_detail_modal", _params, socket) do
    {:noreply, assign(socket, :show_detail_modal, false)}
  end

  def handle_event("update-parameter", params, socket) do
    Logger.info("Test event #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event(
        "attribute_windowsize_changed",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id, "windowsize" => windowsize} =
          params,
        socket
      ) do
    Logger.info("Received windowsize event: #{inspect(params)}")

    {:noreply,
     socket
     |> assign(
       :sensors,
       update_in(
         socket.assigns.sensors,
         [sensor_id, :attributes, attribute_id, :windowsize],
         fn _ -> windowsize end
       )
     )}
  end

  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id} = params,
        socket
      ) do
    Logger.info("clear-attribute request #{inspect(params)}")

    {:noreply,
     push_event(socket, "clear-attribute", %{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       data: []
     })}

    # Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal", {:signal, %{test: 1}})
    # {:noreply, socket}
  end

  @impl true
  def handle_event(
        "request-seed-data",
        %{
          "sensor_id" => sensor_id,
          "attribute_id" => attribute_id,
          "from" => from,
          "to" => to,
          "limit" => limit
        } = _params,
        socket
      ) do
    start = System.monotonic_time()
    Logger.debug("request-seed_data #{sensor_id}:#{attribute_id}")

    attribute_data =
      Sensocto.SimpleSensor.get_attribute(sensor_id, attribute_id, from, to, limit)

    Logger.info("handle_event request-seed-data attribute_data: #{Enum.count(attribute_data)}")

    new_socket =
      socket
      |> push_event("seeddata", %{
        sensor_id: sensor_id,
        attribute_id: attribute_id,
        data: attribute_data
      })

    :telemetry.execute(
      [:sensocto, :live, :handle_event, :request_seed_data],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:noreply, new_socket}
  end

  # Handle incomplete request-seed-data events (missing sensor_id/attribute_id)
  @impl true
  def handle_event("request-seed-data", params, socket) do
    Logger.warning("Received incomplete request-seed-data event: #{inspect(params)}")
    {:noreply, socket}
  end

  # ============================================================================
  # Attention Tracking Events
  # ============================================================================

  @impl true
  def handle_event("view_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("view_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("focus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_focus(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  # Catch-all for malformed focus events (missing sensor_id or attribute_id)
  @impl true
  def handle_event("focus", _params, socket) do
    Logger.debug("Ignoring malformed focus event with missing sensor_id or attribute_id")
    {:noreply, socket}
  end

  @impl true
  def handle_event("unfocus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_focus(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  # Catch-all for malformed unfocus events
  @impl true
  def handle_event("unfocus", _params, socket) do
    Logger.debug("Ignoring malformed unfocus event with missing sensor_id or attribute_id")
    {:noreply, socket}
  end

  @impl true
  def handle_event("hover_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_hover(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("hover_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_hover(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("pin_sensor", %{"sensor_id" => sensor_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.pin_sensor(sensor_id, user_id)
    {:noreply, push_event(socket, "pin_state_changed", %{sensor_id: sensor_id, pinned: true})}
  end

  @impl true
  def handle_event("unpin_sensor", %{"sensor_id" => sensor_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unpin_sensor(sensor_id, user_id)
    {:noreply, push_event(socket, "pin_state_changed", %{sensor_id: sensor_id, pinned: false})}
  end

  @impl true
  def handle_event("page_hidden", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("page_visible", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "battery_state_changed",
        %{"state" => state_str, "level" => level, "charging" => charging} = params,
        socket
      ) do
    user_id = get_user_id(socket)

    # Convert string state to atom (validated set)
    battery_state =
      case state_str do
        "critical" -> :critical
        "low" -> :low
        _ -> :normal
      end

    # Determine source from params or default to :web_api
    source =
      case Map.get(params, "source") do
        "native_ios" -> :native_ios
        "native_android" -> :native_android
        "external_api" -> :external_api
        _ -> :web_api
      end

    Logger.debug(
      "Battery state changed for user #{user_id}: #{battery_state} (level: #{level}%, charging: #{charging}, source: #{source})"
    )

    AttentionTracker.report_battery_state(user_id, battery_state,
      source: source,
      level: level,
      charging: charging
    )

    {:noreply, assign(socket, :battery_state, battery_state)}
  end

  defp get_user_id(socket) do
    # Use socket id as user identifier, or current_user if available
    socket.id
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  def cleanup(entry) do
    case entry do
      {attribute_id, [entry]} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}

      {attribute_id, %{}} ->
        {attribute_id, entry}
    end
  end

  def show_sensor(js \\ %JS{}, id) do
    js
    |> JS.show(
      to: "##{id}",
      display: "inline-block",
      transition: {"ease-out duration-3000", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-content",
      display: "inline-block",
      transition:
        {"ease-out duration-3000", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end
end
