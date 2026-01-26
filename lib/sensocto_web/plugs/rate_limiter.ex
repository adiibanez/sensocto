defmodule SensoctoWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug for authentication endpoints.

  Protects against brute-force attacks and credential stuffing by limiting
  the number of requests from a single IP address within a time window.

  ## Configuration

  Rate limits are configured in `config/config.exs`:

      config :sensocto, SensoctoWeb.Plugs.RateLimiter,
        # Authentication endpoints (login, password reset, magic link)
        auth_limit: 10,
        auth_window_ms: 60_000,
        # Registration endpoints
        registration_limit: 5,
        registration_window_ms: 60_000,
        # API authentication endpoints
        api_auth_limit: 20,
        api_auth_window_ms: 60_000,
        # Guest authentication
        guest_auth_limit: 10,
        guest_auth_window_ms: 60_000

  ## Usage

  Add to your router pipeline:

      plug SensoctoWeb.Plugs.RateLimiter, type: :auth

  Or use the helper function in router scope:

      pipe_through [:browser, :rate_limit_auth]

  ## Rate Limit Types

  - `:auth` - Sign in, password with email/password (10 requests/minute)
  - `:registration` - New user registration (5 requests/minute)
  - `:api_auth` - API token verification (20 requests/minute)
  - `:guest_auth` - Guest session creation (10 requests/minute)

  ## Security Notes

  - Uses IP-based rate limiting with X-Forwarded-For header support for proxies
  - Returns 429 Too Many Requests with Retry-After header
  - Logs rate limit violations for security monitoring
  - Consider using Paraxial.io for more advanced bot protection in production
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  # Default rate limits
  @default_auth_limit 10
  @default_auth_window_ms 60_000
  @default_registration_limit 5
  @default_registration_window_ms 60_000
  @default_api_auth_limit 20
  @default_api_auth_window_ms 60_000
  @default_guest_auth_limit 10
  @default_guest_auth_window_ms 60_000

  @type rate_limit_type :: :auth | :registration | :api_auth | :guest_auth

  @impl true
  def init(opts) do
    type = Keyword.get(opts, :type, :auth)
    config = Application.get_env(:sensocto, __MODULE__, [])

    case type do
      :auth ->
        %{
          type: :auth,
          limit: Keyword.get(config, :auth_limit, @default_auth_limit),
          window_ms: Keyword.get(config, :auth_window_ms, @default_auth_window_ms)
        }

      :registration ->
        %{
          type: :registration,
          limit: Keyword.get(config, :registration_limit, @default_registration_limit),
          window_ms: Keyword.get(config, :registration_window_ms, @default_registration_window_ms)
        }

      :api_auth ->
        %{
          type: :api_auth,
          limit: Keyword.get(config, :api_auth_limit, @default_api_auth_limit),
          window_ms: Keyword.get(config, :api_auth_window_ms, @default_api_auth_window_ms)
        }

      :guest_auth ->
        %{
          type: :guest_auth,
          limit: Keyword.get(config, :guest_auth_limit, @default_guest_auth_limit),
          window_ms: Keyword.get(config, :guest_auth_window_ms, @default_guest_auth_window_ms)
        }

      _ ->
        raise ArgumentError, "Invalid rate limit type: #{inspect(type)}"
    end
  end

  @impl true
  def call(conn, %{type: type, limit: limit, window_ms: window_ms}) do
    cond do
      # Skip rate limiting in test environment
      Application.get_env(:sensocto, :env) == :test and
          not Application.get_env(:sensocto, :enable_rate_limiting_in_test, false) ->
        conn

      # Only rate limit POST requests (actual auth attempts), not page views
      conn.method != "POST" ->
        conn

      true ->
        client_ip = get_client_ip(conn)
        bucket_key = "rate_limit:#{type}:#{client_ip}"

        case check_rate_limit(bucket_key, limit, window_ms) do
          {:allow, count} ->
            conn
            |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(0, limit - count)))
            |> put_resp_header("x-ratelimit-reset", Integer.to_string(reset_timestamp(window_ms)))

          {:deny, retry_after_ms} ->
            Logger.warning(
              "Rate limit exceeded for #{type} from IP #{client_ip}",
              ip: client_ip,
              type: type,
              limit: limit,
              window_ms: window_ms
            )

            retry_after_seconds = div(retry_after_ms, 1000) + 1

            conn
            |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
            |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
            |> put_resp_header("x-ratelimit-remaining", "0")
            |> put_resp_header("x-ratelimit-reset", Integer.to_string(reset_timestamp(window_ms)))
            |> send_rate_limit_response(conn)
            |> halt()
        end
    end
  end

  # Get client IP, supporting X-Forwarded-For for proxies
  defp get_client_ip(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    case forwarded_for do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      header ->
        # X-Forwarded-For can contain multiple IPs: "client, proxy1, proxy2"
        # The first one is the original client
        header
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  # Check rate limit using ETS-based sliding window counter
  defp check_rate_limit(bucket_key, limit, window_ms) do
    now = System.system_time(:millisecond)
    window_start = now - window_ms

    # Use ETS for rate limiting storage
    table = ensure_ets_table()

    # Clean up old entries and count current window
    count =
      case :ets.lookup(table, bucket_key) do
        [{^bucket_key, timestamps}] ->
          # Filter to only timestamps within the window
          valid_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)
          valid_count = length(valid_timestamps)

          if valid_count < limit do
            # Add new timestamp and update
            :ets.insert(table, {bucket_key, [now | valid_timestamps]})
            valid_count + 1
          else
            # Over limit - calculate retry after
            oldest_in_window = Enum.min(valid_timestamps)
            retry_after = oldest_in_window + window_ms - now
            throw({:rate_limited, retry_after})
          end

        [] ->
          # First request - create new entry
          :ets.insert(table, {bucket_key, [now]})
          1
      end

    {:allow, count}
  catch
    {:rate_limited, retry_after} ->
      {:deny, max(0, retry_after)}
  end

  # Ensure ETS table exists
  defp ensure_ets_table do
    table_name = :sensocto_rate_limiter

    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:named_table, :public, :set, read_concurrency: true])

      _ref ->
        table_name
    end
  end

  # Calculate reset timestamp
  defp reset_timestamp(window_ms) do
    now = System.system_time(:second)
    window_seconds = div(window_ms, 1000)
    now + window_seconds
  end

  # Send appropriate response based on request type
  defp send_rate_limit_response(conn, original_conn) do
    if is_api_request?(original_conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        429,
        Jason.encode!(%{
          error: "Too many requests",
          message: "Rate limit exceeded. Please try again later."
        })
      )
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(429, rate_limit_html())
    end
  end

  defp is_api_request?(conn) do
    accept = get_req_header(conn, "accept") |> List.first() || ""
    content_type = get_req_header(conn, "content-type") |> List.first() || ""

    String.contains?(accept, "application/json") or
      String.contains?(content_type, "application/json") or
      String.starts_with?(conn.request_path, "/api")
  end

  defp rate_limit_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Too Many Requests</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          margin: 0;
          background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
          color: #e4e4e7;
        }
        .container {
          text-align: center;
          padding: 2rem;
          max-width: 500px;
        }
        h1 {
          font-size: 4rem;
          margin: 0;
          color: #f59e0b;
        }
        h2 {
          font-size: 1.5rem;
          margin: 1rem 0;
          color: #f4f4f5;
        }
        p {
          color: #a1a1aa;
          line-height: 1.6;
        }
        .retry-info {
          margin-top: 2rem;
          padding: 1rem;
          background: rgba(245, 158, 11, 0.1);
          border-radius: 0.5rem;
          border: 1px solid rgba(245, 158, 11, 0.2);
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>429</h1>
        <h2>Too Many Requests</h2>
        <p>
          You've made too many requests in a short period of time.
          Please wait a moment before trying again.
        </p>
        <div class="retry-info">
          <p>This limit helps protect our service from abuse.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end
end
