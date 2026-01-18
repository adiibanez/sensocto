defmodule Sensocto.RoomMarkdown.TigrisStorage do
  @moduledoc """
  S3-compatible storage adapter for room documents using Fly.io Tigris.

  Handles backup and restore of room markdown files to/from Tigris object storage.

  ## Configuration

  Configure in `config/runtime.exs`:

  ```elixir
  config :sensocto, :tigris,
    bucket: System.get_env("TIGRIS_BUCKET"),
    region: System.get_env("TIGRIS_REGION", "auto"),
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    endpoint: System.get_env("TIGRIS_ENDPOINT", "https://fly.storage.tigris.dev")
  ```

  ## Storage Structure

  ```
  rooms/
    {room_id}/
      room.md           # Main room document
      versions/
        {timestamp}.md  # Version history (optional)
  ```
  """

  alias Sensocto.RoomMarkdown.{Parser, RoomDocument, Serializer}

  require Logger

  @default_endpoint "https://fly.storage.tigris.dev"
  @default_region "auto"

  @doc """
  Uploads a room document to Tigris.

  Returns `{:ok, etag}` on success.
  """
  @spec upload(RoomDocument.t()) :: {:ok, String.t()} | {:error, term()}
  def upload(%RoomDocument{} = doc) do
    content = Serializer.serialize(doc)
    key = Serializer.storage_key(doc)

    case put_object(key, content, content_type: "text/markdown") do
      {:ok, %{status_code: status}} when status in 200..299 ->
        Logger.debug("[TigrisStorage] Uploaded room #{doc.id}")
        {:ok, doc.id}

      {:ok, response} ->
        Logger.error("[TigrisStorage] Upload failed: #{inspect(response)}")
        {:error, {:upload_failed, response}}

      {:error, reason} ->
        Logger.error("[TigrisStorage] Upload error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads a room document from Tigris.

  Returns `{:ok, document}` on success.
  """
  @spec download(String.t()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def download(room_id) when is_binary(room_id) do
    key = Serializer.storage_key(room_id)

    case get_object(key) do
      {:ok, %{status_code: 200, body: body}} ->
        Parser.parse(body)

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        Logger.error("[TigrisStorage] Download failed: #{inspect(response)}")
        {:error, {:download_failed, response}}

      {:error, reason} ->
        Logger.error("[TigrisStorage] Download error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes a room document from Tigris.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(room_id) when is_binary(room_id) do
    key = Serializer.storage_key(room_id)

    case delete_object(key) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        Logger.debug("[TigrisStorage] Deleted room #{room_id}")
        :ok

      {:ok, %{status_code: 404}} ->
        # Already deleted
        :ok

      {:ok, response} ->
        Logger.error("[TigrisStorage] Delete failed: #{inspect(response)}")
        {:error, {:delete_failed, response}}

      {:error, reason} ->
        Logger.error("[TigrisStorage] Delete error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if a room document exists in Tigris.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(room_id) when is_binary(room_id) do
    key = Serializer.storage_key(room_id)

    case head_object(key) do
      {:ok, %{status_code: 200}} -> true
      _ -> false
    end
  end

  @doc """
  Lists all room documents in Tigris.

  Returns a list of room IDs.
  """
  @spec list_rooms() :: {:ok, [String.t()]} | {:error, term()}
  def list_rooms do
    case list_objects("rooms/") do
      {:ok, %{body: %{contents: contents}}} ->
        room_ids =
          contents
          |> Enum.map(& &1.key)
          |> Enum.filter(&String.ends_with?(&1, "/room.md"))
          |> Enum.map(fn key ->
            key
            |> String.replace_prefix("rooms/", "")
            |> String.replace_suffix("/room.md", "")
          end)

        {:ok, room_ids}

      {:ok, %{body: %{contents: nil}}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Saves a version backup of a room document.

  Used for version history before major changes.
  """
  @spec save_version(RoomDocument.t()) :: {:ok, String.t()} | {:error, term()}
  def save_version(%RoomDocument{} = doc) do
    content = Serializer.serialize(doc)
    timestamp = DateTime.to_iso8601(DateTime.utc_now()) |> String.replace(":", "-")
    key = "rooms/#{doc.id}/versions/#{timestamp}.md"

    case put_object(key, content, content_type: "text/markdown") do
      {:ok, %{status_code: status}} when status in 200..299 ->
        {:ok, timestamp}

      {:ok, response} ->
        {:error, {:upload_failed, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists version history for a room.
  """
  @spec list_versions(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_versions(room_id) when is_binary(room_id) do
    prefix = "rooms/#{room_id}/versions/"

    case list_objects(prefix) do
      {:ok, %{body: %{contents: contents}}} when is_list(contents) ->
        versions =
          contents
          |> Enum.map(& &1.key)
          |> Enum.map(&String.replace_prefix(&1, prefix, ""))
          |> Enum.map(&String.replace_suffix(&1, ".md", ""))
          |> Enum.sort(:desc)

        {:ok, versions}

      {:ok, %{body: %{contents: nil}}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a specific version of a room document.
  """
  @spec download_version(String.t(), String.t()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def download_version(room_id, version) when is_binary(room_id) and is_binary(version) do
    key = "rooms/#{room_id}/versions/#{version}.md"

    case get_object(key) do
      {:ok, %{status_code: 200, body: body}} ->
        Parser.parse(body)

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if Tigris storage is configured and available.
  """
  @spec available?() :: boolean()
  def available? do
    config = get_config()
    not is_nil(config[:bucket]) and not is_nil(config[:access_key_id])
  end

  # Private S3 operations using Req (built-in HTTP client)
  # These use AWS Signature V4 for authentication

  defp put_object(key, content, opts) do
    config = get_config()

    if config[:bucket] do
      request(:put, key, body: content, headers: build_headers(opts))
    else
      {:error, :not_configured}
    end
  end

  defp get_object(key) do
    config = get_config()

    if config[:bucket] do
      request(:get, key)
    else
      {:error, :not_configured}
    end
  end

  defp head_object(key) do
    config = get_config()

    if config[:bucket] do
      request(:head, key)
    else
      {:error, :not_configured}
    end
  end

  defp delete_object(key) do
    config = get_config()

    if config[:bucket] do
      request(:delete, key)
    else
      {:error, :not_configured}
    end
  end

  defp list_objects(prefix) do
    config = get_config()

    if config[:bucket] do
      # List objects with prefix
      params = [{"prefix", prefix}, {"list-type", "2"}]
      request(:get, "", query: params, parse_xml: true)
    else
      {:error, :not_configured}
    end
  end

  defp request(method, key, opts \\ []) do
    config = get_config()
    bucket = config[:bucket]
    endpoint = config[:endpoint] || @default_endpoint
    region = config[:region] || @default_region

    url = "#{endpoint}/#{bucket}/#{key}"

    headers =
      Keyword.get(opts, :headers, [])
      |> Keyword.put(:"x-amz-content-sha256", "UNSIGNED-PAYLOAD")
      |> Keyword.put(:host, URI.parse(endpoint).host)

    # Build AWS Signature V4 headers
    signed_headers = sign_request(method, url, headers, config, region)

    req_opts =
      [
        method: method,
        url: url,
        headers: signed_headers
      ]
      |> maybe_add_body(opts)
      |> maybe_add_query(opts)

    case Req.request(req_opts) do
      {:ok, response} ->
        body =
          if Keyword.get(opts, :parse_xml, false) and is_binary(response.body) do
            parse_list_response(response.body)
          else
            response.body
          end

        {:ok, %{status_code: response.status, body: body, headers: response.headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_body(req_opts, opts) do
    case Keyword.get(opts, :body) do
      nil -> req_opts
      body -> Keyword.put(req_opts, :body, body)
    end
  end

  defp maybe_add_query(req_opts, opts) do
    case Keyword.get(opts, :query) do
      nil -> req_opts
      query -> Keyword.put(req_opts, :params, query)
    end
  end

  defp build_headers(opts) do
    headers = []

    headers =
      case Keyword.get(opts, :content_type) do
        nil -> headers
        ct -> Keyword.put(headers, :"content-type", ct)
      end

    headers
  end

  defp sign_request(method, url, headers, config, region) do
    # Simplified AWS Signature V4 implementation
    access_key = config[:access_key_id]
    secret_key = config[:secret_access_key]

    if access_key && secret_key do
      now = DateTime.utc_now()
      date_stamp = Calendar.strftime(now, "%Y%m%d")
      amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

      headers =
        headers
        |> Keyword.put(:"x-amz-date", amz_date)

      uri = URI.parse(url)
      path = uri.path || "/"

      # Create canonical request
      method_str = method |> Atom.to_string() |> String.upcase()

      signed_header_names =
        headers
        |> Enum.map(fn {k, _v} -> k |> Atom.to_string() |> String.downcase() end)
        |> Enum.sort()
        |> Enum.join(";")

      canonical_headers =
        headers
        |> Enum.map(fn {k, v} -> "#{k |> Atom.to_string() |> String.downcase()}:#{v}" end)
        |> Enum.sort()
        |> Enum.join("\n")

      canonical_request = """
      #{method_str}
      #{path}

      #{canonical_headers}

      #{signed_header_names}
      UNSIGNED-PAYLOAD
      """

      canonical_hash = :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)

      # Create string to sign
      credential_scope = "#{date_stamp}/#{region}/s3/aws4_request"

      string_to_sign = """
      AWS4-HMAC-SHA256
      #{amz_date}
      #{credential_scope}
      #{canonical_hash}
      """

      # Calculate signature
      signing_key =
        ("AWS4" <> secret_key)
        |> hmac_sha256(date_stamp)
        |> hmac_sha256(region)
        |> hmac_sha256("s3")
        |> hmac_sha256("aws4_request")

      signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

      # Build authorization header
      auth_header =
        "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_scope}, SignedHeaders=#{signed_header_names}, Signature=#{signature}"

      Keyword.put(headers, :authorization, auth_header)
    else
      headers
    end
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp parse_list_response(xml) do
    # Simple XML parsing for S3 ListObjectsV2 response
    contents =
      Regex.scan(~r/<Key>([^<]+)<\/Key>/, xml)
      |> Enum.map(fn [_, key] -> %{key: key} end)

    %{contents: if(contents == [], do: nil, else: contents)}
  end

  defp get_config do
    Application.get_env(:sensocto, :tigris, [])
  end
end
