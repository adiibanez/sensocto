defmodule Sensocto.ConnectorGenServer do
  use GenServer
  require Logger

  @enforce_keys [:connector_id]
  defstruct @enforce_keys ++ [:state_data, :phoenix_connected, :phoenix_channel]

  @type state :: %__MODULE__{
    connector_id: String.t(),
    state_data: map(),
    phoenix_connected: boolean(),
    phoenix_channel: any()
  }

  # Public API
  def start_link(%{connector_id: connector_id} = config) do
    Logger.info("Starting ConnectorGenServer with config: #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple(connector_id))
  end

  def get_state(connector_id) do
    GenServer.call(via_tuple(connector_id), :get_state)
  end

  # GenServer Callbacks
  @impl true
  def init(%{connector_id: connector_id} = config) do
    Logger.info("Initializing ConnectorGenServer for #{connector_id}")

    state = %__MODULE__{
      connector_id: connector_id,
      state_data: %{},
      phoenix_connected: false,
      phoenix_channel: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:connect_phoenix, state) do
    Logger.info("Connecting to Phoenix for #{state.connector_id}")
    # Implement connection logic here
    {:noreply, state}
  end

  defp via_tuple(connector_id), do: {:via, Registry, {Sensocto.Registry, connector_id}}
end
