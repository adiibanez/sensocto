defmodule Sensocto.Lenses.Router do
  @moduledoc """
  Routes sensor measurements from SimpleSensor broadcasts to appropriate lenses.

  Instead of having every LiveView subscribe to every sensor topic (O(N×M) subscriptions),
  the Router subscribes to attention-sharded sensor data topics and distributes
  measurements to registered lenses.

  ## Design

  The Router listens to "data:attention:{high,medium,low}" for sensor measurements
  and forwards them to active lenses. Lenses register with the Router to receive measurements.

  The Router is demand-driven: it only subscribes to attention topics when there are
  registered lenses, and unsubscribes when the last lens unregisters. This prevents
  unnecessary message processing when no one is viewing sensor data.

  This centralizes the PubSub subscription management and allows lenses to
  process data in batches before forwarding to clients.
  """

  use GenServer
  require Logger

  @attention_topics ["data:attention:high", "data:attention:medium", "data:attention:low"]

  defstruct [:registered_lenses, :subscribed]

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
    # Don't subscribe yet - wait until a lens registers (demand-driven)
    Logger.info("LensRouter started (demand-driven, not yet subscribed to attention topics)")

    {:ok, %__MODULE__{registered_lenses: MapSet.new(), subscribed: false}}
  end

  @impl true
  def handle_call({:register_lens, lens_pid}, _from, state) do
    # Monitor the lens so we can unregister it if it dies
    Process.monitor(lens_pid)
    new_lenses = MapSet.put(state.registered_lenses, lens_pid)

    # Subscribe to attention topics if this is the first lens
    state =
      if not state.subscribed and MapSet.size(new_lenses) > 0 do
        Enum.each(@attention_topics, &Phoenix.PubSub.subscribe(Sensocto.PubSub, &1))
        Logger.info("LensRouter: subscribed to attention topics (first lens registered)")
        %{state | subscribed: true}
      else
        state
      end

    Logger.debug("LensRouter: registered lens #{inspect(lens_pid)}")
    {:reply, :ok, %{state | registered_lenses: new_lenses}}
  end

  @impl true
  def handle_call({:unregister_lens, lens_pid}, _from, state) do
    new_lenses = MapSet.delete(state.registered_lenses, lens_pid)

    # Unsubscribe from attention topics if no more lenses
    state =
      if state.subscribed and MapSet.size(new_lenses) == 0 do
        Enum.each(@attention_topics, &Phoenix.PubSub.unsubscribe(Sensocto.PubSub, &1))
        Logger.info("LensRouter: unsubscribed from attention topics (no more lenses)")
        %{state | subscribed: false}
      else
        state
      end

    Logger.debug("LensRouter: unregistered lens #{inspect(lens_pid)}")
    {:reply, :ok, %{state | registered_lenses: new_lenses}}
  end

  @impl true
  def handle_call(:get_registered_lenses, _from, state) do
    {:reply, MapSet.to_list(state.registered_lenses), state}
  end

  # Handle single measurement from SimpleSensor
  # Writes directly to PriorityLens ETS tables — bypasses PriorityLens GenServer mailbox
  @impl true
  def handle_info({:measurement, measurement}, state) do
    sensor_id = Map.get(measurement, :sensor_id)

    # Direct ETS write via PriorityLens public functions
    Sensocto.Lenses.PriorityLens.buffer_for_sensor(sensor_id, measurement)

    {:noreply, state}
  end

  # Handle batch measurements from SimpleSensor
  # Writes directly to PriorityLens ETS tables — bypasses PriorityLens GenServer mailbox
  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements}}, state) do
    # Direct ETS write via PriorityLens public functions
    Sensocto.Lenses.PriorityLens.buffer_batch_for_sensor(sensor_id, measurements)

    {:noreply, state}
  end

  # Handle lens process death
  @impl true
  def handle_info({:DOWN, _ref, :process, lens_pid, _reason}, state) do
    new_lenses = MapSet.delete(state.registered_lenses, lens_pid)

    # Unsubscribe from attention topics if no more lenses
    state =
      if state.subscribed and MapSet.size(new_lenses) == 0 do
        Enum.each(@attention_topics, &Phoenix.PubSub.unsubscribe(Sensocto.PubSub, &1))
        Logger.info("LensRouter: unsubscribed from attention topics (last lens died)")
        %{state | subscribed: false}
      else
        state
      end

    Logger.debug("LensRouter: lens #{inspect(lens_pid)} died, unregistering")
    {:noreply, %{state | registered_lenses: new_lenses}}
  end

  # Ignore other messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
