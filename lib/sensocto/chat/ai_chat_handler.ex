defmodule Sensocto.Chat.AIChatHandler do
  @moduledoc """
  Handles AI chat requests for the ChatComponent.

  Include this module in your LiveView to enable AI responses in chat.

  ## Usage

      defmodule MyLive do
        use Phoenix.LiveView
        use Sensocto.Chat.AIChatHandler

        # ... your LiveView code
      end

  This will add a handle_info clause for {:generate_ai_response, ...} messages.
  """

  alias Sensocto.AI.LLM
  alias Sensocto.AI.SensorContext
  alias Sensocto.Chat.ChatStore

  @ai_system_prompt """
  You are a helpful AI assistant in a collaborative sensor monitoring environment.
  Users are viewing and discussing sensor data together. Be concise and helpful.
  You can help explain sensor readings, suggest analyses, or answer questions.
  Keep responses brief since this is a chat context.
  """

  defmacro __using__(_opts) do
    quote do
      # Register the chat component for message forwarding
      def handle_info({:register_chat_component, component_id}, socket) do
        {:noreply, assign(socket, :chat_component_id_permanent, component_id)}
      end

      def handle_info({:generate_ai_response, room_id, prompt, component_id}, socket) do
        Sensocto.Chat.AIChatHandler.handle_ai_request(room_id, prompt, component_id)

        # Store the active streaming component ID
        {:noreply, assign(socket, :chat_component_id, component_id)}
      end

      def handle_info(
            {_pid, {:data, %{"done" => false, "message" => %{"content" => chunk}}}},
            socket
          ) do
        if socket.assigns[:chat_component_id] do
          send_update(SensoctoWeb.Components.ChatComponent,
            id: socket.assigns.chat_component_id,
            ai_chunk: chunk
          )
        end

        {:noreply, socket}
      end

      def handle_info({_pid, {:data, %{"done" => true}}}, socket) do
        if socket.assigns[:chat_component_id] do
          send_update(SensoctoWeb.Components.ChatComponent,
            id: socket.assigns.chat_component_id,
            ai_done: true
          )
        end

        # Clear streaming reference but keep permanent reference
        {:noreply, assign(socket, :chat_component_id, nil)}
      end

      def handle_info({:chat_message, message}, socket) do
        # Use permanent reference for forwarding chat messages
        component_id =
          socket.assigns[:chat_component_id] || socket.assigns[:chat_component_id_permanent]

        if component_id do
          send_update(SensoctoWeb.Components.ChatComponent,
            id: component_id,
            new_message: message
          )
        end

        {:noreply, socket}
      end

      def handle_info({:typing, user_name}, socket) do
        timers = socket.assigns[:typing_timers] || %{}

        if timers[user_name], do: Process.cancel_timer(timers[user_name])

        ref = Process.send_after(self(), {:clear_typing, user_name}, 3000)
        typing_users = Map.get(socket.assigns, :typing_users, MapSet.new()) |> MapSet.put(user_name)

        socket =
          socket
          |> assign(:typing_users, typing_users)
          |> assign(:typing_timers, Map.put(timers, user_name, ref))

        component_id =
          socket.assigns[:chat_component_id] || socket.assigns[:chat_component_id_permanent]

        if component_id do
          send_update(SensoctoWeb.Components.ChatComponent,
            id: component_id,
            typing_users: typing_users
          )
        end

        {:noreply, socket}
      end

      def handle_info({:clear_typing, user_name}, socket) do
        typing_users =
          Map.get(socket.assigns, :typing_users, MapSet.new()) |> MapSet.delete(user_name)

        socket = assign(socket, :typing_users, typing_users)

        component_id =
          socket.assigns[:chat_component_id] || socket.assigns[:chat_component_id_permanent]

        if component_id do
          send_update(SensoctoWeb.Components.ChatComponent,
            id: component_id,
            typing_users: typing_users
          )
        end

        {:noreply, socket}
      end
    end
  end

  @doc """
  Handle an AI chat request asynchronously.
  Spawns a task to stream the response back to the component.
  """
  def handle_ai_request(room_id, prompt, component_id) do
    parent = self()

    Task.start(fn ->
      system_prompt = build_system_prompt()

      case LLM.stream_chat([%{role: "user", content: prompt}], parent, system: system_prompt) do
        {:ok, _task} ->
          :ok

        {:error, reason} ->
          save_error_message(room_id, reason)

          Phoenix.LiveView.send_update(SensoctoWeb.Components.ChatComponent,
            id: component_id,
            ai_error: inspect(reason)
          )
      end
    end)
  end

  defp build_system_prompt do
    context = SensorContext.build_context(limit: 5)

    """
    #{@ai_system_prompt}

    ## Current Sensor Context
    #{context}
    """
  end

  defp save_error_message(room_id, reason) do
    ChatStore.add_message(room_id, %{
      role: "assistant",
      content: "Sorry, I encountered an error: #{inspect(reason)}",
      user_name: "AI Assistant"
    })
  end
end
