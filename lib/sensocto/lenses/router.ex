defmodule Sensocto.Lenses.Router do
  @moduledoc """
  Routes sensor measurements from SimpleSensor broadcasts to appropriate lenses.

  Instead of having every LiveView subscribe to every sensor topic (O(N×M) subscriptions),
  the Router subscribes once to the global sensor data topic and distributes
  measurements to registered lenses.

  ## Design

  The Router listens to "data:global" for all sensor measurements and forwards
  them to active lenses. Lenses register with the Router to receive measurements.

  This centralizes the PubSub subscription management and allows lenses to
  process data in batches before forwarding to clients.
  """

  use GenServer
  require Logger

  @global_data_topic "data:global"

  defstruct [:registered_lenses]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a lens process to receive measurements.
  The lens will receive {:measurement, sensor_id, measurement} messages.
  """
  def register_lens(lens_pid) when is_pid(lens_pid) do
    GenServer.call(__MODULE__, {:register_lens, lens_pid})
  end

  @doc """
  Unregister a lens process.
  """
  def unregister_lens(lens_pid) when is_pid(lens_pid) do
    GenServer.call(__MODULE__, {:unregister_lens, lens_pid})
  end

  @doc """
  Get list of registered lenses (for debugging).
  """
  def get_registered_lenses do
    GenServer.call(__MODULE__, :get_registered_lenses)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Subscribe to global data topic
    Phoenix.PubSub.subscribe(Sensocto.PubSub, @global_data_topic)

    Logger.info("LensRouter started, subscribed to #{@global_data_topic}")

    {:ok, %__MODULE__{registered_lenses: MapSet.new()}}
  end

  @impl true
  def handle_call({:register_lens, lens_pid}, _from, state) do
    # Monitor the lens so we can unregister it if it dies
    Process.monitor(lens_pid)
    new_lenses = MapSet.put(state.registered_lenses, lens_pid)
    Logger.debug("LensRouter: registered lens #{inspect(lens_pid)}")
    {:reply, :ok, %{state | registered_lenses: new_lenses}}
  end

  @impl true
  def handle_call({:unregister_lens, lens_pid}, _from, state) do
    new_lenses = MapSet.delete(state.registered_lenses, lens_pid)
    Logger.debug("LensRouter: unregistered lens #{inspect(lens_pid)}")
    {:reply, :ok, %{state | registered_lenses: new_lenses}}
  end

  @impl true
  def handle_call(:get_registered_lenses, _from, state) do
    {:reply, MapSet.to_list(state.registered_lenses), state}
  end

  # Handle single measurement from SimpleSensor
  @impl true
  def handle_info({:measurement, measurement}, state) do
    sensor_id = Map.get(measurement, :sensor_id)

    # Forward to all registered lenses
    for lens_pid <- state.registered_lenses do
      send(lens_pid, {:router_measurement, sensor_id, measurement})
    end

    {:noreply, state}
  end

  # Handle batch measurements from SimpleSensor
  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements}}, state) do
    # Forward batch to all registered lenses
    for lens_pid <- state.registered_lenses do
      send(lens_pid, {:router_measurements_batch, sensor_id, measurements})
    end

    {:noreply, state}
  end

  # Handle lens process death
  @impl true
  def handle_info({:DOWN, _ref, :process, lens_pid, _reason}, state) do
    new_lenses = MapSet.delete(state.registered_lenses, lens_pid)
    Logger.debug("LensRouter: lens #{inspect(lens_pid)} died, unregistering")
    {:noreply, %{state | registered_lenses: new_lenses}}
  end

  # Ignore other messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
