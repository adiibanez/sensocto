defmodule Sensocto.RegistryUtils do
  require Logger

  def list_all_entries(registry_module) do
    Registry.select(registry_module, [{{:"$1", :_, :_}, [], [:"$1"]}])
    # |> Enum.flat_map(& &1)
  end

  def list_all_relevant_registries() do
    %{
      :sensor_pairs => Sensocto.RegistryUtils.list_all_entries(Sensocto.SensorPairRegistry),
      :sensors => Sensocto.RegistryUtils.list_all_entries(Sensocto.SimpleSensorRegistry),
      :attributestores =>
        Sensocto.RegistryUtils.list_all_entries(Sensocto.SimpleAttributeRegistry)
    }
  end
end
