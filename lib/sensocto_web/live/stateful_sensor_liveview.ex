defmodule SensoctoWeb.StatefulSensorLiveview do
  use SensoctoWeb, :live_view
  # LVN_ACTIVATION use SensoctoNative, :live_view
  import Phoenix.LiveView

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.Live.Components.AttributeComponent
  import SensoctoWeb.Live.BaseComponents

  require Logger

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
  def mount(_params, %{"parent_pid" => parent_pid, "sensor" => sensor}, socket) do
    # send_test_event()
    # Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor.sensor_id}")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor.sensor_id}")
    # Subscribe to attention changes for this sensor
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor.sensor_id}")

    # https://www.richardtaylor.dev/articles/beautiful-animated-charts-for-liveview-with-echarts
    # https://echarts.apache.org/examples/en/index.html#chart-type-flowGL

    sensor_state =
      SimpleSensor.get_view_state(sensor.sensor_id)

    # Get initial attention level
    initial_attention =
      try do
        AttentionTracker.get_sensor_attention_level(sensor.sensor_id)
      catch
        :exit, {:noproc, _} -> :none
      end

    {:ok,
     socket
     |> assign(:parent_pid, parent_pid)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_state.sensor_id)
     |> assign(:sensor_name, sensor_state.sensor_name)
     |> assign(:sensor_type, sensor_state.sensor_type)
     |> assign(:highlighted, false)
     |> assign(:attention_level, initial_attention)
     |> assign(
       :attributes_loaded,
       true
     )}
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
    start = System.monotonic_time()

    Logger.debug("Received single measurement for sensor #{sensor_id}")

    # update client
    measurement = %{
      :payload => payload,
      :timestamp => timestamp,
      :attribute_id => attribute_id,
      :sensor_id => sensor_id
    }

    # measurement |> dbg()

    # send_update is already non-blocking, no need to spawn Tasks
    send_update(
      AttributeComponent,
      id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
      lastvalue: measurement
    )

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    # Note: Using string keys for attribute_id to prevent atom exhaustion
    # The attribute_id is already validated at the channel boundary
    _merged_attributes =
      Map.merge(socket.assigns.sensor.attributes, %{
        measurement.attribute_id => measurement
      })

    new_socket =
      socket
      |> push_event("measurement", measurement)

    {:noreply, new_socket}

    # {
    #   :noreply,
    #   socket
    #   |> push_event("measurement", measurement)
    #   |> assign(
    #     :sensor,
    #     update_in(
    #       socket.assigns.sensor,
    #       [:attributes],
    #       fn _ -> Map.merge(socket.assigns.sensor.attributes, measurement) end
    #     )
    #   )
    # }
  end

  @impl true
  def handle_info(
        {:measurements_batch, {sensor_id, measurements_list}},
        socket
      )
      when is_list(measurements_list) do
    start = System.monotonic_time()

    Logger.debug("Received measurements_batch for sensor #{sensor_id}")

    new_socket =
      socket
      # |> assign(:sensors, updated_data)
      |> push_event("measurements_batch", %{
        :sensor_id => sensor_id,
        :attributes => measurements_list
      })

    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attribute_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    new_attributes =
      latest_measurements
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {attribute_id, measurements} ->
        {attribute_id, Enum.max_by(measurements, & &1.timestamp)}
      end)
      |> Enum.into(%{})

    # |> Sensocto.Utils.string_keys_to_atom_keys()

    Map.merge(socket.assigns.sensor.attributes, new_attributes)

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement_batch],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    # send_update is already non-blocking, no need to spawn Tasks
    Enum.each(latest_measurements, fn measurement ->
      send_update(
        AttributeComponent,
        id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
        lastvalue: measurement
      )
    end)

    {:noreply, new_socket}

    # {:noreply,
    #  new_socket
    #  |> assign(
    #    :sensor,
    #    update_in(
    #      socket.assigns.sensor,
    #      [:attributes],
    #      fn _ -> Map.merge(socket.assigns.sensor.attributes, new_attributes) end
    #    )
    #  )}
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

  @impl true
  def handle_event("unfocus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_focus(sensor_id, attr_id, user_id)
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
