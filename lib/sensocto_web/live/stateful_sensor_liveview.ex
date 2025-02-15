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
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor.metadata.sensor_id}")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor.metadata.sensor_id}")

    # https://www.richardtaylor.dev/articles/beautiful-animated-charts-for-liveview-with-echarts
    # https://echarts.apache.org/examples/en/index.html#chart-type-flowGL

    sensor_state =
      SimpleSensor.get_state(sensor.metadata.sensor_id)

    # |> dbg()

    # |> dbg()

    {:ok,
     socket
     |> assign(:parent_pid, parent_pid)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_state.metadata.sensor_id)
     |> assign(:sensor_name, sensor_state.metadata.sensor_name)
     |> assign(:sensor_type, sensor_state.metadata.sensor_type)
     #  |> assign(:sensor_attributes_metadata, sensor_state.metadata.attributes)
     #  |> assign(:sensor_attributes_data, sensor_state.attributes)
     |> assign(:highlighted, false)
     |> assign(
       :attributes_loaded,
       true
     )}
  end

  # defp attributes_loaded?(assigns) do
  #   is_map(assigns.metadata.attributes) and
  #     Enum.count(assigns.metadata.attributes) > 0 and
  #     is_map(assigns.sensor.attributes) and
  #     Enum.count(assigns.sensor.attributes) > 0
  # end

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

    pid = self()

    Task.start(fn ->
      # Do something asynchronously
      send_update(
        pid,
        AttributeComponent,
        id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
        attribute_data: measurement
      )
    end)

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    # measurement |> dbg()
    Map.merge(socket.assigns.sensor.attributes, %{
      String.to_atom(measurement.attribute_id) => measurement
    })

    # |> dbg()

    {
      :noreply,
      socket
      |> push_event("measurement", measurement)
      |> assign(
        :sensor,
        update_in(
          socket.assigns.sensor,
          [:attributes],
          fn _ -> Map.merge(socket.assigns.sensor.attributes, measurement) end
        )
      )
    }
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

    Enum.all?(latest_measurements, fn measurement ->
      pid = self()

      # measurement |> dbg()

      Task.start(fn ->
        # Do something asynchronously
        send_update(
          pid,
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
          attribute_data: measurement
        )
      end)
    end)

    {:noreply,
     new_socket
     |> assign(
       :sensor,
       update_in(
         socket.assigns.sensor,
         [:attributes],
         fn _ -> Map.merge(socket.assigns.sensor.attributes, new_attributes) end
       )
     )}
  end

  @impl true
  def handle_info(
        {:new_state, _sensor_id},
        socket
      ) do
    Logger.debug("New state for sensor")
    # socket.assigns |> dbg()

    {
      :noreply,
      socket
      |> assign(:sensor, SimpleSensor.get_state(socket.assigns.sensor_id))
    }
  end

  @impl true
  def handle_info(
        :attributes_loaded,
        socket
      ) do
    {:noreply, socket |> assign(:attributes_loaded, true)}
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

  def cleanup(entry) do
    case entry do
      {attribute_id, [entry]} ->
        {attribute_id, entry |> Map.put(:attribute_id, attribute_id)}

      {attribute_id, %{}} ->
        {attribute_id, entry}
    end
  end
end
