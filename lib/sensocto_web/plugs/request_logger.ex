defmodule SensoctoWeb.Plugs.RequestLogger do
  # import Plug.Conn
  require Logger

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    log_cookies(conn)
    log_headers(conn)
    log_params(conn)
    conn
  end

  defp log_cookies(conn) do
    Logger.debug("Cookies: #{inspect(conn.cookies)}")
  end

  defp log_headers(conn) do
    Logger.debug("Headers: #{inspect(conn.req_headers)}")
  end

  defp log_params(conn) do
    Logger.debug("Request Parameters: #{inspect(conn.params)}")
  end
end
