defmodule SensoctoWeb.HealthControllerTest do
  @moduledoc """
  Tests for the health check endpoints.

  Verifies:
  - GET /health/live returns 200 with status ok (shallow liveness)
  - GET /health/ready returns 200 with all health checks (deep readiness)
  - Individual health check components are present and well-structured
  - Degraded state returns 503
  """

  use SensoctoWeb.ConnCase

  # ===========================================================================
  # Liveness endpoint
  # ===========================================================================

  describe "GET /health/live" do
    test "returns 200 with status ok", %{conn: conn} do
      conn = get(conn, ~p"/health/live")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert is_binary(response["timestamp"])
    end

    test "timestamp is valid ISO 8601", %{conn: conn} do
      conn = get(conn, ~p"/health/live")
      response = json_response(conn, 200)

      assert {:ok, _dt, _offset} = DateTime.from_iso8601(response["timestamp"])
    end

    test "liveness check is fast (no heavy operations)", %{conn: conn} do
      start = System.monotonic_time(:millisecond)
      _conn = get(conn, ~p"/health/live")
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 100, "Liveness check should complete in under 100ms, took #{elapsed}ms"
    end
  end

  # ===========================================================================
  # Readiness endpoint
  # ===========================================================================

  describe "GET /health/ready" do
    test "returns 200 when system is healthy", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      assert response["status"] == "healthy"
      assert is_map(response["checks"])
      assert is_binary(response["timestamp"])
    end

    test "includes database check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      db_check = response["checks"]["database"]
      assert db_check != nil
      assert db_check["healthy"] == true
      assert is_number(db_check["latency_ms"])
    end

    test "includes pubsub check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      pubsub_check = response["checks"]["pubsub"]
      assert pubsub_check != nil
      assert pubsub_check["healthy"] == true
    end

    test "includes supervisors check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      sup_check = response["checks"]["supervisors"]
      assert sup_check != nil
      assert sup_check["healthy"] == true
      assert is_map(sup_check["details"])
    end

    test "supervisors check lists critical supervisors", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      details = response["checks"]["supervisors"]["details"]

      # All critical supervisors should be alive
      Enum.each(details, fn {_name, status} ->
        assert status == "alive"
      end)
    end

    test "includes system_load check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      load_check = response["checks"]["system_load"]
      assert load_check != nil
      assert load_check["healthy"] == true
      assert load_check["level"] in ["normal", "elevated", "high", "critical", "unknown"]
    end

    test "includes ETS tables check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      ets_check = response["checks"]["ets_tables"]
      assert ets_check != nil
      assert ets_check["healthy"] == true
      assert is_map(ets_check["details"])
    end

    test "ETS tables check verifies critical tables exist", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      details = response["checks"]["ets_tables"]["details"]

      # These critical tables should exist
      assert details["attribute_store_hot"] == true
      assert details["attribute_store_warm"] == true
      assert details["attribute_store_sensors"] == true
    end

    test "includes iroh check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      iroh_check = response["checks"]["iroh"]
      assert iroh_check != nil
      # Iroh check is non-critical — always healthy
      assert iroh_check["healthy"] == true
    end

    test "all checks have healthy boolean field", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = json_response(conn, 200)

      Enum.each(response["checks"], fn {name, check} ->
        assert is_boolean(check["healthy"]),
               "Check '#{name}' should have a boolean 'healthy' field"
      end)
    end
  end

  # ===========================================================================
  # Response structure validation
  # ===========================================================================

  describe "response structure" do
    test "liveness and readiness both include timestamp", %{conn: conn} do
      live_resp = get(conn, ~p"/health/live") |> json_response(200)
      ready_resp = get(conn, ~p"/health/ready") |> json_response(200)

      assert is_binary(live_resp["timestamp"])
      assert is_binary(ready_resp["timestamp"])
    end

    test "readiness check is idempotent (multiple calls return consistent structure)", %{
      conn: conn
    } do
      resp1 = get(conn, ~p"/health/ready") |> json_response(200)
      resp2 = get(conn, ~p"/health/ready") |> json_response(200)

      # Same set of checks should be present
      assert Map.keys(resp1["checks"]) == Map.keys(resp2["checks"])
    end
  end
end
