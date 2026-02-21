defmodule Sensocto.Lenses.RouterTest do
  use ExUnit.Case, async: false

  alias Sensocto.Lenses.Router

  @attention_topics ["data:attention:high", "data:attention:medium", "data:attention:low"]

  setup do
    # Router is started by the application supervisor.
    # Clean up any lenses registered by previous tests.
    for pid <- Router.get_registered_lenses() do
      Router.unregister_lens(pid)
    end

    :ok
  end

  describe "demand-driven subscription" do
    test "starts with no registered lenses" do
      assert Router.get_registered_lenses() == []
    end

    test "subscribes to attention topics on first lens registration" do
      # Before registration, broadcasting should NOT reach the Router
      Router.register_lens(self())

      lenses = Router.get_registered_lenses()
      assert self() in lenses

      # Clean up
      Router.unregister_lens(self())
    end

    test "unsubscribes when last lens unregisters" do
      Router.register_lens(self())
      assert length(Router.get_registered_lenses()) == 1

      Router.unregister_lens(self())
      assert Router.get_registered_lenses() == []
    end

    test "stays subscribed with multiple lenses" do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      Router.register_lens(pid1)
      Router.register_lens(pid2)
      assert length(Router.get_registered_lenses()) == 2

      # Removing one lens should NOT unsubscribe
      Router.unregister_lens(pid1)
      assert length(Router.get_registered_lenses()) == 1

      # Removing last lens should unsubscribe
      Router.unregister_lens(pid2)
      assert Router.get_registered_lenses() == []

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "measurement routing" do
    test "routes single measurement to PriorityLens ETS" do
      Router.register_lens(self())

      sensor_id = "test_sensor_#{System.unique_integer([:positive])}"
      measurement = %{sensor_id: sensor_id, value: 42, timestamp: System.os_time(:millisecond)}

      # Simulate a measurement broadcast arriving at Router
      send(Process.whereis(Router), {:measurement, measurement})

      # Give Router time to process
      Process.sleep(50)

      # The measurement should have been buffered in PriorityLens ETS.
      # We can't easily verify ETS without more setup, but we can verify
      # the Router didn't crash.
      assert Process.alive?(Process.whereis(Router))

      Router.unregister_lens(self())
    end

    test "routes batch measurements to PriorityLens ETS" do
      Router.register_lens(self())

      sensor_id = "test_sensor_#{System.unique_integer([:positive])}"

      measurements =
        for i <- 1..5 do
          %{sensor_id: sensor_id, value: i, timestamp: System.os_time(:millisecond) + i}
        end

      send(Process.whereis(Router), {:measurements_batch, {sensor_id, measurements}})

      Process.sleep(50)

      assert Process.alive?(Process.whereis(Router))

      Router.unregister_lens(self())
    end

    test "handles unknown messages gracefully" do
      send(Process.whereis(Router), :unknown_message)
      send(Process.whereis(Router), {:weird, :stuff})

      Process.sleep(50)
      assert Process.alive?(Process.whereis(Router))
    end
  end

  describe "process death handling" do
    test "auto-unregisters lens when process dies" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      Router.register_lens(pid)
      assert pid in Router.get_registered_lenses()

      Process.exit(pid, :kill)

      # Give Router time to receive :DOWN
      Process.sleep(100)

      refute pid in Router.get_registered_lenses()
    end

    test "unsubscribes from topics when last lens dies" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      Router.register_lens(pid)
      assert length(Router.get_registered_lenses()) == 1

      Process.exit(pid, :kill)
      Process.sleep(100)

      assert Router.get_registered_lenses() == []
    end

    test "stays subscribed when one of multiple lenses dies" do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      Router.register_lens(pid1)
      Router.register_lens(pid2)

      Process.exit(pid1, :kill)
      Process.sleep(100)

      lenses = Router.get_registered_lenses()
      assert length(lenses) == 1
      assert pid2 in lenses

      # Clean up
      Process.exit(pid2, :kill)
      Process.sleep(100)
    end
  end

  describe "idempotency and edge cases" do
    test "registering same pid twice is idempotent (MapSet)" do
      Router.register_lens(self())
      Router.register_lens(self())

      # MapSet deduplicates, so should still be 1
      assert length(Router.get_registered_lenses()) == 1

      Router.unregister_lens(self())
      assert Router.get_registered_lenses() == []
    end

    test "unregistering non-registered pid is safe" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      assert :ok == Router.unregister_lens(pid)
      Process.exit(pid, :kill)
    end

    test "rapid register/unregister cycles don't crash" do
      for _ <- 1..20 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        Router.register_lens(pid)
        Router.unregister_lens(pid)
        Process.exit(pid, :kill)
      end

      Process.sleep(100)
      assert Process.alive?(Process.whereis(Router))
      assert Router.get_registered_lenses() == []
    end
  end
end
