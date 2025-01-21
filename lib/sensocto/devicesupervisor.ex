defmodule Sensocto.DeviceSupervisor do
  use DynamicSupervisor
  alias Sensocto.Device
  require Logger

  ########################
  # SUPERVISOR CALLBACKS #
  ########################

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ##############
  # CLIENT API #
  ##############

  def add_device(device_id) do
    # IO.inspect(via_tuple(device_id))
    Logger.debug("Starting device_id: #{device_id}")

    child_spec = %{
      id: device_id,
      start: {Device, :start_link, [via_tuple(device_id)]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }

    IO.inspect(child_spec)

    # Enum.each(children, fn (c) -> Logger.debug(%{"msg": "children map", "cnt": Sensocto.Registry.whereis_name("7facc584-05b9-4dca-b4ff-c988838a89a6")}) end)
    # IO.inspect(Sensocto.Registry.whereis_name("a2e235f9-14df-4abf-8583-9eaa92e8aad6"))

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      # case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      # case DynamicSupervisor.start_child(__MODULE__, {Device, :device_id: device_id}) do
      {:ok, pid} when is_pid(pid) ->
        Logger.debug("Device started #{device_id}")
        {:ok, "#{device_id}"}

      {:error, {:already_started, _pid}} ->
        Logger.debug("Device already started #{device_id}")
        {:ok, "#{device_id}"}

      {:error, reason} ->
        Logger.debug("Device error?")
        IO.inspect(reason)
        {:error, "Other error"}
    end
  end

  # Terminate a Player process and remove it from supervision
  def remove_device(device_id) do
    # DynamicSupervisor.terminate_child(__MODULE__, via_tuple(device_id))

    case Registry.lookup(Sensocto.Registry, device_id) do
      # Successfully retrieved PID
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      # No process registered with that device_id
      [] ->
        # or handle the error appropriately
        :error
    end
  end

  # Registry.lookup(Registry.ViaTest, "agent")
  def get_device_names do
    Registry.select(Sensocto.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # Function to extract device names (IDs) from the children list
  def get_device_names2 do
    IO.inspect(children())

    Enum.map(children(), fn
      {:undefined, pid, :worker, [Sensocto.Device]} ->
        # You can extract device ID here based on how it's registered
        # For example, assuming the device is registered with `{:via, Sensocto.Registry, device_id}`
        case Process.info(pid, :registered_name) do
          {:registered_name, device_id} ->
            device_id

          _ ->
            Logger.debug("nope")
        end

      _ ->
        Logger.debug("test")
    end)
    # Filter out nil values (if the process name is not found)
    |> Enum.filter(& &1)
  end

  # Nice utility method to check which processes are under supervision
  def children do
    DynamicSupervisor.which_children(__MODULE__)
  end

  # Nice utility method to check which processes are under supervision
  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end

  def via_tuple(device_id) do
    Logger.debug("via_tuple device_id: #{device_id}")
    test = {:via, Registry, {Sensocto.Registry, device_id}}
    IO.inspect(test)
    test
  end
end
