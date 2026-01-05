defmodule Sensocto.Otp.RepoReplicatorPool do
  @moduledoc """
  Supervisor for a pool of RepoReplicator workers.

  Uses consistent hashing to distribute sensors across workers, preventing
  a single process from becoming a bottleneck when subscribing to many sensors.

  Each worker handles a subset of sensors based on hash(sensor_id) % pool_size.
  """
  use Supervisor
  require Logger

  @default_pool_size 8

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)

    # Store pool size in persistent term for fast access
    :persistent_term.put({__MODULE__, :pool_size}, pool_size)

    children =
      for index <- 0..(pool_size - 1) do
        Supervisor.child_spec(
          {Sensocto.Otp.RepoReplicatorWorker, index: index},
          id: {Sensocto.Otp.RepoReplicatorWorker, index}
        )
      end

    Logger.info("Starting RepoReplicatorPool with #{pool_size} workers")
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Subscribe a sensor to a worker based on consistent hashing.
  """
  def sensor_up(sensor_id) do
    worker = get_worker_for_sensor(sensor_id)
    GenServer.cast(worker, {:sensor_up, sensor_id})
  end

  @doc """
  Unsubscribe a sensor from its assigned worker.
  """
  def sensor_down(sensor_id) do
    worker = get_worker_for_sensor(sensor_id)
    GenServer.cast(worker, {:sensor_down, sensor_id})
  end

  @doc """
  Get the worker process name for a given sensor_id using consistent hashing.
  """
  def get_worker_for_sensor(sensor_id) do
    pool_size = :persistent_term.get({__MODULE__, :pool_size}, @default_pool_size)
    index = :erlang.phash2(sensor_id, pool_size)
    Sensocto.Otp.RepoReplicatorWorker.worker_name(index)
  end

  @doc """
  Returns the current pool size.
  """
  def pool_size do
    :persistent_term.get({__MODULE__, :pool_size}, @default_pool_size)
  end

  @doc """
  Returns stats for all workers in the pool.
  """
  def stats do
    pool_size = pool_size()

    for index <- 0..(pool_size - 1) do
      worker = Sensocto.Otp.RepoReplicatorWorker.worker_name(index)

      case GenServer.call(worker, :stats, 5000) do
        stats -> {index, stats}
      end
    end
  end
end
