defmodule Sensocto.SensorSupervisor do
  use Supervisor
  require Logger
  alias Sensocto.AttributeStore
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

    children = [
      %{
        id: :sensor,
        start: {SimpleSensor, :start_link, [configuration]},
        # start: {SimpleSensor, :start_link, [{:via, Registry, {SimpleSensorRegistry, configuration.sensor_id}}]},
        shutdown: 5000,
        restart: :permanent,
        type: :worker
      },
      %{
        id: :attribute_store,
        start: {AttributeStore, :start_link, [configuration]},
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
