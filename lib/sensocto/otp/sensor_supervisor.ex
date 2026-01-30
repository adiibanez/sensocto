defmodule Sensocto.SensorSupervisor do
  use Supervisor
  require Logger
  alias Sensocto.AttributeStoreTiered
  alias Sensocto.SimpleSensor

  def start_link(configuration) do
    Supervisor.start_link(__MODULE__, configuration, name: via_tuple(configuration.sensor_id))
  end

  @impl true
  @spec init(any()) ::
          {:ok,
           {%{
              auto_shutdown: :all_significant | :any_significant | :never,
              intensity: non_neg_integer(),
              period: pos_integer(),
              strategy: :one_for_all | :one_for_one | :rest_for_one
            }, [{any(), any(), any(), any(), any(), any()} | map()]}}
  def init(configuration) do
    Logger.debug("SensorSupervisor started #{inspect(configuration)}")

    # IMPORTANT: Start AttributeStoreTiered BEFORE SimpleSensor
    # SimpleSensor.handle_call({:get_state, _}) calls AttributeStore.get_attributes()
    # which will fail if the Agent isn't registered yet. Starting the attribute store
    # first prevents this race condition.
    children = [
      %{
        id: :attribute_store,
        start: {AttributeStoreTiered, :start_link, [configuration]},
        shutdown: 5000,
        restart: :permanent,
        type: :worker
      },
      %{
        id: :sensor,
        start: {SimpleSensor, :start_link, [configuration]},
        shutdown: 5000,
        restart: :permanent,
        type: :worker
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(sensor_id) do
    {:via, Registry, {Sensocto.SensorPairRegistry, sensor_id}}
  end
end
