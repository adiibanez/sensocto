defmodule SensoctoWeb.AIChatLive do
  @moduledoc """
  LiveView for interacting with the local Ollama LLM.
  Supports streaming responses and sensor data context.
  """
  use SensoctoWeb, :live_view

  alias Sensocto.AI.LLM
  alias Sensocto.AI.SensorContext

  @default_system_prompt """
  You are a helpful AI assistant integrated with a sensor monitoring platform called Sensocto.
  You can help users understand sensor data, analyze trends, and answer questions about their sensor network.
  Be concise and helpful. When discussing sensor data, provide clear explanations.
  """

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "AI Chat")
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:streaming, false)
      |> assign(:current_response, "")
      |> assign(:include_sensor_context, true)
      |> assign(:model, "qwen3-coder:latest")
      |> assign(:available_models, [])

    socket =
      if connected?(socket) do
        case LLM.list_models() do
          {:ok, models} -> assign(socket, :available_models, models)
          _ -> socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-4">
      <div class="max-w-4xl mx-auto">
        <header class="mb-6">
          <h1 class="text-2xl font-bold mb-2">AI Chat</h1>
          <p class="text-gray-400 text-sm">Powered by Ollama with {@model}</p>
        </header>

        <div class="mb-4 flex gap-4 items-center">
          <label class="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={@include_sensor_context}
              phx-click="toggle_sensor_context"
              class="rounded bg-gray-700 border-gray-600"
            />
            <span>Include sensor context</span>
          </label>

          <select
            phx-change="change_model"
            name="model"
            class="bg-gray-800 border border-gray-700 rounded px-3 py-1 text-sm"
          >
            <option :for={model <- @available_models} value={model} selected={model == @model}>
              {model}
            </option>
          </select>
        </div>

        <div class="bg-gray-800 rounded-lg p-4 mb-4 h-[60vh] overflow-y-auto" id="chat-messages">
          <div :if={@messages == []} class="text-gray-500 text-center py-8">
            Start a conversation by typing a message below.
          </div>

          <div :for={msg <- @messages} class={["mb-4", message_class(msg.role)]}>
            <div class="font-semibold text-sm mb-1 capitalize">{msg.role}</div>
            <div class="whitespace-pre-wrap">{msg.content}</div>
          </div>

          <div :if={@streaming} class="mb-4 text-blue-400">
            <div class="font-semibold text-sm mb-1">Assistant</div>
            <div class="whitespace-pre-wrap">
              {@current_response}<span class="animate-pulse">▊</span>
            </div>
          </div>
        </div>

        <form phx-submit="send" class="flex gap-2">
          <input
            type="text"
            name="message"
            value={@input}
            phx-change="update_input"
            placeholder="Type your message..."
            disabled={@streaming}
            class="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
            autofocus
          />
          <button
            type="submit"
            disabled={@streaming || @input == ""}
            class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:cursor-not-allowed px-6 py-2 rounded-lg font-medium transition-colors"
          >
            {if @streaming, do: "...", else: "Send"}
          </button>
        </form>

        <div class="mt-4 text-xs text-gray-500">
          <p>Tips: Ask about sensor data, request analysis, or ask general questions.</p>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  def handle_event("toggle_sensor_context", _params, socket) do
    {:noreply, assign(socket, :include_sensor_context, !socket.assigns.include_sensor_context)}
  end

  def handle_event("change_model", %{"model" => model}, socket) do
    {:noreply, assign(socket, :model, model)}
  end

  def handle_event("send", %{"message" => message}, socket) when message != "" do
    user_message = %{role: "user", content: message}
    messages = socket.assigns.messages ++ [user_message]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:input, "")
      |> assign(:streaming, true)
      |> assign(:current_response, "")

    send(self(), {:generate_response, messages})

    {:noreply, socket}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:generate_response, messages}, socket) do
    system_prompt = build_system_prompt(socket.assigns.include_sensor_context)

    chat_messages =
      Enum.map(messages, fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    case LLM.stream_chat(chat_messages, self(),
           system: system_prompt,
           model: socket.assigns.model
         ) do
      {:ok, _task} ->
        {:noreply, socket}

      {:error, reason} ->
        error_message = %{role: "assistant", content: "Error: #{inspect(reason)}"}

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [error_message])
          |> assign(:streaming, false)

        {:noreply, socket}
    end
  end

  def handle_info({_pid, {:data, %{"done" => false, "message" => %{"content" => chunk}}}}, socket) do
    current = socket.assigns.current_response <> chunk
    {:noreply, assign(socket, :current_response, current)}
  end

  def handle_info({_pid, {:data, %{"done" => true}}}, socket) do
    assistant_message = %{role: "assistant", content: socket.assigns.current_response}

    socket =
      socket
      |> assign(:messages, socket.assigns.messages ++ [assistant_message])
      |> assign(:streaming, false)
      |> assign(:current_response, "")

    {:noreply, socket}
  end

  def handle_info({_pid, {:error, reason}}, socket) do
    error_message = %{role: "assistant", content: "Streaming error: #{inspect(reason)}"}

    socket =
      socket
      |> assign(:messages, socket.assigns.messages ++ [error_message])
      |> assign(:streaming, false)
      |> assign(:current_response, "")

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp build_system_prompt(include_sensor_context) do
    if include_sensor_context do
      SensorContext.system_prompt_with_context(@default_system_prompt)
    else
      @default_system_prompt
    end
  end

  defp message_class("user"), do: "text-green-400"
  defp message_class("assistant"), do: "text-blue-400"
  defp message_class(_), do: "text-gray-400"
end
