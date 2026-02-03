defmodule Sensocto.Chat.ChatStore do
  @moduledoc """
  ETS-based storage for chat messages across rooms and lobbies.

  Messages are stored per-room with automatic cleanup of old messages.
  Supports both user-to-user chat and AI agent conversations.
  """
  use GenServer

  require Logger

  @table_name :sensocto_chat_messages
  @max_messages_per_room 100
  @cleanup_interval :timer.minutes(30)
  @message_ttl :timer.hours(24)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a message to a room's chat history.

  ## Parameters
    - room_id: The room/lobby identifier (string)
    - message: Map with :role, :content, :user_id (optional), :user_name (optional)

  ## Returns
    The message with :id and :timestamp added
  """
  def add_message(room_id, message) when is_binary(room_id) and is_map(message) do
    GenServer.call(__MODULE__, {:add_message, room_id, message})
  end

  @doc """
  Get messages for a room, optionally limited.
  """
  def get_messages(room_id, opts \\ []) when is_binary(room_id) do
    limit = Keyword.get(opts, :limit, @max_messages_per_room)
    GenServer.call(__MODULE__, {:get_messages, room_id, limit})
  end

  @doc """
  Clear all messages for a room.
  """
  def clear_room(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:clear_room, room_id})
  end

  @doc """
  Subscribe to chat updates for a room via PubSub.
  """
  def subscribe(room_id) when is_binary(room_id) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, chat_topic(room_id))
  end

  @doc """
  Unsubscribe from chat updates.
  """
  def unsubscribe(room_id) when is_binary(room_id) do
    Phoenix.PubSub.unsubscribe(Sensocto.PubSub, chat_topic(room_id))
  end

  @doc """
  Get the PubSub topic for a room's chat.
  """
  def chat_topic(room_id), do: "chat:#{room_id}"

  # Server Callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :ordered_set, :public, read_concurrency: true])
    schedule_cleanup()
    Logger.info("ChatStore started with ETS table #{@table_name}")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:add_message, room_id, message}, _from, state) do
    timestamp = System.system_time(:millisecond)
    id = generate_message_id()

    full_message =
      message
      |> Map.put(:id, id)
      |> Map.put(:timestamp, timestamp)
      |> Map.put(:room_id, room_id)

    key = {room_id, timestamp, id}
    :ets.insert(@table_name, {key, full_message})

    enforce_message_limit(room_id)

    broadcast_message(room_id, full_message)

    {:reply, full_message, state}
  end

  @impl true
  def handle_call({:get_messages, room_id, limit}, _from, state) do
    messages =
      @table_name
      |> :ets.select([{{{room_id, :"$1", :"$2"}, :"$3"}, [], [:"$3"]}])
      |> Enum.sort_by(& &1.timestamp)
      |> Enum.take(-limit)

    {:reply, messages, state}
  end

  @impl true
  def handle_call({:clear_room, room_id}, _from, state) do
    :ets.select_delete(@table_name, [{{{room_id, :_, :_}, :_}, [], [true]}])
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_messages()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private helpers

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp enforce_message_limit(room_id) do
    messages =
      @table_name
      |> :ets.select([{{{room_id, :"$1", :"$2"}, :_}, [], [{{room_id, :"$1", :"$2"}}]}])
      |> Enum.sort()

    if length(messages) > @max_messages_per_room do
      to_delete = Enum.take(messages, length(messages) - @max_messages_per_room)
      Enum.each(to_delete, &:ets.delete(@table_name, &1))
    end
  end

  defp cleanup_old_messages do
    cutoff = System.system_time(:millisecond) - @message_ttl

    deleted =
      :ets.select_delete(@table_name, [
        {{{:_, :"$1", :_}, :_}, [{:<, :"$1", cutoff}], [true]}
      ])

    if deleted > 0 do
      Logger.debug("ChatStore cleaned up #{deleted} old messages")
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp broadcast_message(room_id, message) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, chat_topic(room_id), {:chat_message, message})
  end
end
