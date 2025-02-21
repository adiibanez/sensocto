defmodule SensoctoWeb.Live.LvnEntryLive do
  use SensoctoWeb, :live_view
  use SensoctoNative, :live_view
  require Logger
  alias Phoenix.PubSub
  alias Sensocto.Otp.BleConnectorGenServer

  @retrieve_values 5

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(params, session, socket) do
    Logger.info("LVN entry main #{inspect(params)}, #{inspect(session)}")

    # presence joins / leaves
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensocto:")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "ble_state")

    sensors = get_sensors_state()
    # |> dbg()

    Enum.all?(sensors, fn {sensor_id, _sensor} ->
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
    end)

    {:ok,
     socket
     |> assign(:ble_scan, false)
     |> assign(:ble_state, BleConnectorGenServer.get_state())
     |> assign(:sensors, sensors)
     |> assign(:flat_attributes, sensors |> flatten_attributes())}
  end

  def time_ago_from_unix(timestamp) do
    # timestamp |> dbg()

    diff = Timex.diff(Timex.now(), Timex.from_unix(timestamp, :millisecond), :millisecond)

    case diff > 1000 do
      true ->
        timestamp
        |> Timex.from_unix(:milliseconds)
        |> Timex.format!("{relative}", :relative)

      _ ->
        "#{abs(diff)}ms ago"
    end
  end

  # @impl true
  # def _render(assigns) do
  #   ~H"""
  #   <pre class="hidden">{inspect(@ble_state, pretty: true)}</pre>
  #   """
  # end

  defp get_sensors_state() do
    Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view, @retrieve_values)
  end

  def handle_info(:ble_state_changed, socket) do
    # Logger.debug("handle_info :ble_state_changed")

    ble_state = BleConnectorGenServer.get_state()

    {:noreply,
     socket
     |> assign(
       :ble_state,
       ble_state
     )}
  end

  def flatten_attributes(sensor_data) do
    Enum.flat_map(sensor_data, fn {sensor_id, sensor} ->
      Enum.map(sensor.attributes, fn {attribute_id, attribute} ->
        Map.merge(attribute, %{sensor_id: sensor_id})
      end)
    end)
    |> Map.new(fn attribute -> {attribute.attribute_id, attribute} end)
  end

  def handle_info({:measurement, %{:sensor_id => sensor_id} = _measurement}, socket) do
    Logger.info("handle_info measurement: #{sensor_id}")

    sensors = get_sensors_state()

    {:noreply,
     socket
     |> assign(
       :sensors,
       sensors
     )
     |> assign(:flat_attributes, sensors |> flatten_attributes())}
  end

  def handle_info({:measurements_batch, _batch}, socket) do
    Logger.info("handle_info measurements batch")

    sensors = get_sensors_state()

    {:noreply,
     socket
     |> assign(
       :sensors,
       sensors
     )
     |> assign(:flat_attributes, sensors |> flatten_attributes())}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    Logger.debug(
      "presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
    )

    sensors = get_sensors_state()

    {:noreply,
     socket
     |> assign(
       :sensors,
       sensors
     )
     |> assign(:flat_attributes, sensors |> flatten_attributes())}
  end

  def handle_event("test-event", params, socket) do
    Logger.debug("test-event params: #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("toggle-scan", params, socket) do
    Logger.debug("toggle-scan params: #{inspect(params)}")
    {:noreply, socket |> assign(:ble_scan, !socket.assigns.ble_scan)}
  end

  def handle_event("ble-central-state-changed", state, socket) do
    Logger.info("ble-central-state-changed state: #{inspect(state)}")

    BleConnectorGenServer.update_state_type(:central_state, state)
    process_ble_state_change(socket)
  end

  def handle_event("ble-scan-state-changed", state, socket) do
    Logger.info("ble-scan-state-changed state: #{inspect(state)}")

    BleConnectorGenServer.update_state_type(:scan_state, state)
    process_ble_state_change(socket |> assign(:ble_scan, state == "scanning"))
  end

  def handle_event(
        "ble-peripheral-discovered",
        %{
          "id" => peripheral_id,
          "name" => peripheral_name,
          "state" => peripheral_state,
          "rssi" => peripheral_rssi
        } =
          _peripheral,
        socket
      ) do
    # Logger.info(
    #   "ble-peripheral-discovered params: #{inspect(peripheral)}, ble_state: #{inspect(socket.assigns.ble_state)}"
    # )

    BleConnectorGenServer.add_scan_peripheral(%{
      :id => peripheral_id,
      :name => peripheral_name,
      :state => peripheral_state,
      :rssi => peripheral_rssi
    })

    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-peripheral-connected",
        %{
          "id" => peripheral_id,
          "name" => peripheral_name,
          "state" => peripheral_state,
          "rssi" => peripheral_rssi
        } =
          peripheral,
        socket
      ) do
    Logger.info(
      "ble-peripheral-connected params: #{inspect(peripheral)}, ble_state: #{inspect(socket.assigns.ble_state)}"
    )

    BleConnectorGenServer.add_peripheral(%{
      :id => peripheral_id,
      :name => peripheral_name,
      :state => peripheral_state,
      :rssi => peripheral_rssi
    })

    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-peripheral-rssi-update",
        %{"id" => peripheral_id, "rssi" => rssi} = rssi_update,
        socket
      ) do
    Logger.info("ble-peripheral-rssi-update params: #{inspect(rssi_update)}")

    BleConnectorGenServer.update_rssi(%{:id => peripheral_id}, rssi)

    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-service-discovered",
        %{
          "id" => service_id,
          "is_primary" => is_primary,
          "name" => peripheral_name,
          "peripheral_id" => peripheral_id
        } = _service,
        socket
      ) do
    # Logger.info("ble-service-discovered #{inspect(service)}")

    BleConnectorGenServer.add_service(%{:id => peripheral_id}, %{
      :id => service_id,
      :is_primary => is_primary,
      :name => peripheral_name,
      :peripheral_id => peripheral_id
    })

    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-characteristics-discovered",
        %{
          "peripheral_id" => peripheral_id,
          "service_id" => _service_id,
          "characteristics" => characteristics
        } = _payload,
        socket
      ) do
    # Logger.info(
    #   "ble-characteristics-discovered #{peripheral_id}, #{service_id}, #{inspect(characteristics)}"
    # )

    characteristics_atoms =
      Enum.map(characteristics, fn characteristic ->
        Enum.reduce(characteristic, %{}, fn {key, value}, acc ->
          Map.put(acc, String.to_atom(key), value)
        end)
      end)

    BleConnectorGenServer.add_characteristics(%{:id => peripheral_id}, characteristics_atoms)
    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-characteristic-value-changed",
        %{
          "characteristic_id" => characteristic_id,
          "name" => _characteristic_name,
          "timestamp" => timestamp,
          "peripheral_id" => peripheral_id,
          "peripheral_name" => _peripheral_name,
          "value" => value
        },
        socket
      ) do
    Logger.info(
      "ble-characteristic-value-changed #{peripheral_id} #{characteristic_id} #{Sensocto.Utils.typeof(value)} #{is_binary(value)}"
    )

    BleConnectorGenServer.update_value(
      %{:id => peripheral_id},
      characteristic_id,
      %{:timestamp => timestamp, :value => value}
    )

    process_ble_state_change(socket)
  end

  def handle_event("ble-connect", %{"peripheral_id" => peripheral_id}, socket) do
    {:noreply, push_event(socket, "ble-command", %{"peripheral_id" => peripheral_id})}
  end

  def handle_event(event, params, socket) do
    Logger.info("Generic event: #{inspect(event)}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  defp process_ble_state_change(socket) do
    new_ble_state = BleConnectorGenServer.get_state()

    PubSub.broadcast(
      Sensocto.PubSub,
      "ble_state",
      :ble_state_changed
    )

    {:noreply, assign(socket, :ble_state, new_ble_state)}
  end
end
