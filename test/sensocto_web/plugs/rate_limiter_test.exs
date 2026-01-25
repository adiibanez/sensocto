defmodule SensoctoWeb.Plugs.RateLimiterTest do
  use SensoctoWeb.ConnCase, async: false

  alias SensoctoWeb.Plugs.RateLimiter

  # Enable rate limiting for these tests
  setup do
    # Store original config
    original_env = Application.get_env(:sensocto, :env)
    original_enable = Application.get_env(:sensocto, :enable_rate_limiting_in_test)

    # Enable rate limiting for tests
    Application.put_env(:sensocto, :env, :test)
    Application.put_env(:sensocto, :enable_rate_limiting_in_test, true)

    # Clean up ETS table between tests
    case :ets.whereis(:sensocto_rate_limiter) do
      :undefined -> :ok
      _ref -> :ets.delete_all_objects(:sensocto_rate_limiter)
    end

    on_exit(fn ->
      # Restore original config
      if original_env do
        Application.put_env(:sensocto, :env, original_env)
      end

      if original_enable do
        Application.put_env(:sensocto, :enable_rate_limiting_in_test, original_enable)
      end

      # Clean up ETS table
      case :ets.whereis(:sensocto_rate_limiter) do
        :undefined -> :ok
        _ref -> :ets.delete_all_objects(:sensocto_rate_limiter)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with default auth type" do
      opts = RateLimiter.init([])
      assert opts.type == :auth
      assert opts.limit == 10
      assert opts.window_ms == 60_000
    end

    test "initializes with registration type" do
      opts = RateLimiter.init(type: :registration)
      assert opts.type == :registration
      assert opts.limit == 5
      assert opts.window_ms == 60_000
    end

    test "initializes with api_auth type" do
      opts = RateLimiter.init(type: :api_auth)
      assert opts.type == :api_auth
      assert opts.limit == 20
      assert opts.window_ms == 60_000
    end

    test "initializes with guest_auth type" do
      opts = RateLimiter.init(type: :guest_auth)
      assert opts.type == :guest_auth
      assert opts.limit == 10
      assert opts.window_ms == 60_000
    end

    test "raises on invalid type" do
      assert_raise ArgumentError, ~r/Invalid rate limit type/, fn ->
        RateLimiter.init(type: :invalid)
      end
    end
  end

  describe "call/2" do
    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimiter.init(type: :auth)

      # Make 5 requests (under the limit of 10)
      for i <- 1..5 do
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
        assert get_resp_header(result_conn, "x-ratelimit-limit") == ["10"]
        assert get_resp_header(result_conn, "x-ratelimit-remaining") == ["#{10 - i}"]
      end
    end

    test "blocks requests over the limit", %{conn: conn} do
      # Use a very low limit for testing
      opts = %{type: :auth, limit: 3, window_ms: 60_000}

      # Make requests up to the limit
      for _ <- 1..3 do
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
      end

      # The 4th request should be blocked
      blocked_conn = RateLimiter.call(conn, opts)
      assert blocked_conn.halted
      assert blocked_conn.status == 429
      assert get_resp_header(blocked_conn, "retry-after") != []
      assert get_resp_header(blocked_conn, "x-ratelimit-remaining") == ["0"]
    end

    test "returns JSON response for API requests", %{conn: conn} do
      opts = %{type: :api_auth, limit: 1, window_ms: 60_000}

      # First request succeeds
      conn1 = RateLimiter.call(conn, opts)
      refute conn1.halted

      # Second request blocked with JSON response
      api_conn =
        conn
        |> put_req_header("accept", "application/json")

      blocked_conn = RateLimiter.call(api_conn, opts)
      assert blocked_conn.halted
      assert blocked_conn.status == 429

      body = Jason.decode!(blocked_conn.resp_body)
      assert body["error"] == "Too many requests"
    end

    test "returns HTML response for browser requests", %{conn: conn} do
      opts = %{type: :auth, limit: 1, window_ms: 60_000}

      # First request succeeds
      conn1 = RateLimiter.call(conn, opts)
      refute conn1.halted

      # Second request blocked with HTML response
      blocked_conn = RateLimiter.call(conn, opts)
      assert blocked_conn.halted
      assert blocked_conn.status == 429
      assert blocked_conn.resp_body =~ "Too Many Requests"
      assert blocked_conn.resp_body =~ "<!DOCTYPE html>"
    end

    test "tracks different IPs separately", %{conn: conn} do
      opts = %{type: :auth, limit: 2, window_ms: 60_000}

      # Requests from IP 1
      conn1 = %{conn | remote_ip: {192, 168, 1, 1}}

      result1 = RateLimiter.call(conn1, opts)
      refute result1.halted

      result2 = RateLimiter.call(conn1, opts)
      refute result2.halted

      # IP 1 is now at limit
      result3 = RateLimiter.call(conn1, opts)
      assert result3.halted

      # But IP 2 can still make requests
      conn2 = %{conn | remote_ip: {192, 168, 1, 2}}

      result4 = RateLimiter.call(conn2, opts)
      refute result4.halted
    end

    test "respects X-Forwarded-For header", %{conn: conn} do
      opts = %{type: :auth, limit: 2, window_ms: 60_000}

      # Requests with X-Forwarded-For
      forwarded_conn =
        conn
        |> put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.1")

      result1 = RateLimiter.call(forwarded_conn, opts)
      refute result1.halted

      result2 = RateLimiter.call(forwarded_conn, opts)
      refute result2.halted

      # Now at limit for 10.0.0.1
      result3 = RateLimiter.call(forwarded_conn, opts)
      assert result3.halted

      # Different forwarded IP should work
      other_forwarded_conn =
        conn
        |> put_req_header("x-forwarded-for", "10.0.0.2")

      result4 = RateLimiter.call(other_forwarded_conn, opts)
      refute result4.halted
    end

    test "different rate limit types have separate buckets", %{conn: conn} do
      auth_opts = %{type: :auth, limit: 2, window_ms: 60_000}
      api_opts = %{type: :api_auth, limit: 2, window_ms: 60_000}

      # Use up auth limit
      RateLimiter.call(conn, auth_opts)
      RateLimiter.call(conn, auth_opts)

      blocked_auth = RateLimiter.call(conn, auth_opts)
      assert blocked_auth.halted

      # API auth should still work (different bucket)
      api_result = RateLimiter.call(conn, api_opts)
      refute api_result.halted
    end
  end

  describe "rate limiting disabled in test" do
    setup do
      # Disable rate limiting
      Application.put_env(:sensocto, :enable_rate_limiting_in_test, false)

      on_exit(fn ->
        Application.put_env(:sensocto, :enable_rate_limiting_in_test, true)
      end)

      :ok
    end

    test "does not rate limit when disabled", %{conn: conn} do
      opts = %{type: :auth, limit: 1, window_ms: 60_000}

      # Even though limit is 1, multiple requests should succeed
      for _ <- 1..10 do
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
      end
    end
  end
end
