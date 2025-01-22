defmodule SensoctoWeb.IndexLive do
  alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components

  alias SensoctoWeb.Components.SensorTypes.{
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
     |> stream(:sensor_data, [])}
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="status" class="hidden" phx-disconnected={JS.show()} phx-connected={JS.hide()}>
      Attempting to reconnect...
    </div>
    <div>
      <div id="sensors" phx-update="stream" class={assigns.stream_div_class}>
        <div class="only:block hidden">
          <p>No sensors online</p>
        </div>
        <div
          :for={{id, sensor_data} <- @streams.sensor_data}
          id={id}
          class="bg-gray-800 text-xs m-0 p-1"
          phx-hook="SensorDataAccumulator"
          data-sensorid={sensor_data.id}
          data-sensorid_raw={sensor_data.sensor_id}
          data-append={sensor_data.append_data}
          class="m-0 p-0"
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
      class="bg-gray-800 p-4 rounded-lg fixed bottom-0 right-0 w-64 max-h-[50%] overflow-y-auto"
    >
      {live_render(@socket, SensoctoWeb.SenseLive,
        id: "bluetooth",
        session: %{"parent_id" => self()}
      )}
    </div>
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns)
       when sensor_type in ["ecg", "pressure", "flex", "eda", "emg", "rsp"] do
    ~H"""
    <.live_component
      id={"live-" <> sensor_data.sensor_id}
      module={HighSamplingRateSensorComponent}
      sensor_data={sensor_data}
    />
    """
  end

  defp render_sensor_by_type(%{sensor_type: "heartrate"} = sensor_data, assigns) do
    ~H"""
    <.live_component
      id={"live-" <> sensor_data.sensor_id}
      module={HeartrateComponent}
      sensor_data={sensor_data}
    />
    """
  end

  defp render_sensor_by_type(%{sensor_type: sensor_type} = sensor_data, assigns) do
    ~H"""
    <.live_component
      id={"live-" <> sensor_data.sensor_id}
      module={GenericSensorComponent}
      sensor_data={sensor_data}
    />
    """
  end

  defp render_sensor_by_type(sensor_data, assigns) do
    ~H"""
    <div>Unknown sensor_type {sensor_data}</div>
    """
  end

  @impl true
  def handle_event(
        "request-seed-data",
        %{"id" => sensor_id, "attribute_id" => attribute_id},
        socket
      ) do
    IO.puts("request-seed_data #{sensor_id}")
    {:noreply, push_event(socket, "scores", %{points: 100, user: "josé"})}

    case Sensocto.SimpleSensor.get_attribute(sensor_id, attribute_id, 10000) do
      attribute_data ->
        # IO.inspect(attribute_data, label: " SimpleSensor data received")

        {:noreply,
         push_event(socket, "seeddata", %{
           sensor_id: sensor_id,
           attribute_id: attribute_id,
           data: attribute_data
         })}

      _ ->
        Logger.error("Seed data SimpleSensor data error")
        {:noreply, put_flash(socket, :error, "SimpleSensor data error")}
    end

    # Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal", {:signal, %{test: 1}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("signal", _, socket) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal", {:signal, %{test: 1}})
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}, socket) do
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

    sensors_online_count = min(2, Enum.count(sensors_online))

    div_class =
      "grid gap-2 grid-cols-1 md:grid-cols-" <>
        Integer.to_string(min(2, sensors_online_count)) <>
        " lg:grid-cols-" <>
        Integer.to_string(min(4, sensors_online_count))

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
  def handle_info(
        {:measurement,
         %{
           "payload" => payload,
           "timestamp" => timestamp,
           "uuid" => _uuid,
           "sensor_id" => sensor_id,
           "sensor_params" => sensor_params
         } =
           sensor_data},
        socket
      ) do
    # IO.inspect(sensor_data)

    # case SimpleSensor.get_attributes(sensor_id) do
    #  attributes ->
    #    IO.inspect(attributes, label: " SimpleSensor data received")

    ##    {:noreply, socket}
    #  {:error, _} ->
    #    {:noreply, put_flash(socket, :error, "SimpleSensor data error")}
    # end

    updated_sensor =
      %{
        # liveview streams id, remove : for document.querySelector compliance
        id: sanitize_sensor_id(sensor_id),
        payload: payload,
        timestamp: timestamp,
        timestamp_formated: DateTime.from_unix!(timestamp, :millisecond) |> DateTime.to_string(),
        sensor_id: sensor_params["sensor_id"],
        sensor_name: sensor_params["sensor_name"],
        sensor_type: sensor_params["sensor_type"],
        connector_id: sensor_params["connector_id"],
        connector_name: sensor_params["connector_name"],
        sampling_rate: sensor_params["sampling_rate"],
        append_data:
          "{\"timestamp\": #{sensor_data["timestamp"]}, \"value\": #{sensor_data["payload"]}}"
      }

    # |> Map.update(
    #  :append_data,
    #  "{\"timestamp\": #{sensor_data["timestamp"]}, \"value\": #{sensor_data["payload"]}}",
    #  fn existing_value -> existing_value end
    # )

    {:noreply, stream_insert(socket, :sensor_data, updated_sensor)}
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

  defp sanitize_sensor_id(sensor_id) do
    String.replace(String.replace(sensor_id, ":", "_"), " ", "_")
  end
end
