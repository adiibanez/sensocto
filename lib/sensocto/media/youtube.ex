defmodule Sensocto.Media.YouTube do
  @moduledoc """
  YouTube URL parsing and metadata fetching utilities.
  Uses oEmbed API for metadata (no API key required).
  """

  require Logger

  @youtube_url_patterns [
    # Standard watch URL: https://www.youtube.com/watch?v=VIDEO_ID
    ~r/(?:youtube\.com\/watch\?.*v=)([a-zA-Z0-9_-]{11})/,
    # Short URL: https://youtu.be/VIDEO_ID
    ~r/(?:youtu\.be\/)([a-zA-Z0-9_-]{11})/,
    # Embed URL: https://www.youtube.com/embed/VIDEO_ID
    ~r/(?:youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
    # Shorts URL: https://www.youtube.com/shorts/VIDEO_ID
    ~r/(?:youtube\.com\/shorts\/)([a-zA-Z0-9_-]{11})/,
    # Music URL: https://music.youtube.com/watch?v=VIDEO_ID
    ~r/(?:music\.youtube\.com\/watch\?.*v=)([a-zA-Z0-9_-]{11})/
  ]

  @oembed_url "https://www.youtube.com/oembed"

  @doc """
  Extracts the YouTube video ID from various URL formats.
  Returns {:ok, video_id} or {:error, reason}.
  """
  def extract_video_id(url) when is_binary(url) do
    url = String.trim(url)

    result =
      @youtube_url_patterns
      |> Enum.find_value(fn pattern ->
        case Regex.run(pattern, url) do
          [_, video_id] -> video_id
          _ -> nil
        end
      end)

    case result do
      nil -> {:error, :invalid_youtube_url}
      video_id -> {:ok, video_id}
    end
  end

  def extract_video_id(_), do: {:error, :invalid_youtube_url}

  @doc """
  Validates if a string is a valid YouTube video ID.
  """
  def valid_video_id?(video_id) when is_binary(video_id) do
    String.length(video_id) == 11 and Regex.match?(~r/^[a-zA-Z0-9_-]+$/, video_id)
  end

  def valid_video_id?(_), do: false

  @doc """
  Fetches video metadata from YouTube's oEmbed API.
  Returns {:ok, metadata} or {:error, reason}.

  Metadata includes:
  - title: Video title
  - author_name: Channel name
  - thumbnail_url: Thumbnail image URL
  """
  def fetch_metadata(video_id) when is_binary(video_id) do
    video_url = "https://www.youtube.com/watch?v=#{video_id}"
    oembed_request_url = "#{@oembed_url}?url=#{URI.encode_www_form(video_url)}&format=json"

    case http_get(oembed_request_url) do
      {:ok, %{status_code: 200, body: body}} ->
        # Body may already be decoded by Req, or may be a JSON string from :httpc
        case decode_body(body) do
          {:ok, data} ->
            {:ok,
             %{
               title: data["title"],
               author_name: data["author_name"],
               thumbnail_url: build_thumbnail_url(video_id),
               # oEmbed doesn't provide duration, we'll get it from the player
               duration_seconds: nil
             }}

          {:error, _} ->
            {:error, :invalid_response}
        end

      {:ok, %{status_code: 401}} ->
        {:error, :video_not_found}

      {:ok, %{status_code: 403}} ->
        {:error, :video_not_embeddable}

      {:ok, %{status_code: 404}} ->
        {:error, :video_not_found}

      {:ok, %{status_code: status}} ->
        Logger.warning("YouTube oEmbed returned status #{status} for video #{video_id}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Failed to fetch YouTube metadata: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  def fetch_metadata(_), do: {:error, :invalid_video_id}

  @doc """
  Builds the standard thumbnail URL for a YouTube video.
  Uses maxresdefault with fallback to hqdefault.
  """
  def build_thumbnail_url(video_id) do
    "https://img.youtube.com/vi/#{video_id}/hqdefault.jpg"
  end

  @doc """
  Builds the embed URL for a YouTube video.
  """
  def build_embed_url(video_id, opts \\ []) do
    params =
      [
        enablejsapi: 1,
        origin: Keyword.get(opts, :origin, ""),
        autoplay: if(Keyword.get(opts, :autoplay, false), do: 1, else: 0),
        controls: if(Keyword.get(opts, :controls, true), do: 1, else: 0),
        rel: 0,
        modestbranding: 1
      ]
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    "https://www.youtube.com/embed/#{video_id}?#{params}"
  end

  @doc """
  Normalizes a YouTube URL to the standard watch format.
  """
  def normalize_url(url) do
    case extract_video_id(url) do
      {:ok, video_id} -> {:ok, "https://www.youtube.com/watch?v=#{video_id}"}
      error -> error
    end
  end

  # Decode body - handles both already-decoded maps (from Req) and JSON strings (from :httpc)
  defp decode_body(body) when is_map(body), do: {:ok, body}
  defp decode_body(body) when is_binary(body), do: Jason.decode(body)
  defp decode_body(_), do: {:error, :invalid_body}

  # HTTP client wrapper - uses Req if available, falls back to :httpc
  defp http_get(url) do
    if Code.ensure_loaded?(Req) do
      case Req.get(url) do
        {:ok, %Req.Response{status: status, body: body}} ->
          {:ok, %{status_code: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Fallback to :httpc
      case :httpc.request(:get, {String.to_charlist(url), []}, [], body_format: :binary) do
        {:ok, {{_, status, _}, _headers, body}} ->
          {:ok, %{status_code: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
