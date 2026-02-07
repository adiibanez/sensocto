defmodule Sensocto.Calls.CloudflareTurn do
  @moduledoc """
  Generates short-lived TURN credentials via Cloudflare's Realtime TURN API.

  Cloudflare TURN requires ephemeral credentials generated server-side.
  Credentials are cached in-process to avoid hitting the API on every call join.

  Configuration (via environment variables):
    - CLOUDFLARE_TURN_KEY_ID: The TURN key ID from Cloudflare dashboard
    - CLOUDFLARE_TURN_API_TOKEN: The API token for the TURN key
  """

  require Logger

  @api_base "https://rtc.live.cloudflare.com/v1/turn/keys"
  # Credentials TTL: 24 hours
  @credential_ttl 86400
  # Refresh credentials when less than 1 hour remains
  @refresh_threshold 3600

  @doc """
  Returns Cloudflare ICE servers (STUN + TURN) if configured, otherwise nil.
  Caches credentials in persistent_term to avoid API calls on every request.
  """
  def get_ice_servers do
    case config() do
      {:ok, key_id, api_token} ->
        case get_cached_credentials() do
          {:ok, ice_servers} ->
            ice_servers

          :expired ->
            case generate_credentials(key_id, api_token) do
              {:ok, ice_servers} ->
                cache_credentials(ice_servers)
                ice_servers

              {:error, reason} ->
                Logger.error("CloudflareTurn: Failed to generate credentials: #{inspect(reason)}")
                nil
            end
        end

      :not_configured ->
        nil
    end
  end

  defp config do
    key_id = Application.get_env(:sensocto, :cloudflare_turn_key_id)
    api_token = Application.get_env(:sensocto, :cloudflare_turn_api_token)

    if key_id && api_token do
      {:ok, key_id, api_token}
    else
      :not_configured
    end
  end

  defp generate_credentials(key_id, api_token) do
    url = "#{@api_base}/#{key_id}/credentials/generate-ice-servers"

    case Req.post(url,
           json: %{ttl: @credential_ttl},
           headers: [{"authorization", "Bearer #{api_token}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 201, body: %{"iceServers" => ice_servers}}} ->
        formatted = format_ice_servers(ice_servers)
        Logger.info("CloudflareTurn: Generated credentials (TTL: #{@credential_ttl}s)")
        {:ok, formatted}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_ice_servers(ice_servers) when is_list(ice_servers) do
    Enum.flat_map(ice_servers, fn server ->
      urls = server["urls"] || []

      base = %{urls: urls}

      base =
        if server["username"], do: Map.put(base, :username, server["username"]), else: base

      base =
        if server["credential"], do: Map.put(base, :credential, server["credential"]), else: base

      [base]
    end)
  end

  defp format_ice_servers(_), do: []

  defp get_cached_credentials do
    case :persistent_term.get(:cloudflare_turn_cache, nil) do
      nil ->
        :expired

      {ice_servers, expires_at} ->
        remaining = expires_at - System.system_time(:second)

        if remaining > @refresh_threshold do
          {:ok, ice_servers}
        else
          :expired
        end
    end
  end

  defp cache_credentials(ice_servers) do
    expires_at = System.system_time(:second) + @credential_ttl
    :persistent_term.put(:cloudflare_turn_cache, {ice_servers, expires_at})
  end
end
