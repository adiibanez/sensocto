defmodule SensoctoWeb.IndexLive do
  alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components

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
            Sensocto.SensorsDynamicSupervisor.get_all_sensors_state() |> generate_view_data()
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
    <div id="cnt" phx-hook="ConnectionHandler" class="flex-none md:flex-1">
      <div id="test-sensors">
        <.async_result :let={sensors} assign={@sensors}>
          <:loading>Loading Sensor data ...</:loading>
          <:failed :let={reason}>{reason}</:failed>
          <p>Online: {inspect(@sensors_online)}</p>
          <hr />
          <p>Offline: {inspect(@sensors_offline)}</p>
          <hr />

          {inspect(sensors)}

          <div :for={{id, sensor} <- sensors}>
            Sensor ID: {id} <br />
            {inspect(sensor)}
            
    <!--<div
              :for={{id, attribute_data} <- sensor.viewdata}
              id={id}
              class="bg-gray-800 text-xs m-0 p-1"
              phx-hook="SensorDataAccumulator"
              data-sensorid={attribute_data.sensor_id}
              data-sensortype={attribute_data.sensor_type}
              data-sensorid_raw={"#{attribute_data.sensor_id}"}
            >
              {render_sensor_by_type(attribute_data, sensor.metadata)}
            </div>-->
          </div>
          
    <!--<div :for={sensor_map <- sensors} style="border:1px solid white">
            <div :for={{id, sensor} <- sensor_map}>
              Sensor ID: {id} <br />
              {inspect(sensor)}
            </div>
          </div>-->

    <!--<div
            :for={{id, sensor} <- @sensors.result}
            id={"test_sensor_#{id}"}
            class="bg-gray-800 text-xs m-0 p-1"
          >
            {inspect(sensor)}
          </div>-->

    <!--<span :if={user}>{user.email}</span>-->
        </.async_result>
      </div>

      <div style="display:hidden" id="sensors" phx-update="stream" class={assigns.stream_div_class}>
        <div id="no-sensors" phx-update="ignore" class="only_:block hidden">
          <p>No sensors online</p>
        </div>
        <div
          :for={{id, sensor_data} <- @streams.sensor_data}
          id={id}
          class="bg-gray-800 text-xs m-0 p-1"
          phx-hook="SensorDataAccumulator"
          data-sensorid={sensor_data.id}
          data-sensortype={sensor_data.sensor_type}
          data-sensorid_raw={"#{sensor_data.sensor_id}"}
          data-append={sensor_data.append_data}
        >
          {render_sensor_by_type(sensor_data, assigns)}
        </div>
      </div>
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
    component_id = "live-#{sensor_data.sensor_id}"

    ~H"""
    <.live_component id={component_id} module={EcgSensorComponent} sensor_data={sensor_data} />
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
       when sensor_type in ["pressure", "flex", "eda", "emg", "rsp"] do
    component_id = "live-#{sensor_data.sensor_id}"

    ~H"""
    <.live_component
      id={component_id}
      module={HighSamplingRateSensorComponent}
      sensor_data={sensor_data}
    />
    """
  end

  defp render_sensor_by_type(%{sensor_type: "heartrate"} = sensor_data, assigns) do
    component_id = "live-#{sensor_data.sensor_id}"

    ~H"""
    <.live_component id={component_id} module={HeartrateComponent} sensor_data={sensor_data} />
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns) do
    component_id = "live-#{sensor_data.sensor_id}"

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
    # IO.inspect(sensor_data, label: "Received measurement data:")

    # IO.inspect(socket.assigns.sensors.result, label: "Existing sensors async_assign data")

    existing_data = Map.get(socket.assigns.sensors, :result, %{})
    IO.inspect(existing_data, label: "Existing sensors async_assign data")

    new_data_updated = update_sensor_data(existing_data, sensor_data)
    IO.inspect(new_data_updated, label: "Existing sensors async_assign data")
    new_data = Map.merge(new_data_updated, socket.assigns.sensors.result)

    IO.inspect(new_data, label: "New data")

    new_data_async_assign =
      Map.merge(%{"#{sensor_id}" => generate_sensor_view_data(sensor_id, sensor_data)}, new_data)

    IO.inspect(
      new_data_async_assign,
      label: "New sensors async_assign data"
    )

    # new_data =
    #   Map.merge(
    #     existing_data,

    #   )

    # IO.inspect(new_data, label: "New sensors async_assign data")

    # {:noreply,
    #  socket
    #  |> assign_async(:sensors, fn ->
    #    {:ok,
    #     %{
    #       :sensors => new_data_async_assign
    #     }}
    #  end)}

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Unknown Message")
    {:noreply, socket}
  end

  # @spec handle_info(any(), any()) :: {:noreply, any()}
  # def handle_info(
  #       {:measurement,
  #        %{
  #          :payload => _payload,
  #          :timestamp => _timestamp,
  #          :uuid => _uuid,
  #          :sensor_id => _sensor_id
  #        } =
  #          sensor_data},
  #       socket
  #     ) do
  #   Logger.debug("Received TEST measurement: #{inspect(sensor_data)}")
  #   {:noreply, socket}
  # end

  # def handle_info(
  #       {:measurement,
  #        %{
  #          "payload" => payload,
  #          "timestamp" => timestamp,
  #          "uuid" => _uuid,
  #          "sensor_id" => sensor_id
  #        } =
  #          sensor_data},
  #       socket
  #     ) do
  #   Logger.debug("Received measurement: #{inspect(sensor_data)}")
  #   {:noreply, socket}
  # end

  # @spec handle_info(any(), any()) :: {:noreply, any()}
  # def handle_info({:measurement, sensor_data}, socket) do
  #   IO.inspect(sensor_data, label: "Received in LiveView")

  #   key_types =
  #     sensor_data
  #     |> Map.keys()
  #     |> Enum.map(fn key ->
  #       case key do
  #         key when is_atom(key) -> {key, :atom}
  #         key when is_binary(key) -> {key, :binary}
  #         key -> {key, :other}
  #       end
  #     end)

  #   Enum.each(key_types, fn {key, type} ->
  #     IO.inspect({key, type}, label: "Key type")
  #   end)

  #   {:noreply, socket}
  # end

  # def handle_info(
  #       {:measurement,
  #        %{
  #          :payload => payload,
  #          :timestamp => timestamp,
  #          :uuid => _uuid,
  #          :sensor_id => sensor_id
  #        } =
  #          sensor_data},
  #       socket
  #     ) do
  #   Logger.debug("Received measurement: #{inspect(sensor_data)}")

  #   # existing_data = socket.assigns.sensors.result

  #   # IO.inspect(existing_data)
  #   # IO.inspect(update_sensor_data(existing_data, sensor_data))
  #   {:noreply, socket}

  #   # {:noreply,
  #   #  socket
  #   #  |> assign_async(:sensors, fn ->
  #   #    {:ok,
  #   #     %{
  #   #       :sensors =>
  #   #         #existing_data
  #   #         # |> update_sensor_data(sensor_data)
  #   #         |> generate_view_data()
  #   #     }}
  #   #  end)}

  #   # {:noreply, update_sensors(socket, sensor_data, :update)}
  # end

  # def handle_info(
  #       {:measurement,
  #        %{
  #          "payload" => payload,
  #          "timestamp" => timestamp,
  #          "uuid" => _uuid,
  #          "sensor_id" => sensor_id
  #        } =
  #          sensor_data},
  #       socket
  #     ) do
  #   Logger.debug("handle_info2 Received measurement: #{inspect(sensor_data)}")
  #   # {:noreply, update_sensors(socket, sensor_data, :update)}
  #   {:noreply, socket}

  #   # {:noreply,
  #   #  socket
  #   #  |> assign_async(:sensors, fn ->
  #   #    {:ok,
  #   #     %{
  #   #       :sensors =>
  #   #         #existing_data
  #   #         # |> update_sensor_data(sensor_data)
  #   #         |> generate_view_data()
  #   #     }}
  #   #  end)}

  #   # {:noreply, update_sensors(socket, sensor_data, :update)}
  # end

  # # def handle_info(event, socket) do
  # #  IO.puts("handle_info CATCHALL event: #{inspect(event)}")
  # #  {:noreply, socket}
  # # end

  defp update_sensor_data(sensors, sensor_data) do
    sensor_id = Map.get(sensor_data, :sensor_id)
    sensor_id_string = to_string(sensor_id)

    Enum.reduce(sensors, %{}, fn sensor, acc ->
      case Map.get(acc, sensor_id_string) do
        nil ->
          Map.put(acc, sensor_id_string, %{
            attributes: %{
              Map.get(sensor_data, :uuid) => [
                %{
                  timestamp: Map.get(sensor_data, :timestamp),
                  payload: Map.get(sensor_data, :payload)
                }
              ]
            }
          })

        existing_sensor ->
          updated_sensor =
            Map.update(existing_sensor, :attributes, fn attributes ->
              Map.put(attributes, Map.get(sensor_data, :uuid), [
                %{
                  timestamp: Map.get(sensor_data, :timestamp),
                  payload: Map.get(sensor_data, :payload)
                }
              ])
            end)

          Map.put(acc, sensor_id_string, updated_sensor)
      end
    end)
  end

  defp update_view_data(sensors, sensor_id, attribute_id) do
    sensor_id_string = to_string(sensor_id)

    Enum.reduce(sensors, %{}, fn {key, value}, acc ->
      if key == sensor_id_string do
        updated_sensor =
          Map.put(value, :viewdata, generate_sensor_view_data(key, value))

        Map.put(acc, key, updated_sensor)
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp update_sensor(sensors, attribute_update) do
    sensor_id_string =
      attribute_update
      |> Map.get("sensor_id", Map.get(attribute_update, :sensor_id))
      |> to_string()

    Enum.map(sensors, fn sensor ->
      case Map.get(sensor, sensor_id_string) do
        nil ->
          sensor

        sensor_data ->
          updated_attributes =
            sensor_data
            |> Map.get(:attributes, %{})
            |> Map.update(
              Map.get(attribute_update, :attribute_id),
              fn attribute_values ->
                [Map.drop(attribute_update, [:attribute_id, :sensor_id]) | attribute_values]
              end,
              [Map.drop(attribute_update, [:attribute_id, :sensor_id])]
            )

          Map.put(sensor, sensor_id_string, Map.put(sensor_data, :attributes, updated_attributes))
      end
    end)
  end

  defp update_view_data(socket) do
    socket
    |> assign(
      :sensors,
      socket.assigns.sensors
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        Map.put(
          acc,
          key,
          Map.put(value, :viewdata, generate_sensor_view_data(key, value))
        )
      end)
    )
  end

  alias Timex.DateTime
  import String, only: [replace: 3]

  def generate_view_data(sensors) when is_map(sensors) do
    sensors
    |> Enum.reduce(%{}, fn {sensor_id, sensor_data}, acc ->
      view_data = generate_sensor_view_data(sensor_id, sensor_data)
      Map.put(acc, sensor_id, Map.put(sensor_data, :viewdata, view_data))
    end)
  end

  defp generate_sensor_view_data(sensor_id, sensor_data) do
    metadata = Map.get(sensor_data, :metadata, %{})
    attributes = Map.get(sensor_data, :attributes, %{})

    Enum.reduce(attributes, %{}, fn {attribute_id, attribute_values}, acc ->
      view_data = generate_single_view_data(sensor_id, attribute_id, attribute_values, metadata)
      Map.put(acc, attribute_id, view_data)
    end)
  end

  defp generate_single_view_data(sensor_id, attribute_id, attribute_values, metadata) do
    attribute_values
    |> Enum.reduce(%{}, fn attribute_value, _acc ->
      timestamp = Map.get(attribute_value, :timestamp)

      timestamp_formatted =
        try do
          case timestamp do
            nil ->
              "Invalid Date"

            timestamp ->
              timestamp
              |> Kernel./(1000)
              |> Timex.from_unix()
              |> Timex.to_string()
          end
        rescue
          _ ->
            "Invalid Date"
        end

      %{
        # liveview streams id, remove : for document.querySelector compliance
        id: sanitize_sensor_id(sensor_id),
        payload: Map.get(attribute_value, :payload),
        timestamp: timestamp,
        timestamp_formated: timestamp_formatted,
        attribute_id: attribute_id,
        sensor_id: Map.get(metadata, :sensor_id),
        sensor_name: Map.get(metadata, :sensor_name),
        sensor_type: Map.get(metadata, :sensor_type),
        connector_id: Map.get(metadata, :connector_id),
        connector_name: Map.get(metadata, :connector_name),
        sampling_rate: Map.get(metadata, :sampling_rate),
        append_data:
          ~s|{"timestamp": #{timestamp}, "payload": #{Jason.encode!(Map.get(attribute_value, :payload))}}|
      }
    end)
  end

  def sanitize_sensor_id(sensor_id) when is_binary(sensor_id) do
    replace(sensor_id, ":", "_")
  end

  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id} = _params,
        socket
      ) do
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
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}, socket) do
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

    sensors_online_count = min(2, Enum.count(sensors_online))

    # div_class =
    #   "grid gap-2 grid-cols-1 md:grid-cols-" <>
    #     Integer.to_string(min(2, sensors_online_count)) <>
    #     " lg:grid-cols-" <>
    #     Integer.to_string(min(4, sensors_online_count))

    div_class =
      "grid gap-2 grid-cols-4 sd:grid-cols-1 md:grid-cols-2 lg:grid-cols-4"

    socket_to_return =
      Enum.reduce(payload.leaves, socket, fn {id, metas}, socket ->
        sensor_dom_id = "sensor_data-" <> sanitize_sensor_id(id)
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
             Sensocto.SensorsDynamicSupervisor.get_all_sensors_state() |> generate_view_data()
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

  # Catch-all for unmatched messages
  @impl true
  def handle_info(_msg, socket) do
    # IO.inspect(msg, label: "Unhandled message")
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
