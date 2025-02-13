defmodule SensoctoWeb.Live.LvnEntryLive do
  alias Sensocto.Sensors.Connector
  use SensoctoWeb, :live_view
  use SensoctoNative, :live_view
  require Logger
  alias Phoenix.PubSub
  alias Sensocto.Otp.BleConnectorGenServer

  def mount(params, session, socket) do
    Logger.info("LVN entry main #{inspect(params)}, #{inspect(session)}")

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "ble_state")

    {:ok,
     socket
     |> assign(:ble_scan, false)
     |> assign(:ble_state, BleConnectorGenServer.get_state())}
  end

  def render(assigns) do
    ~H"""
    <pre class="">{inspect(@ble_state, pretty: true)}</pre>
    <div>
      <div :for={{peripheral_id, peripheral} <- @ble_state.peripherals}>
        <div>{inspect(peripheral)}</div>
        <p>{peripheral.name} {peripheral.id}</p>
        <p>RSSI: {peripheral.rssi}, State: {peripheral.state}</p>

        <%!--<div
          :for={
            {characteristic_id, characteristic} <-
              @ble_state.peripheral_characteristics[peripheral_id]
          }
          :if={is_map(@ble_state.peripheral_characteristics[peripheral_id])}
        >
          {inspect(characteristic)}
        </div>--%>
      </div>
    </div>
    """
  end

  def handle_info(:ble_state_changed, socket) do
    Logger.debug("handle_info :ble_state_changed")

    {:noreply,
     assign(
       socket,
       :ble_state,
       BleConnectorGenServer.get_state()
     )}
  end

  def handle_event("test-event", params, socket) do
    Logger.debug("test-event params: #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("toggle-scan", params, socket) do
    Logger.debug("toggle-scan params: #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("ble-central-state-changed", state, socket) do
    Logger.info("ble-central-state-changed state: #{inspect(state)}")

    BleConnectorGenServer.update_state_type(:central_state, state)
    process_ble_state_change(socket)
  end

  def handle_event("ble-scan-state-changed", state, socket) do
    Logger.info("ble-scan-state-changed state: #{inspect(state)}")

    BleConnectorGenServer.update_state_type(:scan_state, state)
    process_ble_state_change(socket)
  end

  def handle_event(
        "ble-peripheral-discovered",
        %{
          "id" => peripheral_id,
          "name" => peripheral_name,
          "state" => peripheral_state,
          "rssi" => peripheral_rssi
        } =
          peripheral,
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
        } = service,
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
          "service_id" => service_id,
          "characteristics" => characteristics
        } = payload,
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
