defmodule SensoctoWeb.StatefulSensorLiveview do
  use SensoctoWeb, :live_view
  use SensoctoNative, :live_view
  import Phoenix.LiveView

  alias Sensocto.SimpleSensor
  alias SensoctoWeb.Live.Components.AttributeComponent
  import SensoctoWeb.Live.BaseComponents

  require Logger

  @impl true
  def mount(_params, %{"parent_pid" => parent_pid, "sensor" => sensor}, socket) do
    # send_test_event()
    # Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement:#{sensor.metadata.sensor_id}")

    Phoenix.PubSub.subscribe(
      Sensocto.PubSub,
      "measurements_batch:#{sensor.metadata.sensor_id}"
    )

    # https://www.richardtaylor.dev/articles/beautiful-animated-charts-for-liveview-with-echarts
    # https://echarts.apache.org/examples/en/index.html#chart-type-flowGL

    sensor_state =
      SimpleSensor.get_state(sensor.metadata.sensor_id)

    # |> dbg()

    {:ok,
     socket
     |> assign(:parent_pid, parent_pid)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_state.metadata.sensor_id)
     |> assign(:sensor_name, sensor_state.metadata.sensor_name)
     |> assign(:sensor_type, sensor_state.metadata.sensor_type)
     |> assign(:highlighted, false)
     |> assign(:attributes, sensor_state.attributes)
     |> assign(
       :attributes_loaded,
       is_map(sensor_state.attributes) and Enum.count(sensor_state.attributes) > 0
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="sensor flex flex-col rounded-lg shadow-md p-2 sm:p-2 md:p-2 lg:p-2 xl:p-2 cursor-pointer bg-dark-gray text-light-gray h-48"
      style="border:0 solid green"
    >
      <div class="w-full h-full">
        <p class="hidden">
          Statefulsensor pid: {inspect(self())} Parent pid: {inspect(@parent_pid)} attributes: {inspect(
            @attributes_loaded
          )}
        </p>

        <.render_sensor_header
          sensor_id={@sensor_id}
          sensor_name={@sensor_name}
          highlighted={@highlighted}
        >
        </.render_sensor_header>

        <div :if={not @attributes_loaded}>
          {render_loading(8, "#{@sensor_id}", assigns)}
        </div>

        <div>
          Type: {@sensor_type}

          <.live_component
            :for={{attribute_id, attribute} <- @attributes}
            id={"attribute_#{@sensor_id}_#{attribute_id}"}
            attribute_type={@sensor_type}
            module={AttributeComponent}
            attribute={attribute}
            sensor_id={@sensor_id}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
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

    Map.merge(socket.assigns.attributes, new_attributes)

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement_batch],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    Enum.all?(latest_measurements, fn measurement ->
      Logger.debug("Heereee ... #{inspect(measurement.attribute_id)}")
      pid = self()

      Task.start(fn ->
        # Do something asynchronously
        send_update_after(
          pid,
          AttributeComponent,
          [
            id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
            attribute: measurement
            # sensor_id: sensor_id
          ],
          0
        )
      end)

      # send_update(AttributeComponent,
      #   id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
      #   attribute: measurement
      # )
    end)

    {:noreply,
     new_socket
     |> assign(:attributes, Map.merge(socket.assigns.attributes, new_attributes))}
  end

  defp list_to_map(list) do
    list
    |> Enum.group_by(& &1.attribute_id)
    |> Enum.map(fn {attribute_id, measurements} ->
      {attribute_id, Enum.max_by(measurements, & &1.timestamp)}
    end)
    |> Enum.into(%{})
  end

  def cleanup(entry) do
    case entry do
      {attribute_id, [entry]} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}

      {attribute_id, %{}} ->
        {attribute_id, entry}
    end
  end

  @impl true
  def handle_info(
        :attributes_loaded,
        socket
      ) do
    {:noreply, socket |> assign(:attributes_loaded, true)}
  end

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

    pid = self()

    Task.start(fn ->
      # Do something asynchronously
      send_update_after(
        pid,
        AttributeComponent,
        [
          id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
          attribute: measurement
          # sensor_id: sensor_id
        ],
        0
      )
    end)

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    # measurement |> dbg()
    Map.merge(socket.assigns.attributes, %{measurement.attribute_id => measurement})
    # |> dbg()

    {
      :noreply,
      socket
      |> push_event("measurement", measurement)
      |> assign(
        :attributes,
        Map.merge(socket.assigns.attributes, %{measurement.attribute_id => measurement})
      )

      # |> assign(:sensors_online_count, Enum.count(socket.assigns.sensors))
      # |> assign(:sensors, updated_data)
    }
  end

  def handle_event("toggle_highlight", %{"sensor_id" => sensor_id} = params, socket) do
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
end
