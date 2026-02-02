defmodule Sensocto.AttributeStoreTiered.TableOwner do
  @moduledoc """
  Singleton GenServer that owns the ETS tables for attribute storage.

  Started early in the supervision tree to ensure tables exist before
  any sensors start. The actual data operations bypass this process
  entirely - it only exists for table ownership.
  """
  use GenServer
  require Logger

  @hot_table :attribute_store_hot
  @warm_table :attribute_store_warm
  @sensors_table :attribute_store_sensors

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("AttributeStoreTiered.TableOwner starting, creating ETS tables")
    ensure_tables()
    {:ok, %{}}
  end

  @doc """
  Ensure all ETS tables exist. Idempotent - safe to call multiple times.
  """
  def ensure_tables do
    ensure_table(@hot_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    ensure_table(@warm_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    ensure_table(@sensors_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    :ok
  end

  defp ensure_table(name, opts) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, opts)
      Logger.debug("Created ETS table: #{name}")
    end
  end
end
