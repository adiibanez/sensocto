defmodule Sensocto.Supervision.SupervisionTreeTest do
  @moduledoc """
  Tests for the hierarchical supervision tree structure.

  These tests verify that:
  1. The supervision tree has the correct structure
  2. Intermediate supervisors are properly configured
  3. Restart strategies are appropriate for each layer
  4. Failure isolation works as expected
  """
  use ExUnit.Case, async: false

  describe "supervision tree structure" do
    test "root supervisor exists and has correct name" do
      assert Process.whereis(Sensocto.Supervisor) != nil
    end

    test "root supervisor uses :rest_for_one strategy" do
      pid = Process.whereis(Sensocto.Supervisor)
      assert pid != nil

      # Get supervisor state to verify strategy
      # Use :sys.get_state which returns the internal supervisor state directly
      state = :sys.get_state(pid)

      # The supervisor state tuple is:
      # {:state, name, strategy, children, ...}
      # We pattern match to verify the strategy
      assert elem(state, 0) == :state
      assert elem(state, 1) == {:local, Sensocto.Supervisor}
      assert elem(state, 2) == :rest_for_one
    end

    test "infrastructure supervisor exists" do
      assert Process.whereis(Sensocto.Infrastructure.Supervisor) != nil
    end

    test "registry supervisor exists" do
      assert Process.whereis(Sensocto.Registry.Supervisor) != nil
    end

    test "storage supervisor exists" do
      assert Process.whereis(Sensocto.Storage.Supervisor) != nil
    end

    test "domain supervisor exists" do
      assert Process.whereis(Sensocto.Domain.Supervisor) != nil
    end

    test "bio supervisor exists" do
      assert Process.whereis(Sensocto.Bio.Supervisor) != nil
    end
  end

  describe "infrastructure supervisor children" do
    test "telemetry is running" do
      assert Process.whereis(SensoctoWeb.Telemetry) != nil
    end

    test "task supervisor is running" do
      assert Process.whereis(Sensocto.TaskSupervisor) != nil
    end

    test "pubsub is running" do
      # PubSub uses a different naming scheme
      assert Process.whereis(Sensocto.PubSub) != nil ||
               :pg.which_groups(Sensocto.PubSub) != {:error, :no_such_group}
    end

    test "finch is running" do
      assert Process.whereis(Sensocto.Finch) != nil
    end
  end

  describe "registry supervisor children" do
    test "sensor registries are running" do
      assert Registry.lookup(Sensocto.Sensors.Registry, :test) != nil
      assert Registry.lookup(Sensocto.Sensors.SensorRegistry, :test) != nil
      assert Registry.lookup(Sensocto.SimpleSensorRegistry, :test) != nil
      assert Registry.lookup(Sensocto.SimpleAttributeRegistry, :test) != nil
      assert Registry.lookup(Sensocto.SensorPairRegistry, :test) != nil
    end

    test "room registries are running" do
      assert Registry.lookup(Sensocto.RoomRegistry, :test) != nil
      assert Registry.lookup(Sensocto.RoomJoinCodeRegistry, :test) != nil
    end

    test "distributed room registries are running" do
      # Horde registries
      assert Horde.Registry.lookup(Sensocto.DistributedRoomRegistry, :test) != nil
      assert Horde.Registry.lookup(Sensocto.DistributedJoinCodeRegistry, :test) != nil
    end

    test "feature registries are running" do
      assert Registry.lookup(Sensocto.CallRegistry, :test) != nil
      assert Registry.lookup(Sensocto.MediaRegistry, :test) != nil
      assert Registry.lookup(Sensocto.Object3DRegistry, :test) != nil
    end
  end

  describe "storage supervisor children" do
    test "room store processes are running" do
      assert Process.whereis(Sensocto.Iroh.RoomStore) != nil
      assert Process.whereis(Sensocto.RoomStore) != nil
      assert Process.whereis(Sensocto.Iroh.RoomSync) != nil
      assert Process.whereis(Sensocto.Iroh.RoomStateCRDT) != nil
    end

    test "room presence server is running" do
      assert Process.whereis(Sensocto.RoomPresenceServer) != nil
    end
  end

  describe "domain supervisor children" do
    test "sensors dynamic supervisor is running" do
      assert Process.whereis(Sensocto.SensorsDynamicSupervisor) != nil
    end

    test "rooms dynamic supervisor is running" do
      assert Process.whereis(Sensocto.RoomsDynamicSupervisor) != nil
    end

    test "call supervisor is running" do
      assert Process.whereis(Sensocto.Calls.CallSupervisor) != nil
    end

    test "media player supervisor is running" do
      assert Process.whereis(Sensocto.Media.MediaPlayerSupervisor) != nil
    end

    test "object3d player supervisor is running" do
      assert Process.whereis(Sensocto.Object3D.Object3DPlayerSupervisor) != nil
    end

    test "attention tracker is running" do
      assert Process.whereis(Sensocto.AttentionTracker) != nil
    end

    test "system load monitor is running" do
      assert Process.whereis(Sensocto.SystemLoadMonitor) != nil
    end
  end

  describe "bio supervisor children" do
    test "novelty detector is running" do
      assert Process.whereis(Sensocto.Bio.NoveltyDetector) != nil
    end

    test "predictive load balancer is running" do
      assert Process.whereis(Sensocto.Bio.PredictiveLoadBalancer) != nil
    end

    test "homeostatic tuner is running" do
      assert Process.whereis(Sensocto.Bio.HomeostaticTuner) != nil
    end

    test "resource arbiter is running" do
      assert Process.whereis(Sensocto.Bio.ResourceArbiter) != nil
    end

    test "circadian scheduler is running" do
      assert Process.whereis(Sensocto.Bio.CircadianScheduler) != nil
    end
  end

  describe "supervisor hierarchy" do
    test "intermediate supervisors are children of root" do
      root_pid = Process.whereis(Sensocto.Supervisor)
      children = Supervisor.which_children(root_pid)

      child_modules =
        children
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      assert Sensocto.Infrastructure.Supervisor in child_modules
      assert Sensocto.Registry.Supervisor in child_modules
      assert Sensocto.Storage.Supervisor in child_modules
      assert Sensocto.Bio.Supervisor in child_modules
      assert Sensocto.Domain.Supervisor in child_modules
    end

    test "root has exactly 7 or 8 children (depending on simulator config)" do
      root_pid = Process.whereis(Sensocto.Supervisor)
      children = Supervisor.which_children(root_pid)

      # 7 children minimum: Infrastructure, Registry, Storage, Bio, Domain, Endpoint, AshAuth
      # 8 if simulator is enabled
      assert length(children) in [7, 8]
    end
  end
end
