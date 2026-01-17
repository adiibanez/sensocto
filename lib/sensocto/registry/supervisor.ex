defmodule Sensocto.Registry.Supervisor do
  @moduledoc """
  Supervisor for all Registry processes used for process lookup.

  ## Failure Isolation Strategy

  Registries are lightweight, in-memory key-value stores for process discovery.
  They are fundamentally independent of each other - sensor registries don't
  affect room registries.

  Uses `:one_for_one` because:
  - Each registry is a separate namespace with no dependencies between them
  - A registry crash only affects lookups in that domain
  - Processes registered in a crashed registry re-register on restart

  ## Registry Categories

  **Sensor Domain:**
  - `TestRegistry` - Development/testing
  - `Sensors.Registry` - Legacy sensor registry
  - `Sensors.SensorRegistry` - Sensor process lookup
  - `SimpleAttributeRegistry` - Sensor attribute processes
  - `SimpleSensorRegistry` - Simple sensor processes
  - `SensorPairRegistry` - Sensor pair coordination

  **Room Domain (Local):**
  - `RoomRegistry` - Local room process lookup
  - `RoomJoinCodeRegistry` - Join code to room mapping

  **Room Domain (Distributed - Horde):**
  - `DistributedRoomRegistry` - Cluster-wide room lookup
  - `DistributedJoinCodeRegistry` - Cluster-wide join code lookup

  **Feature Domains:**
  - `CallRegistry` - Video/voice call processes
  - `MediaRegistry` - Media player processes
  - `Object3DRegistry` - 3D viewer processes

  ## Blast Radius

  If this supervisor exhausts its restart budget (unlikely for registries),
  the root supervisor restarts it. All dynamic supervisors that depend on
  registries for lookup will lose their registry references momentarily,
  but processes survive and re-register on registry restart.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Development/testing registry
      {Registry, keys: :unique, name: Sensocto.TestRegistry},

      # Sensor domain registries
      {Registry, keys: :unique, name: Sensocto.Sensors.Registry},
      {Registry, keys: :unique, name: Sensocto.Sensors.SensorRegistry},
      {Registry, keys: :unique, name: Sensocto.SimpleAttributeRegistry},
      {Registry, keys: :unique, name: Sensocto.SimpleSensorRegistry},
      {Registry, keys: :unique, name: Sensocto.SensorPairRegistry},

      # Room domain - local registries (backward compatibility)
      {Registry, keys: :unique, name: Sensocto.RoomRegistry},
      {Registry, keys: :unique, name: Sensocto.RoomJoinCodeRegistry},

      # Room domain - distributed registries (Horde for cluster-wide lookups)
      {Horde.Registry, [name: Sensocto.DistributedRoomRegistry, keys: :unique, members: :auto]},
      {Horde.Registry,
       [name: Sensocto.DistributedJoinCodeRegistry, keys: :unique, members: :auto]},

      # Feature domain registries
      {Registry, keys: :unique, name: Sensocto.CallRegistry},
      {Registry, keys: :unique, name: Sensocto.MediaRegistry},
      {Registry, keys: :unique, name: Sensocto.Object3DRegistry}
    ]

    # one_for_one: registries are independent
    # Higher restart tolerance - registries rarely crash
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 5)
  end
end
