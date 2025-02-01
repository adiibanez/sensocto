defmodule SensoctoWeb.IndexLive do
  # alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.Live.BaseComponents
  import SensoctoWeb.Live.BaseComponents

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 6
  @grid_cols_2xl_default 6

  # https://dev.to/ivor/how-to-unsubscribe-from-all-topics-in-phoenixpubsub-dka
  # https://hexdocs.pm/phoenix_live_view/bindings.html#js-commands

  @impl true
  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensordata:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurements_batch")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    # presence tracking

    new_socket =
      socket
      |> assign(
        sensors_online_count: 0,
        sensors_online: %{},
        sensors_offline: %{},
        sensors: %{},
        test: %{:test2 => %{:timestamp => 123, :payload => 10}},
        stream_div_class: "",
        grid_cols_sm: @grid_cols_sm_default,
        grid_cols_lg: @grid_cols_lg_default,
        grid_cols_xl: @grid_cols_xl_default,
        grid_cols_2xl: @grid_cols_2xl_default
      )
      |> assign(:sensors, Sensocto.SensorsDynamicSupervisor.get_all_sensors_state())

    :telemetry.execute(
      [:sensocto, :live, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
  end

  def handle_info(
        {:measurements_batch, {sensor_id, measurements_list}},
        socket
      )
      when is_list(measurements_list) do
    start = System.monotonic_time()

    Logger.debug("Received measurements_batch for sensor #{sensor_id}")

    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attribute_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    updated_data =
      Enum.reduce(latest_measurements, socket.assigns.sensors, fn measurement, acc ->
        update_in(acc, [measurement.sensor_id], fn sensor_data ->
          sensor_data = sensor_data || %{}

          update_in(sensor_data, [:attributes], fn attributes ->
            attributes = attributes || %{}

            update_in(attributes, [measurement.attribute_id], fn list ->
              list = list || []

              case list do
                [] ->
                  [%{payload: measurement.payload, timestamp: measurement.timestamp}]

                list ->
                  List.update_at(list, 0, fn entry ->
                    %{entry | payload: measurement.payload, timestamp: measurement.timestamp}
                  end)
              end
            end)
          end)
        end)
      end)

    new_socket =
      socket
      |> assign(:sensors_online_count, Enum.count(socket.assigns.sensors))
      |> assign(:sensors, updated_data)
      |> push_event("measurements_batch", %{
        :sensor_id => sensor_id,
        :attributes => measurements_list
      })

    :telemetry.execute(
      [:sensocto, :live, :handle_info, :measurement_batch],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:noreply, new_socket}
  end

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

    #    existing_data = socket.assigns.sensors.result
    existing_data = socket.assigns.sensors

    # Logger.debug("Handle measurment #{inspect(sensor_data)}")

    # IO.inspect(sensor_data, label: "Received measurement data:")
    # IO.inspect(existing_data, label: "Existing:")

    # update client
    measurement = %{
      :payload => payload,
      :timestamp => timestamp,
      :attribute_id => attribute_id,
      :sensor_id => sensor_id
    }

    # IO.inspect(existing_data, label: "Existing data")

    # |> dbg()

    if is_map(existing_data) do
      updated_data =
        update_in(existing_data, [sensor_id], fn sensor_data ->
          sensor_data = sensor_data || %{}

          update_in(sensor_data, [:attributes], fn attributes ->
            attributes = attributes || %{}

            update_in(attributes, [attribute_id], fn list ->
              list = list || []

              case list do
                [] ->
                  [%{payload: payload, timestamp: timestamp}]

                list ->
                  List.update_at(list, 0, fn entry ->
                    %{entry | payload: payload, timestamp: timestamp}
                  end)
              end
            end)
          end)
        end)

      new_socket =
        socket
        |> assign(:sensors_online_count, Enum.count(socket.assigns.sensors))
        |> assign(:sensors, updated_data)
        |> push_event("measurement", measurement)

      :telemetry.execute(
        [:sensocto, :live, :handle_info, :measurement],
        %{duration: System.monotonic_time() - start},
        %{}
      )

      {:noreply, new_socket}
    else
      Logger.debug("Something wrong with existing data #{Sensocto.Utils.typeof(existing_data)}")

      :telemetry.execute(
        [:sensocto, :live, :handle_info, :measurement],
        %{duration: System.monotonic_time() - start},
        %{}
      )

      {:noreply,
       socket
       |> push_event("measurement", measurement)}
    end
  end

  def handle_event("toggle_highlight", %{"sensor_id" => sensor_id} = params, socket) do
    Logger.info("Received highlight event: #{inspect(params)}")

    is_highlighted =
      socket.assigns.sensors
      |> Map.get(sensor_id)
      |> Map.get(:highlighted)
      |> case do
        true -> true
        _ -> false
      end

    {:noreply,
     socket
     |> assign(
       :sensors,
       update_in(socket.assigns.sensors, [sensor_id, :highlighted], fn _ -> not is_highlighted end)
     )}
  end

  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id} = params,
        socket
      ) do
    Logger.debug("clear-attribute request #{inspect(params)}")

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
        %{
          "sensor_id" => sensor_id,
          "attribute_id" => attribute_id,
          "from" => from,
          "to" => to,
          "limit" => limit
        } = params,
        socket
      ) do
    start = System.monotonic_time()
    Logger.debug("request-seed_data #{sensor_id}:#{attribute_id}")

    {:ok, attribute_data} =
      Sensocto.SimpleSensor.get_attribute(sensor_id, attribute_id, from, to, limit)

    Logger.debug("handle_event request-seed-data attribute_data: #{inspect(attribute_data)}")

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

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          # topic: "sensordata:all",
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    Logger.debug(
      "presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
    )

    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)
    sensors_online_count = Enum.count(socket.assigns.sensors)

    {
      :noreply,
      socket
      |> assign(:sensors_online_count, sensors_online_count)
      |> assign(:sensors_online, sensors_online)
      |> assign(:sensors_offline, payload.leaves)
      |> assign(:grid_cols_sm, min(@grid_cols_sm_default, sensors_online_count))
      |> assign(:grid_cols_lg, min(@grid_cols_lg_default, sensors_online_count))
      |> assign(:grid_cols_xl, min(@grid_cols_xl_default, sensors_online_count))
      |> assign(:grid_cols_2xl, min(@grid_cols_2xl_default, sensors_online_count))
      |> assign(:sensors, Sensocto.SensorsDynamicSupervisor.get_all_sensors_state())
    }
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Handled message {__MODULE__}")

    {:noreply, put_flash(socket, :info, "You clicked the button!")}
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
end
