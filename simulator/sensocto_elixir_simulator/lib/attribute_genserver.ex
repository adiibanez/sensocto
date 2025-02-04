defmodule Sensocto.AttributeGenServer do
  use GenServer
  require Logger

  @enforce_keys [:attribute_id]
  defstruct @enforce_keys ++ [:state_data, :phoenix_connected, :phoenix_channel]

  @type state :: %__MODULE__{
    attribute_id: String.t(),
    state_data: map(),
    phoenix_connected: boolean(),
    phoenix_channel: any()
  }

  # Public API
  def start_link(%{attribute_id: attribute_id} = config) do
    Logger.info("Starting AttributeGenServer with config: #{inspect(config)}")
    GenServer.start_link(__MODULE__, config, name: via_tuple(attribute_id))
  end

  def get_state(attribute_id) do
    GenServer.call(via_tuple(attribute_id), :get_state)
  end

  # GenServer Callbacks
  @impl true
  def init(%{attribute_id: attribute_id} = config) do
    Logger.info("Initializing AttributeGenServer for #{attribute_id}")

    state = %__MODULE__{
      attribute_id: attribute_id,
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
    Logger.info("Connecting to Phoenix for #{state.attribute_id}")
    # Implement connection logic here
    {:noreply, state}
  end

  defp via_tuple(attribute_id), do: {:via, Registry, {Sensocto.Registry, attribute_id}}
end
