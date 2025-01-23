defmodule SensoctoElixirSimulatorTest do
  use ExUnit.Case
  doctest SensoctoElixirSimulator

  test "greets the world" do
    assert SensoctoElixirSimulator.hello() == :world
  end
end
