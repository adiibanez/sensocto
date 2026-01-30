defmodule SensoctoWeb.SensorLive.Show do
  use SensoctoWeb, :live_view

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.Live.Components.AttributeComponent

  require Logger

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @push_throttle_interval 100

  @impl true
  def mount(%{"id" => sensor_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}")
      Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)
    end

    sensor_state = get_sensor_state(sensor_id)
    rooms_containing_sensor = find_rooms_with_sensor(sensor_id)
    attention_level = AttentionTracker.get_sensor_attention_level(sensor_id)

    {:ok,
     socket
     |> assign(:page_title, sensor_state.sensor_name || sensor_id)
     |> assign(:sensor_id, sensor_id)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_name, sensor_state.sensor_name)
     |> assign(:sensor_type, sensor_state.sensor_type)
     |> assign(:attributes, sensor_state.attributes || %{})
     |> assign(:attention_level, attention_level)
     |> assign(:rooms, rooms_containing_sensor)
     |> assign(:view_mode, :normal)
     |> assign(:pending_measurements, [])
     |> assign(:pressed_buttons, %{})}
  end

  @impl true
  def handle_params(%{"id" => sensor_id}, _url, socket) do
    {:noreply,
     socket
     |> assign(:page_title, socket.assigns.sensor_name || sensor_id)}
  end

  @impl true
  def handle_info(
        {:measurement,
         %{
           payload: payload,
           timestamp: timestamp,
           attribute_id: "button" = attribute_id,
           sensor_id: sensor_id,
           event: event_type
         }},
        socket
      )
      when event_type in ["press", "release"] do
    button_id = payload
    current_pressed = Map.get(socket.assigns.pressed_buttons, attribute_id, MapSet.new())

    new_pressed =
      case event_type do
        "press" -> MapSet.put(current_pressed, button_id)
        "release" -> MapSet.delete(current_pressed, button_id)
      end

    pressed_buttons = Map.put(socket.assigns.pressed_buttons, attribute_id, new_pressed)

    measurement = %{
      payload: payload,
      timestamp: timestamp,
      attribute_id: attribute_id,
      sensor_id: sensor_id,
      event: event_type
    }

    send_update(
      AttributeComponent,
      id: "attribute_#{sensor_id}_#{attribute_id}",
      lastvalue: measurement,
      pressed_buttons: new_pressed
    )

    pending = [measurement | socket.assigns.pending_measurements]

    {:noreply,
     socket |> assign(:pending_measurements, pending) |> assign(:pressed_buttons, pressed_buttons)}
  end

  @impl true
  def handle_info(
        {:measurement,
         %{
           payload: payload,
           timestamp: timestamp,
           attribute_id: attribute_id,
           sensor_id: sensor_id
         }},
        socket
      ) do
    measurement = %{
      payload: payload,
      timestamp: timestamp,
      attribute_id: attribute_id,
      sensor_id: sensor_id
    }

    send_update(
      AttributeComponent,
      id: "attribute_#{sensor_id}_#{attribute_id}",
      lastvalue: measurement
    )

    pending = [measurement | socket.assigns.pending_measurements]
    {:noreply, assign(socket, :pending_measurements, pending)}
  end

  @impl true
  def handle_info(
        {:measurements_batch, {sensor_id, measurements_list}},
        socket
      )
      when is_list(measurements_list) do
    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attribute_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    Enum.each(latest_measurements, fn measurement ->
      send_update(
        AttributeComponent,
        id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
        lastvalue: measurement
      )
    end)

    pending = measurements_list ++ socket.assigns.pending_measurements
    {:noreply, assign(socket, :pending_measurements, pending)}
  end

  @impl true
  def handle_info({:attention_changed, %{sensor_id: sensor_id, level: new_level}}, socket)
      when sensor_id == socket.assigns.sensor_id do
    {:noreply, assign(socket, :attention_level, new_level)}
  end

  @impl true
  def handle_info({:attention_changed, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:flush_throttled_measurements, socket) do
    Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)

    case socket.assigns.pending_measurements do
      [] ->
        {:noreply, socket}

      measurements ->
        sensor_id = socket.assigns.sensor_id
        sorted_measurements = Enum.sort_by(measurements, & &1.timestamp)

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

  @impl true
  def handle_info({:new_state, _sensor_id}, socket) do
    try do
      new_sensor_state = SimpleSensor.get_view_state(socket.assigns.sensor_id)
      {:noreply, assign(socket, :sensor, new_sensor_state)}
    catch
      :exit, _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_view_mode", _params, socket) do
    new_mode = if socket.assigns.view_mode == :normal, do: :summary, else: :normal
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  @impl true
  def handle_event("view_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = socket.id
    AttentionTracker.register_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("view_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = socket.id
    AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("focus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = socket.id
    AttentionTracker.register_focus(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("unfocus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = socket.id
    AttentionTracker.unregister_focus(sensor_id, attr_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("request-seed-data", params, socket) do
    %{
      "sensor_id" => sensor_id,
      "attribute_id" => attribute_id,
      "from" => from,
      "to" => to,
      "limit" => limit
    } = params

    attribute_data =
      try do
        SimpleSensor.get_attribute(sensor_id, attribute_id, from, to, limit)
      catch
        :exit, _ -> []
      end

    new_socket =
      socket
      |> push_event("seeddata", %{
        sensor_id: sensor_id,
        attribute_id: attribute_id,
        data: attribute_data
      })

    {:noreply, new_socket}
  end

  @impl true
  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id},
        socket
      ) do
    {:noreply,
     push_event(socket, "clear-attribute", %{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       data: []
     })}
  end

  @impl true
  def handle_event(_, _, socket), do: {:noreply, socket}

  defp get_sensor_state(sensor_id) do
    try do
      SimpleSensor.get_view_state(sensor_id)
    catch
      :exit, _ ->
        %{
          sensor_id: sensor_id,
          sensor_name: sensor_id,
          sensor_type: "unknown",
          attributes: %{}
        }
    end
  end

  defp find_rooms_with_sensor(_sensor_id) do
    # TODO: Implement room-sensor association lookup
    # For now, return empty list as this feature requires room-sensor relationship tracking
    []
  end

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
      class={"flex items-center gap-1 text-sm #{@color_class}"}
      title={"Attention: #{@label} - affects data update frequency"}
    >
      <Heroicons.icon name={@icon_name} type="outline" class="h-4 w-4" />
      <span>{@label}</span>
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-4">
        <.link navigate={~p"/sensors"} class="text-gray-400 hover:text-white">
          <Heroicons.icon name="arrow-left" type="outline" class="h-6 w-6" />
        </.link>
        <div class="flex-1">
          <h1 class="text-2xl font-bold text-white">{@sensor_name}</h1>
          <p class="text-sm text-gray-400">{@sensor_type}</p>
        </div>
        <div class="flex items-center gap-3">
          <.attention_badge level={@attention_level} />
          <button
            phx-click="toggle_view_mode"
            class="px-3 py-1 text-sm bg-gray-700 text-gray-300 rounded hover:bg-gray-600"
          >
            {if @view_mode == :normal, do: "Summary", else: "Normal"}
          </button>
        </div>
      </div>

      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <h2 class="text-lg font-medium text-white mb-4">Sensor Information</h2>
        <dl class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <dt class="text-sm text-gray-400">Sensor ID</dt>
            <dd class="text-sm text-white font-mono truncate" title={@sensor_id}>{@sensor_id}</dd>
          </div>
          <div>
            <dt class="text-sm text-gray-400">Type</dt>
            <dd class="text-sm text-white">{@sensor_type}</dd>
          </div>
          <div>
            <dt class="text-sm text-gray-400">Attributes</dt>
            <dd class="text-sm text-white">{map_size(@attributes)}</dd>
          </div>
          <div>
            <dt class="text-sm text-gray-400">Attention Level</dt>
            <dd class="text-sm"><.attention_badge level={@attention_level} /></dd>
          </div>
        </dl>
      </div>

      <div :if={@rooms != []} class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <h2 class="text-lg font-medium text-white mb-3">Rooms containing this sensor</h2>
        <div class="flex flex-wrap gap-2">
          <.link
            :for={room <- @rooms}
            navigate={~p"/rooms/#{room.id}"}
            class="inline-flex items-center px-3 py-1 rounded-full bg-gray-700 text-gray-300 hover:bg-gray-600 text-sm"
          >
            <Heroicons.icon name="building-office" type="outline" class="h-4 w-4 mr-1" />
            {room.name}
          </.link>
        </div>
      </div>

      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <h2 class="text-lg font-medium text-white mb-4">Attributes</h2>

        <div :if={@attributes == %{}} class="text-center py-8">
          <Heroicons.icon name="chart-bar" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
          <p class="mt-2 text-sm text-gray-400">No attributes available</p>
        </div>

        <div :if={@attributes != %{}} class="space-y-4">
          <.live_component
            :for={{attribute_id, attribute} <- @attributes}
            id={"attribute_#{@sensor_id}_#{attribute_id}"}
            attribute_type={@sensor_type}
            module={AttributeComponent}
            attribute={attribute}
            sensor_id={@sensor_id}
            view_mode={@view_mode}
          />
        </div>
      </div>
    </div>
    """
  end
end
