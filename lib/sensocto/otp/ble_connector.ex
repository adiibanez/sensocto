defmodule Sensocto.Otp.BleConnectorGenServer do
  use GenServer
  require Logger
  # use Sensocto.Utils.OtpDsl.Genserver,
  #  initial_state: %{},
  #  register: :sensocto_connector

  # defcast add_peripheral(peripheral), state do
  #  noreply(Map.put(state, :peripherals, [peripheral | state[:peripherals]]))
  # end

  @doc """
  alias Sensocto.Otp.BleConnectorGenServer
  BleConnectorGenServer.add_peripheral(%{:id => "test2"})
  BleConnectorGenServer.update_rssi(%{:id => "test2"}, 20)
  BleConnectorGenServer.update_value(%{:id => "test2"}, "test", 10)
  """

  def start_link(configuration \\ %{}) do
    Logger.debug("BleConnectorGenServer start_link: #{inspect(configuration)}")
    GenServer.start_link(__MODULE__, configuration, name: :ble_genserver)
  end

  @impl true
  @spec init(map()) :: {:ok, %{:message_timestamps => [], optional(any()) => any()}}
  def init(state) do
    Logger.debug("BleConnectorGenServer state: #{inspect(state)}")
    # Initialize message counter and schedule mps calculation
    # state =
    #   Map.merge(state, %{message_timestamps: []})
    #   |> Map.put(:mps_interval, 5000)

    # schedule_mps_calculation()
    {:ok,
     %{
       :central_state => :unknown,
       :scan_state => :unknown,
       :scan_peripherals => %{},
       :peripherals => %{},
       :peripheral_characteristics => %{},
       :peripheral_characteristic_values => %{}
     }}
  end

  def get_state() do
    # Logger.debug("Client: get_state #{inspect(self())}")
    GenServer.call(:ble_genserver, :get_state)
  end

  def update_state_type(type, value) do
    # Logger.debug("Client: update_state #{inspect(self())}")
    GenServer.cast(:ble_genserver, {:update_state, type, value})
  end

  def add_scan_peripheral(peripheral) do
    # Logger.debug("Client: add_scan_peripheral #{inspect(self())}")

    GenServer.cast(
      :ble_genserver,
      {:add_scan_peripheral, peripheral}
    )
  end

  def add_peripheral(peripheral) do
    # Logger.debug("Client: add_peripheral #{inspect(self())}")

    GenServer.cast(
      :ble_genserver,
      {:add_peripheral, peripheral}
    )
  end

  def add_service(peripheral, service) do
    # Logger.debug("Client: add_service  #{inspect(self())}")

    GenServer.cast(
      :ble_genserver,
      {:add_service, {peripheral, service}}
    )
  end

  def add_characteristics(peripheral, characteristics) do
    # Logger.debug("Client: add_characteristics  #{inspect(self())}")

    GenServer.cast(
      :ble_genserver,
      {:add_characteristics, {peripheral, characteristics}}
    )
  end

  def update_rssi(peripheral, rssi) do
    # Logger.debug("Client: add_peripheral #{inspect(self())}")
    GenServer.cast(:ble_genserver, {:update_rssi, peripheral, rssi})
  end

  def update_value(peripheral, characteristic_id, value) do
    # Logger.debug("Client: update_value #{inspect(self())}")
    GenServer.cast(:ble_genserver, {:update_value, peripheral, characteristic_id, value})
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:add_scan_peripheral, peripheral}, state) do
    # Logger.debug("Server: add_scan_peripheral #{peripheral}")

    peripherals =
      state.scan_peripherals
      |> Map.put(peripheral.id, peripheral)

    {:noreply, %{state | scan_peripherals: peripherals}}
  end

  @impl true
  def handle_cast({:add_peripheral, peripheral}, state) do
    # Logger.debug("Server: add_peripheral #{peripheral}")

    new_state =
      Map.merge(state, %{
        :peripheral_services => %{peripheral.id => %{}},
        :peripheral_characteristics => %{peripheral.id => %{}},
        :peripheral_characteristic_values => %{peripheral.id => %{}}
      })

    # |> update_in([:peripherals, peripheral.id], fn _ -> %{} end)
    # |> update_in([:peripheral_characteristics, peripheral.id], fn _ -> %{} end)
    # |> update_in([:peripheral_characteristic_values, peripheral.id], fn _ -> %{} end)

    peripherals =
      state.peripherals
      |> Map.put(peripheral.id, peripheral)

    {:noreply, %{new_state | peripherals: peripherals}}
  end

  @impl true
  def handle_cast({:remove_peripheral, peripheral}, state) do
    # Logger.debug("Server: add_peripheral #{peripheral}")

    # new_state =
    #   state
    #   |> update_in([:peripheral_services, peripheral.id], fn _ -> %{} end)
    #   |> update_in([:peripheral_characteristics, peripheral.id], fn _ -> %{} end)
    #   |> update_in([:peripheral_characteristic_values, peripheral.id], fn _ -> %{} end)

    peripherals =
      state.peripherals
      |> Map.put(peripheral.id, peripheral)

    {:noreply, %{state | peripherals: peripherals}}
  end

  @impl true
  def handle_cast({:add_service, {peripheral, service}}, state) do
    # Logger.debug("Server: add_service #{inspect(peripheral)} #{inspect(service)}")

    new_state =
      state
      |> update_in([:peripheral_services, peripheral.id, service.id], fn _ -> service end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:add_characteristics, {peripheral, characteristics}}, state) do
    # Logger.debug("Server: add_characteristics #{inspect(peripheral)} #{inspect(characteristics)}")

    characteristics_map =
      characteristics
      |> Enum.reduce(%{}, fn characteristic, acc ->
        Map.put(acc, characteristic.id, characteristic)
      end)

    # |> dbg()

    initialized_values =
      Map.keys(characteristics_map)
      |> Enum.reduce(%{}, fn characteristic_id, acc ->
        Map.put(acc, characteristic_id, [])
      end)

    # |> dbg()

    new_characterists_values =
      Map.merge(state.peripheral_characteristic_values[peripheral.id], initialized_values)

    new_state =
      state
      |> update_in([:peripheral_characteristics, peripheral.id], fn _ -> characteristics_map end)
      |> update_in([:peripheral_characteristic_values, peripheral.id], fn _ ->
        new_characterists_values
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_rssi, peripheral, rssi}, state) do
    # Logger.debug("Server: update_rssi #{peripheral} #{rssi}")

    peripherals =
      state.peripherals
      |> update_in([peripheral.id, :rssi], fn _ -> rssi end)

    {:noreply, %{state | peripherals: peripherals}}
  end

  @impl true
  def handle_cast({:update_state, type, value}, state) do
    # Logger.debug("Server: update_state #{type} #{value}")

    {:noreply,
     state
     |> update_in([type], fn _ -> value end)}
  end

  @impl true
  def handle_cast({:update_value, peripheral, characteristic_id, value}, state) do
    Logger.info(
      "Server: update_value #{inspect(peripheral)} #{inspect(characteristic_id)} #{inspect(value)}"
    )

    new_state =
      state
      |> update_in(
        [:peripheral_characteristic_values, peripheral.id, characteristic_id],
        fn values ->
          (values ++ [value]) |> Enum.take(-10)
        end
      )

    # peripherals =
    #   state.peripherals
    #   |> ensure_characteristic_init(peripheral, characteristic_id)
    #   |> update_in([peripheral.id, characteristic_id], fn values ->
    #     # Logger.info("Here: #{inspect(values)}")

    #     case is_list(values) and length(values) > 0 do
    #       # true -> {nil, [values ++ value] |> List.flatten()}
    #       # false -> {nil, [value]}
    #       true -> (values ++ [value]) |> Enum.take(-50)
    #       false -> [value]
    #     end
    #   end)

    # |> dbg()

    {:noreply, new_state}
  end

  # defp ensure_characteristic_init(peripherals, peripheral, characteristic_id) do
  #   case is_list(peripherals[peripheral.id][characteristic_id]) do
  #     true ->
  #       peripherals

  #     false ->
  #       peripherals
  #       # |> dbg()
  #       |> update_in([peripheral.id, :characteristics, characteristic_id], fn _ ->
  #         []
  #       end)

  #       # |> dbg()
  #   end
  # end

  defp via_tuple(sensor_id) do
    # Sensocto.RegistryUtils.via_dynamic_registry(SimpleSensorRegistry, sensor_id)
    {:via, Registry, {SimpleSensorRegistry, sensor_id}}
  end
end
