defmodule Sensocto.Resilience.CircuitBreaker.TableOwner do
  @moduledoc """
  GenServer that owns the `:circuit_breakers` ETS table.

  Follows the same pattern as `AttributeStoreTiered.TableOwner` -
  exists solely for table ownership. All data operations go directly
  through `CircuitBreaker` module functions.
  """
  use GenServer
  require Logger

  alias Sensocto.Resilience.CircuitBreaker

  @table :circuit_breakers

  # Default breaker configurations: {name, failure_threshold, timeout_ms}
  @default_breakers [
    {:iroh_nif, 5, 30_000},
    {:iroh_docs, 5, 30_000}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    end

    Enum.each(@default_breakers, fn {name, threshold, timeout_ms} ->
      CircuitBreaker.register(name, threshold, timeout_ms)
    end)

    Logger.info(
      "[CircuitBreaker] Table owner started, registered #{length(@default_breakers)} breakers"
    )

    {:ok, %{}}
  end
end
