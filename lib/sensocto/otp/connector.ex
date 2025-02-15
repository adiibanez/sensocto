defmodule Sensocto.Otp.Connector do
  use Sensocto.Utils.OtpDsl.Genserver,
    initial_state: %{},
    register: :connector

  defcall put(key, value), kv_store do
    reply(value, Map.put(kv_store, key, value))
  end

  defcall get(key), kv_store do
    reply(Map.get(kv_store, key), kv_store)
  end

  @spec init(map()) :: {:ok, %{:message_timestamps => [], optional(any()) => any()}}
  def init(state) do
    Logger.debug("#{__MODULE__} state: #{inspect(state)}")
    # Initialize message counter and schedule mps calculation
    # state =
    #  Map.merge(state, %{message_timestamps: []})
    #  |> Map.put(:mps_interval, 5000)

    # schedule_mps_calculation()
    {:ok, state}
  end

  defp via_tuple(sensor_id) do
    # Sensocto.RegistryUtils.via_dynamic_registry(SimpleSensorRegistry, sensor_id)
    {:via, Registry, {Sensocto.TestRegistry, sensor_id}}
  end
end
