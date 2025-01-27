defmodule SensoctoWeb.IndexLive do
  alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.Live.Components.ViewData

  alias SensoctoWeb.Components.SensorTypes.{
    EcgSensorComponent,
    GenericSensorComponent,
    HeartrateComponent,
    HighSamplingRateSensorComponent
  }

  # https://dev.to/ivor/how-to-unsubscribe-from-all-topics-in-phoenixpubsub-dka
  # https://hexdocs.pm/phoenix_live_view/bindings.html#js-commands

  @impl true
  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensordata:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    # presence tracking

    {:ok,
     socket
     |> assign(
       sensors_online: %{},
       sensors_offline: %{},
       stream_div_class: ""
     )
     |> assign_async(:sensors, fn ->
       {:ok,
        %{
          :sensors =>
            Sensocto.SensorsDynamicSupervisor.get_all_sensors_state()
            |> ViewData.generate_view_data()
        }}
     end)
     |> stream(:sensor_data, [])}
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="status" class="hidden" phx-disconnected={JS.show()} phx-connected={JS.hide()}>
      Attempting to reconnect...
    </div>

    <!--<div id="test-scichart">
      <sensocto-testchart class="resizeable" />
    </div>-->

    <div>
      {inspect(assigns.sensors.result)}
    </div>

    <div id="cnt" phx-hook="ConnectionHandler" class="flex-none md:flex-1">
      <.async_result :let={sensors} assign={@sensors}>
        <:loading>Loading Sensor data ...</:loading>
        <:failed :let={reason}>{reason}</:failed>

        <div class={assigns.stream_div_class}>
          <div :for={{id, sensor} <- sensors}>
            <div
              :if={is_nil(sensor.viewdata) || sensor.viewdata |> Map.size() == 0}
              class="bg-gray-800 text-xs m-0 p-1"
            >
              <div class="m-0 p-2">
                <p class="font-bold text-s">
                  {sensor.metadata.sensor_name}
                </p>
                <p>Type: {sensor.metadata.sensor_type}</p>
                <p class="text-xs hidden">Conn: {sensor.metadata.connector_name}</p>
              </div>

              <svg
                aria-hidden="true"
                class="w-8 h-8 text-gray-200 animate-spin dark:text-gray-600 fill-blue-600"
                viewBox="0 0 100 101"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
                  fill="currentColor"
                />
                <path
                  d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
                  fill="currentFill"
                />
              </svg>
            </div>
            <div
              :for={{id, attribute_data} <- sensor.viewdata}
              id={attribute_data.id}
              class="bg-gray-800 text-xs m-0 p-1"
              phx-hook="SensorDataAccumulator"
              data-sensor_id={attribute_data.sensor_id}
              data-attribute_id={attribute_data.attribute_id}
              data-sensor_type={attribute_data.sensor_type}
              phx-hook="SensorDataAccumulator"
              data-append={attribute_data.append_data}
            >
              {render_sensor_by_type(attribute_data, sensor.metadata)}
            </div>
          </div>
        </div>
        
    <!--<p class="text-xs">Online: {inspect(@sensors_online)}</p>
        <p class="text-xs">Offline: {inspect(@sensors_offline)}</p>-->
      </.async_result>
    </div>
    <%= if @sensors_offline != %{} do %>
      <div>
        <p class="text font-bold mt-8 mb-2">Recently disconnected sensors</p>
        <ul class="list-disc list-inside ml-4">
          <%= for sensor_id <- Map.keys(@sensors_offline) do %>
            <li>{sensor_id}</li>
          <% end %>
        </ul>
      </div>
    <% end %>
    <div
      id="toolbar"
      class="bg-gray-800 p-4 rounded-lg fixed bottom-0 right-0 w-64 max-h-[80%] overflow-y-auto"
    >
      {live_render(@socket, SensoctoWeb.SenseLive,
        id: "bluetooth",
        session: %{"parent_id" => self()}
      )}
    </div>
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
       when sensor_type in ["ecg"] do
    component_id = "live-#{sensor_data.id}"

    ~H"""
    <.live_component id={component_id} module={EcgSensorComponent} sensor_data={sensor_data} />
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
       when sensor_type in ["pressure", "flex", "eda", "emg", "rsp"] do
    component_id = "sensorviz-#{sensor_data.id}"

    ~H"""
    <.live_component
      id={component_id}
      module={HighSamplingRateSensorComponent}
      sensor_data={sensor_data}
    />
    """
  end

  defp render_sensor_by_type(%{sensor_type: "heartrate"} = sensor_data, assigns) do
    component_id = "sensorviz-#{sensor_data.id}"

    ~H"""
    <.live_component id={component_id} module={HeartrateComponent} sensor_data={sensor_data} />
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns) do
    component_id = "sensorviz-#{sensor_data.id}"

    ~H"""
    <.live_component id={component_id} module={GenericSensorComponent} sensor_data={sensor_data} />
    """
  end

  defp render_sensor_by_type(sensor_data, assigns) do
    ~H"""
    <div>Unknown sensor_type {sensor_data}</div>
    """
  end

  def handle_info(
        {:measurement,
         %{
           :payload => payload,
           :timestamp => timestamp,
           :uuid => uuid,
           :sensor_id => sensor_id
         } =
           sensor_data},
        socket
      ) do
    IO.inspect(sensor_data, label: "Received measurement data:")

    existing_data = socket.assigns.sensors.result

    {:noreply,
     socket
     |> assign_async(:sensors, fn ->
       {:ok,
        %{
          :sensors => ViewData.merge_sensor_data(existing_data, sensor_data)
        }}
     end)}
  end

  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id} = params,
        socket
      ) do
    Logger.debug("clear-attribute request #{inspect(params)}")
    # IO.puts("request-seed_data #{sensor_id}")
    # {:noreply, push_event(socket, "scores", %{points: 100, user: "josé"})}

    attribute_data = Sensocto.SimpleSensor.clear_attribute(sensor_id, attribute_id)
    IO.inspect(attribute_data)

    {:noreply,
     push_event(socket, "seeddata", %{
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
        %{"id" => sensor_id, "attribute_id" => attribute_id},
        socket
      ) do
    IO.puts("request-seed_data #{sensor_id}:#{attribute_id}")
    # {:noreply, push_event(socket, "scores", %{points: 100, user: "josé"})}

    attribute_data = Sensocto.SimpleSensor.get_attribute(sensor_id, attribute_id, 10000)

    Logger.debug(
      "Seed data available for attribute #{sensor_id}:#{attribute_id}, #{inspect(attribute_data)}}"
    )

    {:noreply,
     push_event(socket, "seeddata", %{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       data: attribute_data
     })}

    # Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal", {:signal, %{test: 1}})
    # {:noreply, socket}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          # topic: "sensordata:all",
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    Logger.debug("presence #{inspect(payload)}")
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

    sensors_online_count = min(2, Enum.count(sensors_online))

    div_class =
      "grid gap-2 grid-cols-1 md:grid-cols-" <>
        Integer.to_string(min(2, sensors_online_count)) <>
        " lg:grid-cols-" <>
        Integer.to_string(min(4, sensors_online_count))

    # div_class =
    #   "grid gap-2 grid-cols-4 sd:grid-cols-1 md:grid-cols-2 lg:grid-cols-4"

    socket_to_return =
      Enum.reduce(payload.leaves, socket, fn {id, metas}, socket ->
        sensor_dom_id = "sensor_data-" <> ViewData.sanitize_sensor_id(id)
        stream_delete_by_dom_id(socket, :sensor_data, sensor_dom_id)
      end)

    {
      :noreply,
      socket_to_return
      |> assign(:sensors_online, sensors_online)
      |> assign(:sensors_offline, payload.leaves)
      |> assign(:stream_div_class, div_class)
      |> assign_async(:sensors, fn ->
        {:ok,
         %{
           :sensors =>
             Sensocto.SensorsDynamicSupervisor.get_all_sensors_state()
             |> ViewData.generate_view_data()
         }}
      end)
    }
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Handled message {__MODULE__}")

    {:noreply,
     socket
     |> put_flash(:info, "You clicked the button!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  @impl true
  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Unknown Message")
    {:noreply, socket}
  end

  # Define a map for UUID to human-readable names
  defp sensor_name_for_uuid(uuid) do
    case uuid do
      "61d20a90-71a1-11ea-ab12-0800200c9a66" -> "Pressure"
      "00002a37-0000-1000-8000-00805f9b34fb" -> "Heart Rate"
      "feb7cb83-e359-4b57-abc6-628286b7a79b" -> "Flexsense"
      "00002a19-0000-1000-8000-00805f9b34fb" -> "Battery"
      # Default for unknown UUIDs
      _ -> uuid
    end
  end
end
