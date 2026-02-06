defmodule SensoctoWeb.HealthController do
  @moduledoc """
  Health check endpoints for load balancers and orchestrators.

  Provides:
  - GET /health/live - Shallow liveness check (BEAM is responsive)
  - GET /health/ready - Deep readiness check (database, PubSub, supervisors)
  """
  use SensoctoWeb, :controller
  require Logger

  @doc """
  GET /health/live

  Shallow health check for load balancers.
  Returns 200 if the BEAM is responsive.
  """
  def liveness(conn, _params) do
    json(conn, %{
      status: "ok",
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  GET /health/ready

  Deep health check for orchestrators.
  Checks database, PubSub, and critical processes.
  """
  def readiness(conn, _params) do
    checks = %{
      database: check_database(),
      pubsub: check_pubsub(),
      supervisors: check_supervisors(),
      system_load: get_system_load(),
      iroh: check_iroh(),
      ets_tables: check_ets_tables()
    }

    all_healthy = Enum.all?(checks, fn {_k, v} -> v.healthy end)
    status_code = if all_healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_healthy, do: "healthy", else: "degraded"),
      checks: checks,
      timestamp: DateTime.utc_now()
    })
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp check_database do
    start_time = System.monotonic_time(:millisecond)

    try do
      Sensocto.Repo.query!("SELECT 1", [], timeout: 5000)
      latency_ms = System.monotonic_time(:millisecond) - start_time
      %{healthy: true, latency_ms: latency_ms}
    rescue
      e ->
        Logger.warning("Health check: database unhealthy - #{inspect(e)}")
        %{healthy: false, error: Exception.message(e)}
    catch
      :exit, reason ->
        Logger.warning("Health check: database exit - #{inspect(reason)}")
        %{healthy: false, error: "connection_timeout"}
    end
  end

  defp check_pubsub do
    ref = make_ref()
    topic = "health_check:#{inspect(ref)}"

    try do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
      Phoenix.PubSub.broadcast(Sensocto.PubSub, topic, {:ping, ref})

      receive do
        {:ping, ^ref} ->
          Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
          %{healthy: true}
      after
        1000 ->
          Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
          %{healthy: false, error: "timeout"}
      end
    rescue
      e ->
        Logger.warning("Health check: pubsub unhealthy - #{inspect(e)}")
        %{healthy: false, error: Exception.message(e)}
    end
  end

  defp check_supervisors do
    critical_supervisors = [
      Sensocto.Infrastructure.Supervisor,
      Sensocto.Registry.Supervisor,
      Sensocto.Domain.Supervisor
    ]

    results =
      Enum.map(critical_supervisors, fn sup ->
        status =
          case Process.whereis(sup) do
            pid when is_pid(pid) -> :alive
            nil -> :dead
          end

        {sup, status}
      end)

    all_alive = Enum.all?(results, fn {_, status} -> status == :alive end)

    details =
      results
      |> Enum.map(fn {sup, status} -> {inspect(sup), status} end)
      |> Map.new()

    %{healthy: all_alive, details: details}
  end

  defp check_iroh do
    crdt_ready =
      try do
        Sensocto.Iroh.RoomStateCRDT.ready?()
      catch
        :exit, _ -> false
      end

    store_ready =
      try do
        Sensocto.Iroh.RoomStore.ready?()
      catch
        :exit, _ -> false
      end

    # Iroh is optional/secondary - mark healthy even when not ready
    %{healthy: true, crdt_ready: crdt_ready, store_ready: store_ready}
  end

  defp check_ets_tables do
    critical_tables = [:attribute_store_hot, :attribute_store_warm, :attribute_store_sensors]

    results =
      Enum.map(critical_tables, fn table ->
        {table, :ets.whereis(table) != :undefined}
      end)

    all_exist = Enum.all?(results, fn {_table, exists} -> exists end)
    details = Map.new(results)

    %{healthy: all_exist, details: details}
  end

  defp get_system_load do
    try do
      metrics = Sensocto.SystemLoadMonitor.get_metrics()
      level = metrics.load_level

      %{
        healthy: level != :critical,
        level: level,
        scheduler_utilization: Float.round(metrics.scheduler_utilization * 100, 1),
        memory_pressure: Float.round(metrics.memory_pressure * 100, 1),
        pubsub_pressure: Float.round(metrics.pubsub_pressure * 100, 1),
        message_queue_pressure: Float.round(metrics.message_queue_pressure * 100, 1)
      }
    rescue
      _ ->
        # SystemLoadMonitor might not be running in tests
        %{healthy: true, level: :unknown, error: "monitor_unavailable"}
    catch
      :exit, _ ->
        %{healthy: true, level: :unknown, error: "monitor_unavailable"}
    end
  end
end
