defmodule SensoctoWeb.Components.ChatComponent do
  @moduledoc """
  Reusable chat component for rooms and lobbies.

  Supports:
  - User-to-user messaging
  - AI agent chat (optional)
  - Real-time updates via PubSub
  - Multiple display modes: floating, sidebar, inline

  ## Modes

  - `:floating` - Fixed position floating panel (default, backward compatible)
  - `:sidebar` - Fills parent container, always visible, for desktop sidebar
  - `:inline` - Fills parent, optimized for mobile tab content
  """
  use SensoctoWeb, :live_component

  alias Sensocto.Chat.ChatStore

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:input, "")
     |> assign(:expanded, false)
     |> assign(:ai_enabled, true)
     |> assign(:ai_streaming, false)
     |> assign(:ai_response, "")
     |> assign(:unread_count, 0)
     |> assign(:mode, :floating)}
  end

  @impl true
  def update(%{ai_chunk: chunk}, socket) do
    current = socket.assigns.ai_response <> chunk
    {:ok, assign(socket, :ai_response, current)}
  end

  def update(%{ai_done: true}, socket) do
    room_id = socket.assigns.room_id
    response = socket.assigns.ai_response

    if response != "" do
      ai_message = %{
        role: "assistant",
        content: response,
        user_name: "AI Assistant"
      }

      ChatStore.add_message(room_id, ai_message)
    end

    {:ok,
     socket
     |> assign(:ai_streaming, false)
     |> assign(:ai_response, "")}
  end

  def update(%{ai_error: error}, socket) do
    room_id = socket.assigns.room_id

    error_message = %{
      role: "assistant",
      content: "Sorry, I encountered an error: #{error}",
      user_name: "AI Assistant"
    }

    ChatStore.add_message(room_id, error_message)

    {:ok,
     socket
     |> assign(:ai_streaming, false)
     |> assign(:ai_response, "")}
  end

  def update(%{new_message: message}, socket) do
    messages = socket.assigns.messages ++ [message]

    socket =
      socket
      |> assign(:messages, messages)
      |> maybe_increment_unread()

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Preserve the component ID from the parent template
    component_id = assigns[:id] || socket.assigns[:id]
    room_id = assigns[:room_id] || socket.assigns[:room_id] || "global"
    current_user = assigns[:current_user] || socket.assigns[:current_user]
    mode = assigns[:mode] || socket.assigns[:mode] || :floating

    socket =
      socket
      |> assign(:id, component_id)
      |> assign(:room_id, room_id)
      |> assign(:current_user, current_user)
      |> assign(:user_name, get_user_name(current_user))
      |> assign(:mode, mode)

    # In sidebar/inline modes, always show expanded
    socket =
      if mode in [:sidebar, :inline] do
        assign(socket, :expanded, true)
      else
        socket
      end

    socket =
      if connected?(socket) && !socket.assigns[:subscribed] do
        ChatStore.subscribe(room_id)
        messages = ChatStore.get_messages(room_id)

        # Register this component with the parent for message forwarding
        send(self(), {:register_chat_component, component_id})

        socket
        |> assign(:messages, messages)
        |> assign(:subscribed, true)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(%{mode: :floating} = assigns) do
    ~H"""
    <div class="fixed bottom-[140px] md:bottom-28 right-4 z-[55]" id={"chat-#{@room_id}"}>
      <div :if={!@expanded} class="relative">
        <button
          phx-click="toggle_chat"
          phx-target={@myself}
          class="bg-blue-600 hover:bg-blue-700 text-white rounded-full p-3 shadow-lg transition-all"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
            />
          </svg>
        </button>
        <span
          :if={@unread_count > 0}
          class="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full h-5 w-5 flex items-center justify-center"
        >
          {@unread_count}
        </span>
      </div>

      <div
        :if={@expanded}
        class="bg-gray-800 rounded-lg shadow-xl w-80 sm:w-96 flex flex-col max-h-[70vh]"
      >
        <.chat_header myself={@myself} room_id={@room_id} ai_enabled={@ai_enabled} show_close={true} />
        <.chat_messages
          messages={@messages}
          room_id={@room_id}
          current_user={@current_user}
          ai_streaming={@ai_streaming}
          ai_response={@ai_response}
          mode={@mode}
        />
        <.chat_input
          myself={@myself}
          input={@input}
          ai_enabled={@ai_enabled}
          ai_streaming={@ai_streaming}
        />
      </div>
    </div>
    """
  end

  def render(%{mode: :sidebar} = assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-gray-800" id={"chat-#{@room_id}"}>
      <.chat_header myself={@myself} room_id={@room_id} ai_enabled={@ai_enabled} show_close={false} />
      <.chat_messages
        messages={@messages}
        room_id={@room_id}
        current_user={@current_user}
        ai_streaming={@ai_streaming}
        ai_response={@ai_response}
        mode={@mode}
      />
      <.chat_input
        myself={@myself}
        input={@input}
        ai_enabled={@ai_enabled}
        ai_streaming={@ai_streaming}
      />
    </div>
    """
  end

  def render(%{mode: :inline} = assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-gray-900" id={"chat-#{@room_id}"}>
      <.chat_header myself={@myself} room_id={@room_id} ai_enabled={@ai_enabled} show_close={false} />
      <.chat_messages
        messages={@messages}
        room_id={@room_id}
        current_user={@current_user}
        ai_streaming={@ai_streaming}
        ai_response={@ai_response}
        mode={@mode}
      />
      <.chat_input
        myself={@myself}
        input={@input}
        ai_enabled={@ai_enabled}
        ai_streaming={@ai_streaming}
      />
    </div>
    """
  end

  # Shared chat header component
  attr :myself, :any, required: true
  attr :room_id, :string, required: true
  attr :ai_enabled, :boolean, required: true
  attr :show_close, :boolean, default: true

  defp chat_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-3 border-b border-gray-700">
      <div class="flex items-center gap-2">
        <h3 class="font-semibold text-white">Chat</h3>
        <span class="text-xs text-gray-400">{@room_id}</span>
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="toggle_ai"
          phx-target={@myself}
          class={"px-2 py-1 text-xs rounded transition-colors #{if @ai_enabled, do: "bg-green-600 text-white", else: "bg-gray-600 text-gray-300"}"}
          title={
            if @ai_enabled,
              do: "AI enabled - click to disable",
              else: "AI disabled - click to enable"
          }
        >
          AI
        </button>
        <button
          :if={@show_close}
          phx-click="toggle_chat"
          phx-target={@myself}
          class="text-gray-400 hover:text-white"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Shared chat messages component
  attr :messages, :list, required: true
  attr :room_id, :string, required: true
  attr :current_user, :any, required: true
  attr :ai_streaming, :boolean, required: true
  attr :ai_response, :string, required: true
  attr :mode, :atom, required: true

  defp chat_messages(assigns) do
    ~H"""
    <div
      class={[
        "flex-1 overflow-y-auto p-3 space-y-2",
        if(@mode == :floating, do: "min-h-[200px] max-h-[400px]", else: "min-h-0")
      ]}
      id={"chat-messages-#{@room_id}"}
      phx-hook="ChatScroll"
    >
      <div :if={@messages == []} class="text-gray-500 text-sm text-center py-4">
        No messages yet. Start the conversation!
      </div>

      <div :for={msg <- @messages} class={message_container_class(msg, @current_user)}>
        <div class={message_bubble_class(msg, @current_user)}>
          <div class="text-xs opacity-70 mb-1">
            {message_sender_name(msg)}
            <span :if={msg.role == "assistant"} class="ml-1 text-green-400">AI</span>
          </div>
          <div class="whitespace-pre-wrap break-words">{msg.content}</div>
        </div>
      </div>

      <div :if={@ai_streaming} class="flex justify-start">
        <div class="bg-green-900/50 text-green-100 rounded-lg px-3 py-2 max-w-[85%]">
          <div class="text-xs opacity-70 mb-1">AI Assistant</div>
          <div class="whitespace-pre-wrap">
            {@ai_response}<span class="animate-pulse">▊</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Shared chat input component
  attr :myself, :any, required: true
  attr :input, :string, required: true
  attr :ai_enabled, :boolean, required: true
  attr :ai_streaming, :boolean, required: true

  defp chat_input(assigns) do
    ~H"""
    <form phx-submit="send_message" phx-target={@myself} class="p-3 border-t border-gray-700">
      <div class="flex gap-2">
        <input
          type="text"
          name="message"
          value={@input}
          phx-change="update_input"
          phx-target={@myself}
          placeholder={if @ai_enabled, do: "Message or @ai for AI...", else: "Type a message..."}
          class="flex-1 bg-gray-700 border border-gray-600 rounded px-3 py-2 text-sm text-white placeholder-gray-400 focus:outline-none focus:border-blue-500"
          autocomplete="off"
        />
        <button
          type="submit"
          disabled={@input == "" || @ai_streaming}
          class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white px-3 py-2 rounded text-sm transition-colors"
        >
          Send
        </button>
      </div>
      <div :if={@ai_enabled} class="text-xs text-gray-500 mt-1">
        Type @ai to ask the AI assistant
      </div>
    </form>
    """
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    expanded = !socket.assigns.expanded
    socket = assign(socket, :expanded, expanded)
    socket = if expanded, do: assign(socket, :unread_count, 0), else: socket
    {:noreply, socket}
  end

  def handle_event("toggle_ai", _params, socket) do
    {:noreply, assign(socket, :ai_enabled, !socket.assigns.ai_enabled)}
  end

  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input, message)}
  end

  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    room_id = socket.assigns.room_id
    user_name = socket.assigns.user_name
    user_id = get_user_id(socket.assigns.current_user)

    is_ai_request = socket.assigns.ai_enabled && String.starts_with?(String.trim(message), "@ai")

    user_message = %{
      role: "user",
      content: message,
      user_id: user_id,
      user_name: user_name
    }

    ChatStore.add_message(room_id, user_message)

    socket = assign(socket, :input, "")

    socket =
      if is_ai_request do
        ai_prompt = String.trim_leading(message, "@ai") |> String.trim()
        # Send to parent with the component's string ID for send_update
        component_id = socket.assigns[:id] || "chat"
        send(self(), {:generate_ai_response, room_id, ai_prompt, component_id})
        assign(socket, :ai_streaming, true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  # Private helpers

  defp get_user_name(nil), do: "Guest"
  defp get_user_name(%{display_name: name}) when is_binary(name), do: name
  defp get_user_name(%{email: email}) when is_binary(email), do: String.split(email, "@") |> hd()
  defp get_user_name(_), do: "User"

  defp get_user_id(nil), do: nil
  defp get_user_id(%{id: id}), do: id
  defp get_user_id(_), do: nil

  defp message_container_class(msg, current_user) do
    if is_own_message?(msg, current_user) do
      "flex justify-end"
    else
      "flex justify-start"
    end
  end

  defp message_bubble_class(msg, current_user) do
    base = "rounded-lg px-3 py-2 max-w-[85%] text-sm"

    cond do
      msg.role == "assistant" ->
        "#{base} bg-green-900/50 text-green-100"

      is_own_message?(msg, current_user) ->
        "#{base} bg-blue-600 text-white"

      true ->
        "#{base} bg-gray-700 text-gray-100"
    end
  end

  defp is_own_message?(msg, current_user) do
    user_id = get_user_id(current_user)
    user_id != nil && msg[:user_id] == user_id
  end

  defp message_sender_name(msg) do
    msg[:user_name] || msg.role
  end

  defp maybe_increment_unread(socket) do
    # Only increment unread in floating mode when collapsed
    if socket.assigns.mode == :floating && !socket.assigns.expanded do
      assign(socket, :unread_count, socket.assigns.unread_count + 1)
    else
      socket
    end
  end
end
