defmodule Sensocto.AttentionTracker.TableOwner do
  @moduledoc """
  Owns the AttentionTracker ETS tables so they survive tracker crashes.

  Follows the same pattern as `CircuitBreaker.TableOwner` and
  `AttributeStoreTiered.TableOwner` - exists solely for table ownership.
  All data operations go through `AttentionTracker` module functions.
  """
  use GenServer
  require Logger

  @attention_levels_table :attention_levels_cache
  @attention_config_table :attention_config_cache
  @sensor_attention_table :sensor_attention_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    create_table_if_missing(@attention_levels_table)
    create_table_if_missing(@attention_config_table)
    create_table_if_missing(@sensor_attention_table)

    Logger.info("[AttentionTracker] Table owner started, 3 ETS tables created")
    {:ok, %{}}
  end

  defp create_table_if_missing(name) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:set, :named_table, :public, read_concurrency: true])
    end
  end
end
