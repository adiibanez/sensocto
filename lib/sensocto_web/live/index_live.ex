defmodule SensoctoWeb.IndexLive do
  alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.Live.Components.ViewData
  import SensoctoWeb.Live.BaseComponents

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

  # @impl true
  # @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  #   #render_with(socket)
  # end

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
    # IO.inspect(sensor_data, label: "Received measurement data:")

    existing_data = socket.assigns.sensors.result

    # update client
    measurement = %{
      :payload => payload,
      :timestamp => timestamp,
      :attribute_id => uuid,
      :sensor_id => sensor_id
    }

    {:noreply,
     socket
     |> assign_async(:sensors, fn ->
       {:ok,
        %{
          :sensors => ViewData.merge_sensor_data(existing_data, sensor_data)
        }}
     end)
     |> push_event("measurement", measurement)}
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
    # IO.inspect(attribute_data)

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
