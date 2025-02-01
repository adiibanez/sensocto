defmodule Sensocto.RegistryUtils do
  require Logger
  alias Horde.Registry

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

  def via_dynamic_registry(registry, via_token) do
    case check_registry_type(registry) do
      {:ok, :elixir_registry, _} ->
        {:via, Registry, {registry, via_token}}

      {:ok, :horde_registry, _} ->
        {:via, Horde.Registry, {registry, via_token}}
    end
  end

  def dynamic_select(registry, select) do
    case check_registry_type(registry) do
      {:ok, :elixir_registry, _} ->
        Registry.select(Sensocto.SensorPairRegistry, select)

      {:ok, :horde_registry, _} ->
        Horde.Registry.select(Sensocto.SensorPairRegistry, select)
    end
  end

  def dynamic_terminat(_supervisor, _module, pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  def dynamic_lookup(registry, lookup) do
    case check_registry_type(registry) do
      {:ok, :elixir_registry, _} ->
        Registry.lookup(Sensocto.SensorPairRegistry, lookup)

      {:ok, :horde_registry, _} ->
        Horde.Registry.lookup(Sensocto.SensorPairRegistry, lookup)
    end
  end

  alias Horde.DynamicSupervisor

  def check_supervisor_type(tuple) do
    IO.inspect(tuple)

    case tuple do
      {:via, _, {supervisor_type, _}} when supervisor_type in [Horde.DynamicSupervisor] ->
        {:ok, :horde_dynamic_supervisor}

      {supervisor_type, _} when supervisor_type in [Horde.DynamicSupervisor] ->
        {:ok, :horde_dynamic_supervisor}

      {:via, _, {supervisor_type, _}} when supervisor_type in [DynamicSupervisor] ->
        {:ok, :dynamic_supervisor}

      {supervisor_type, _} when supervisor_type in [DynamicSupervisor] ->
        {:ok, :dynamic_supervisor}

      _ ->
        :error
    end

    case tuple do
      # {:via, _, {Horde.DynamicSupervisor, _}} ->
      #   {:ok, :horde_dynamic_supervisor}

      {Horde.DynamicSupervisor, _} ->
        {:ok, :horde_dynamic_supervisor}

      # {:via, _, {DynamicSupervisor, _}} ->
      #   {:ok, :dynamic_supervisor}

      # {DynamicSupervisor, _} ->
      #   {:ok, :dynamic_supervisor}

      _ ->
        :error
    end
  end

  def dynamic_start_link(_dynamicsupervisor, module) do
    DynamicSupervisor.start_link(module)

    # case check_supervisor_type(dynamicsupervisor) do
    #   {:ok, :dynamic_supervisor} ->
    #     DynamicSupervisor.start_link(module, :no_args, name: module)

    #   {:ok, :horde_dynamic_supervisor} ->
    #     Horde.DynamicSupervisor.start_link(module, :no_args, name: module)
    # end
  end

  def dynamic_start_child(_dynamicsupervisor, module, child_spec) do
    DynamicSupervisor.start_child(module, child_spec)

    # case check_supervisor_type(dynamicsupervisor) do
    #  {:ok, :dynamic_supervisor} -> DynamicSupervisor.start_child(module, child_spec)
    #  {:ok, :horde_dynamic_supervisor} -> Horde.DynamicSupervisor.start_child(module, child_spec)
    # end
  end

  def check_registry_type(via_tuple) do
    case via_tuple do
      {:via, Registry, {module, _key}}
      when module in [
             Sensocto.SimpleSensorRegistry,
             Sensocto.SensorRegistry,
             Sensocto.SensorAttributeRegistry
           ] ->
        IO.puts("using Elixir Registry")
        {:ok, :elixir_registry, module}

      {:via, Horde.Registry, {module, _key}} ->
        IO.puts("using Horde Registry")
        {:ok, :horde_registry, module}

      _ ->
        :error
    end
  end
end
