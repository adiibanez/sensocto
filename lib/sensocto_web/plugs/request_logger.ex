defmodule SensoctoWeb.Plugs.RequestLogger do
  @moduledoc """
  Request logging plug that sanitizes sensitive data before logging.

  Filters out sensitive parameters, headers, and cookies to prevent
  credential leakage in log files.
  """
  require Logger

  @sensitive_params ~w(password password_confirmation token api_key secret
                       current_password new_password reset_token access_token
                       refresh_token authorization)
  @sensitive_headers ~w(authorization cookie x-api-key x-auth-token)
  @sensitive_cookies ~w(_sensocto_key)

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    log_request_info(conn)
    conn
  end

  defp log_request_info(conn) do
    Logger.debug(fn ->
      """
      Request: #{conn.method} #{conn.request_path}
      Params: #{inspect(sanitize_params(conn.params))}
      """
    end)
  end

  defp sanitize_params(params) when is_map(params) do
    Map.new(params, fn {key, value} ->
      if sensitive_param?(key) do
        {key, "[FILTERED]"}
      else
        {key, sanitize_value(value)}
      end
    end)
  end

  defp sanitize_params(params), do: params

  defp sanitize_value(value) when is_map(value), do: sanitize_params(value)
  defp sanitize_value(value), do: value

  defp sensitive_param?(key) when is_binary(key) do
    String.downcase(key) in @sensitive_params
  end

  defp sensitive_param?(key) when is_atom(key) do
    key_str = key |> Atom.to_string() |> String.downcase()
    key_str in @sensitive_params
  end

  defp sensitive_param?(_), do: false

  # These functions are available for explicit debug logging if needed,
  # but are not called by default to avoid log pollution
  @doc false
  def log_headers(conn) do
    filtered_headers =
      conn.req_headers
      |> Enum.map(fn {key, value} ->
        if String.downcase(key) in @sensitive_headers do
          {key, "[FILTERED]"}
        else
          {key, value}
        end
      end)

    Logger.debug("Headers: #{inspect(filtered_headers)}")
  end

  @doc false
  def log_cookies(conn) do
    filtered_cookies =
      conn.cookies
      |> Enum.map(fn {key, value} ->
        if key in @sensitive_cookies do
          {key, "[FILTERED]"}
        else
          {key, value}
        end
      end)
      |> Map.new()

    Logger.debug("Cookies: #{inspect(filtered_cookies)}")
  end
end
