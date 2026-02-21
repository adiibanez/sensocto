defmodule Sensocto.Simulator.ManagerTest do
  use ExUnit.Case, async: false

  alias Sensocto.Simulator.Manager

  # Manager may not be started in test environment — skip if unavailable
  setup do
    case Process.whereis(Manager) do
      nil -> {:ok, skip: true}
      pid when is_pid(pid) -> {:ok, skip: false}
    end
  end

  defp skip_if_unavailable(%{skip: true}), do: :ok
  defp skip_if_unavailable(_), do: nil

  describe "startup phase" do
    test "reports :ready after initial startup", ctx do
      unless skip_if_unavailable(ctx) do
        assert Manager.startup_phase() == :ready
      end
    end

    test "startup_phase returns :loading_config when process is not alive" do
      # When Manager is not running, startup_phase catches the exit and returns :loading_config
      if Process.whereis(Manager) == nil do
        assert Manager.startup_phase() == :loading_config
      end
    end
  end

  describe "state queries" do
    test "get_state returns Manager struct", ctx do
      unless skip_if_unavailable(ctx) do
        state = Manager.get_state()
        assert %Manager{} = state
        assert is_map(state.connectors)
        assert is_map(state.running_scenarios)
        assert is_list(state.available_scenarios)
      end
    end

    test "list_connectors returns list of connector IDs", ctx do
      unless skip_if_unavailable(ctx) do
        connectors = Manager.list_connectors()
        assert is_list(connectors)
      end
    end

    test "get_connectors returns map with status info", ctx do
      unless skip_if_unavailable(ctx) do
        connectors = Manager.get_connectors()
        assert is_map(connectors)

        for {_id, info} <- connectors do
          assert Map.has_key?(info, :name)
          assert Map.has_key?(info, :status)
          assert Map.has_key?(info, :sensors)
          assert info.status in [:running, :stopped]
        end
      end
    end

    test "get_config returns raw config map", ctx do
      unless skip_if_unavailable(ctx) do
        config = Manager.get_config()
        assert is_map(config)
      end
    end
  end

  describe "scenario discovery" do
    test "list_scenarios returns available scenarios", ctx do
      unless skip_if_unavailable(ctx) do
        scenarios = Manager.list_scenarios()
        assert is_list(scenarios)

        for scenario <- scenarios do
          assert Map.has_key?(scenario, :name)
          assert Map.has_key?(scenario, :path)
          assert Map.has_key?(scenario, :sensor_count)
          assert Map.has_key?(scenario, :attribute_count)
          assert is_binary(scenario.name)
          assert is_binary(scenario.path)
          assert is_integer(scenario.sensor_count)
          assert is_integer(scenario.attribute_count)
        end
      end
    end

    test "scenarios are sorted by attribute count", ctx do
      unless skip_if_unavailable(ctx) do
        scenarios = Manager.list_scenarios()

        if length(scenarios) > 1 do
          counts = Enum.map(scenarios, & &1.attribute_count)
          assert counts == Enum.sort(counts)
        end
      end
    end
  end

  describe "running scenarios" do
    test "get_running_scenarios returns map", ctx do
      unless skip_if_unavailable(ctx) do
        running = Manager.get_running_scenarios()
        assert is_map(running)

        for {name, info} <- running do
          assert is_binary(name)
          assert Map.has_key?(info, :room_id)
          assert Map.has_key?(info, :connector_ids)
          assert is_list(info.connector_ids)
        end
      end
    end

    test "get_current_scenario returns first running scenario or nil", ctx do
      unless skip_if_unavailable(ctx) do
        result = Manager.get_current_scenario()
        assert is_nil(result) or is_binary(result)
      end
    end
  end

  describe "scenario lifecycle" do
    test "starting non-existent scenario returns error", ctx do
      unless skip_if_unavailable(ctx) do
        assert {:error, :scenario_not_found} = Manager.start_scenario("nonexistent_scenario_xyz")
      end
    end

    test "stopping non-running scenario returns error", ctx do
      unless skip_if_unavailable(ctx) do
        assert {:error, :not_running} = Manager.stop_scenario("nonexistent_scenario_xyz")
      end
    end

    test "switching to non-existent scenario returns error", ctx do
      unless skip_if_unavailable(ctx) do
        assert {:error, :scenario_not_found} =
                 Manager.switch_scenario("nonexistent_scenario_xyz")
      end
    end

    test "starting already-running scenario returns error", ctx do
      unless skip_if_unavailable(ctx) do
        running = Manager.get_running_scenarios()

        if map_size(running) > 0 do
          scenario_name = running |> Map.keys() |> List.first()
          assert {:error, :already_running} = Manager.start_scenario(scenario_name)
        end
      end
    end
  end

  describe "connector operations" do
    test "stopping non-existent connector doesn't crash", ctx do
      unless skip_if_unavailable(ctx) do
        assert :ok = Manager.stop_connector("nonexistent_connector_xyz")
      end
    end

    test "starting non-existent connector returns error", ctx do
      unless skip_if_unavailable(ctx) do
        assert {:error, :not_found} = Manager.start_connector("nonexistent_connector_xyz")
      end
    end
  end

  describe "config reload" do
    test "reload_config succeeds without crashing", ctx do
      unless skip_if_unavailable(ctx) do
        assert :ok = Manager.reload_config()
        assert Manager.startup_phase() == :ready
      end
    end

    test "scenarios are rediscovered after reload", ctx do
      unless skip_if_unavailable(ctx) do
        scenarios_before = Manager.list_scenarios()
        Manager.reload_config()
        scenarios_after = Manager.list_scenarios()

        assert length(scenarios_before) == length(scenarios_after)
      end
    end
  end

  describe "health check resilience" do
    test "Manager stays alive after health check", ctx do
      unless skip_if_unavailable(ctx) do
        send(Process.whereis(Manager), :health_check)
        Process.sleep(100)

        assert Process.alive?(Process.whereis(Manager))
        assert Manager.startup_phase() == :ready
      end
    end
  end
end
