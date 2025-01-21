defmodule SensoctoWeb.IndexLive do
  use SensoctoWeb, :live_view
  require Logger

  # https://dev.to/ivor/how-to-unsubscribe-from-all-topics-in-phoenixpubsub-dka

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
       sensors_offline: %{}
     )
     |> stream(:sensor_data, [])}
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <div
        id="sensors"
        phx-update="stream"
        class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-4"
      >
        <div
          :for={{id, sensor_data} <- @streams.sensor_data}
          id={id}
          class="bg-gray-800 p-6 rounded text-xs"
          phx-hook="SensorDataAccumulator"
        >
          <p class="font-bold">{sensor_data.sensor_name}</p>
          <p class="mt-2">
            <span id={"source_#{sensor_data.sensor_id}"}>
              {sensor_data.payload}
            </span>
          </p>
          <p class="text-sm text-gray-500">{sensor_data.timestamp}</p>

          <div role="status" phx-update="ignore" id={ "loading-" <> id }>
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
            <span class="sr-only">Loading...</span>
          </div>

          <div
            id={ "sparkline-disable-" <> id }
            class="sparkline hidden"
            phx-update="ignore"
            data-append={sensor_data.append_data}
            data-maxlength="200"
            data-color-stroke="#ffc107"
            data-color-filled="#ffc107"
            data-filled="0.1"
            data-values="[0]"
            data-stroke-width="2"
            data-tooltip="bottom"
            data-aria-label="Tüderlidrü ... "
          >
          </div>

    <!--<sparkline-element
            width="200"
            height="50"
            id={ "sparkline_element-" <> id }
            data-append={sensor_data.append_data}
            data-maxlength="200"
            phx-update="ignore"
          >
          </sparkline-element>-->

          <sparkline-test
            width="200"
            height="50"
            id={ "sparkline_element-" <> id }
            data-append={sensor_data.append_data}
            maxlength="400"
            phx-update="ignore"
          >
          </sparkline-test>
        </div>
      </div>

      <div id="accumulated-data" class="hidden" phx-update="ignore"></div>

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
    </div>
    """
  end

  @impl true
  def handle_event("signal", _, socket) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "signal", {:signal, %{test: 1}})
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}, socket) do
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

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
           "sensor_id" => sensor_id
         } =
           sensor_data},
        socket
      ) do
    sensor_attribute = sensor_data["uuid"]

    # IO.inspect(sensor_data)

    updated_sensor =
      %{
        # liveview streams id, remove : for document.querySelector compliance
        id: sanitize_sensor_id(sensor_id),
        payload: payload,
        timestamp: DateTime.from_unix!(timestamp, :millisecond) |> DateTime.to_string(),
        sensor_name: sensor_name_for_uuid(sensor_attribute),
        sensor_id: sensor_id
      }
      |> Map.update(
        :append_data,
        "{\"timestamp\": #{sensor_data["timestamp"]}, \"value\": #{sensor_data["payload"]}}",
        fn existing_value -> existing_value end
      )

    # IO.inspect(updated_sensor)

    # case Map.update(updated_sensor, :append_data,  "{\"timestamp\": #{sensor_data["timestamp"]}, \"value\": " <> sensor_data["number"] <> "}", fn existing_value -> existing_value end) do
    #  {:ok} -> IO.puts("Success:")
    #  {:error, reason} -> IO.puts("Error: #{reason}")
    # end

    # Update or add the sensor data for the given UUID
    # updated_sensor_data = Map.put(socket.assigns.sensor_data, sensor_attribute, updated_sensor)

    # Re-assign the updated sensors to the socket and trigger re-render
    # {:noreply, assign(socket, sensor_data: updated_sensor_data)}
    {:noreply, stream_insert(socket, :sensor_data, updated_sensor)}
    # stream
    # Process the payload (e.g., update the assigns)
    # IO.inspect({number, timestamp, uuid}, label: "Received data")

    # Update the socket state
    # {:noreply, assign(socket, :number, number)}
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
