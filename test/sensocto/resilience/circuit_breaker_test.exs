defmodule Sensocto.Resilience.CircuitBreakerTest do
  @moduledoc """
  Tests for the CircuitBreaker ETS-backed state machine.
  Tests use the application-level :circuit_breakers ETS table.
  """
  use ExUnit.Case, async: false

  alias Sensocto.Resilience.CircuitBreaker

  setup do
    # Use a unique breaker name per test to avoid cross-test interference
    name = :"test_breaker_#{System.unique_integer([:positive])}"
    {:ok, name: name}
  end

  describe "get_state/1" do
    test "returns :closed for unknown breaker", %{name: name} do
      assert CircuitBreaker.get_state(name) == :closed
    end

    test "returns :closed after registration", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)
      assert CircuitBreaker.get_state(name) == :closed
    end
  end

  describe "call/2 in closed state" do
    test "successful call returns {:ok, result}", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)
      assert {:ok, 42} = CircuitBreaker.call(name, fn -> 42 end)
    end

    test "failed call returns {:error, reason}", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)

      assert {:error, %RuntimeError{}} =
               CircuitBreaker.call(name, fn -> raise "boom" end)
    end
  end

  describe "state transitions" do
    test "transitions to :open after threshold failures", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)

      for _ <- 1..3 do
        CircuitBreaker.call(name, fn -> raise "fail" end)
      end

      assert CircuitBreaker.get_state(name) == :open
    end

    test "call returns :circuit_open when open", %{name: name} do
      CircuitBreaker.register(name, 2, 5_000)

      for _ <- 1..2 do
        CircuitBreaker.call(name, fn -> raise "fail" end)
      end

      assert {:error, :circuit_open} = CircuitBreaker.call(name, fn -> :should_not_run end)
    end

    test "transitions to :half_open after timeout", %{name: name} do
      # Use a very short timeout (1ms) for testing
      CircuitBreaker.register(name, 1, 1)
      CircuitBreaker.call(name, fn -> raise "fail" end)

      assert CircuitBreaker.get_state(name) == :open

      # Wait for timeout to elapse
      Process.sleep(5)
      assert CircuitBreaker.get_state(name) == :half_open
    end

    test "call succeeds in half_open state", %{name: name} do
      CircuitBreaker.register(name, 1, 1)
      CircuitBreaker.call(name, fn -> raise "fail" end)
      Process.sleep(5)

      assert CircuitBreaker.get_state(name) == :half_open
      # Call should be allowed through in half_open
      assert {:ok, :recovered} = CircuitBreaker.call(name, fn -> :recovered end)
    end

    test "manual reset works after half_open", %{name: name} do
      CircuitBreaker.register(name, 1, 1)
      CircuitBreaker.call(name, fn -> raise "fail" end)
      Process.sleep(5)

      assert CircuitBreaker.get_state(name) == :half_open
      CircuitBreaker.reset(name)
      assert CircuitBreaker.get_state(name) == :closed
    end
  end

  describe "reset/1" do
    test "resets open breaker to closed", %{name: name} do
      CircuitBreaker.register(name, 1, 60_000)
      CircuitBreaker.call(name, fn -> raise "fail" end)
      assert CircuitBreaker.get_state(name) == :open

      CircuitBreaker.reset(name)
      assert CircuitBreaker.get_state(name) == :closed
    end

    test "no-op for unknown breaker" do
      assert :ok = CircuitBreaker.reset(:nonexistent_breaker)
    end
  end

  describe "get_all_states/0" do
    test "returns map of breaker states", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)
      states = CircuitBreaker.get_all_states()

      assert is_map(states)
      assert states[name] == :closed
    end
  end

  describe "success resets failure count" do
    test "successful call clears failures", %{name: name} do
      CircuitBreaker.register(name, 3, 5_000)

      # 2 failures (below threshold)
      CircuitBreaker.call(name, fn -> raise "fail" end)
      CircuitBreaker.call(name, fn -> raise "fail" end)

      # 1 success should reset
      CircuitBreaker.call(name, fn -> :ok end)

      # 2 more failures should NOT open (reset happened)
      CircuitBreaker.call(name, fn -> raise "fail" end)
      CircuitBreaker.call(name, fn -> raise "fail" end)

      assert CircuitBreaker.get_state(name) == :closed
    end
  end
end
