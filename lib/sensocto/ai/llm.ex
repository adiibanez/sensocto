defmodule Sensocto.AI.LLM do
  @moduledoc """
  LLM interface for interacting with local Ollama models.

  Provides a simple API for chat completions, streaming responses,
  and structured outputs using the Ollama library.
  """

  require Logger

  @default_model "qwen3-coder:latest"
  @default_base_url "http://localhost:11434/api"

  @doc """
  Initialize an Ollama client with optional configuration.

  ## Options

    * `:base_url` - Ollama API URL (default: "http://localhost:11434/api")
  """
  def client(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    Ollama.init(base_url)
  end

  @doc """
  Send a chat message and get a response.

  ## Options

    * `:model` - Model to use (default: "qwen3-coder:latest")
    * `:system` - System prompt to set context
    * `:stream` - Set to `true` for streaming or a PID to receive messages
    * `:format` - JSON schema for structured outputs
    * `:temperature` - Sampling temperature (0.0-2.0)
  """
  def chat(messages, opts \\ []) when is_list(messages) do
    model = Keyword.get(opts, :model, @default_model)
    system = Keyword.get(opts, :system)
    stream = Keyword.get(opts, :stream, false)
    format = Keyword.get(opts, :format)
    temperature = Keyword.get(opts, :temperature)

    messages =
      if system do
        [%{role: "system", content: system} | normalize_messages(messages)]
      else
        normalize_messages(messages)
      end

    request_opts = [model: model, messages: messages]
    request_opts = if stream, do: Keyword.put(request_opts, :stream, stream), else: request_opts
    request_opts = if format, do: Keyword.put(request_opts, :format, format), else: request_opts

    request_opts =
      if temperature,
        do: Keyword.put(request_opts, :options, %{temperature: temperature}),
        else: request_opts

    Logger.debug("LLM chat request: model=#{model}, messages=#{length(messages)}")

    case Ollama.chat(client(), request_opts) do
      {:ok, %{"message" => %{"content" => content}}} = result ->
        Logger.debug("LLM response received: #{String.slice(content, 0..100)}...")
        result

      {:ok, stream} when is_function(stream, 2) ->
        {:ok, stream}

      {:ok, %Task{}} = result ->
        result

      {:error, reason} = error ->
        Logger.error("LLM chat error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Simple completion without chat history.
  Convenience wrapper around chat/2 for single-turn conversations.
  """
  def complete(prompt, opts \\ []) when is_binary(prompt) do
    chat([%{role: "user", content: prompt}], opts)
  end

  @doc """
  Get a simple text response (extracts content from the response).
  """
  def ask(prompt, opts \\ []) when is_binary(prompt) do
    case complete(prompt, opts) do
      {:ok, %{"message" => %{"content" => content}}} -> {:ok, content}
      error -> error
    end
  end

  @doc """
  Stream a chat response to a LiveView process.
  Returns {:ok, task} where task is the streaming task.
  """
  def stream_chat(messages, pid, opts \\ []) when is_list(messages) and is_pid(pid) do
    opts = Keyword.put(opts, :stream, pid)
    chat(messages, opts)
  end

  @doc """
  Get structured JSON output from the model.

  ## Example

      schema = %{
        type: "object",
        properties: %{
          sentiment: %{type: "string", enum: ["positive", "negative", "neutral"]},
          confidence: %{type: "number"}
        },
        required: ["sentiment", "confidence"]
      }

      {:ok, result} = LLM.structured("Analyze: I love this product!", schema)
  """
  def structured(prompt, schema, opts \\ []) when is_binary(prompt) and is_map(schema) do
    opts = Keyword.put(opts, :format, schema)

    case complete(prompt, opts) do
      {:ok, %{"message" => %{"content" => content}}} ->
        case Jason.decode(content) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, :invalid_json, content}
        end

      error ->
        error
    end
  end

  @doc """
  Check if Ollama is available and the model is loaded.
  """
  def health_check(model \\ @default_model) do
    case Ollama.show_model(client(), name: model) do
      {:ok, %{"modelfile" => _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List available models on the Ollama instance.
  """
  def list_models do
    case Ollama.list_models(client()) do
      {:ok, %{"models" => models}} ->
        {:ok, Enum.map(models, & &1["name"])}

      error ->
        error
    end
  end

  # Private helpers

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{role: to_string(role), content: content}
      %{"role" => _, "content" => _} = msg -> msg
      content when is_binary(content) -> %{role: "user", content: content}
    end)
  end
end
