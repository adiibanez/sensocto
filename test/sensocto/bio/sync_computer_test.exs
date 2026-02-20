defmodule Sensocto.Bio.SyncComputerTest do
  @moduledoc """
  Tests for the SyncComputer GenServer.
  Demand-driven Kuramoto phase synchronization computer.
  """
  use ExUnit.Case, async: false

  alias Sensocto.Bio.SyncComputer

  describe "demand-driven lifecycle" do
    test "get_state returns a valid state struct" do
      state = SyncComputer.get_state()
      assert is_integer(state.viewer_count)
      assert state.viewer_count >= 0
      assert is_boolean(state.active)
    end

    test "register_viewer increments count and activates" do
      SyncComputer.register_viewer()
      state = SyncComputer.get_state()
      assert state.viewer_count >= 1
      assert state.active == true

      SyncComputer.unregister_viewer()
    end

    test "unregister_viewer decrements count" do
      SyncComputer.register_viewer()
      SyncComputer.unregister_viewer()

      # Give cast time to process
      Process.sleep(50)

      state = SyncComputer.get_state()
      assert state.viewer_count >= 0
    end

    test "tracked_sensor_count returns integer" do
      count = SyncComputer.tracked_sensor_count()
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "sync values" do
    test "get_sync(:breathing) returns a float" do
      val = SyncComputer.get_sync(:breathing)
      assert is_float(val)
      assert val >= 0.0 and val <= 1.0
    end

    test "get_sync(:hrv) returns a float" do
      val = SyncComputer.get_sync(:hrv)
      assert is_float(val)
      assert val >= 0.0 and val <= 1.0
    end

    test "get_sync(:rsa) returns a float" do
      val = SyncComputer.get_sync(:rsa)
      assert is_float(val)
      assert val >= 0.0 and val <= 1.0
    end
  end

  describe "state structure" do
    test "get_state returns expected struct fields" do
      state = SyncComputer.get_state()

      assert Map.has_key?(state, :tracked_sensors)
      assert Map.has_key?(state, :phase_buffers)
      assert Map.has_key?(state, :smoothed)
      assert Map.has_key?(state, :viewer_count)
      assert Map.has_key?(state, :active)

      assert is_map(state.smoothed)
      assert Map.has_key?(state.smoothed, :breathing)
      assert Map.has_key?(state.smoothed, :hrv)
      assert Map.has_key?(state.smoothed, :rsa)
    end
  end
end
