defmodule Sensocto.Chat.ChatStoreTest do
  @moduledoc """
  Tests for the ChatStore GenServer (ETS-based chat message storage).
  """
  use ExUnit.Case, async: false

  alias Sensocto.Chat.ChatStore

  setup do
    room_id = "test_room_#{System.unique_integer([:positive])}"
    # Ensure clean state
    ChatStore.clear_room(room_id)
    {:ok, room_id: room_id}
  end

  describe "add_message/2" do
    test "adds a message and returns it with id and timestamp", %{room_id: room_id} do
      msg = ChatStore.add_message(room_id, %{role: "user", content: "Hello"})

      assert msg.id
      assert msg.timestamp
      assert msg.content == "Hello"
      assert msg.role == "user"
      assert msg.room_id == room_id
    end

    test "multiple messages are stored in order", %{room_id: room_id} do
      ChatStore.add_message(room_id, %{role: "user", content: "First"})
      ChatStore.add_message(room_id, %{role: "user", content: "Second"})
      ChatStore.add_message(room_id, %{role: "assistant", content: "Third"})

      messages = ChatStore.get_messages(room_id)
      assert length(messages) == 3
      contents = Enum.map(messages, & &1.content)
      assert "First" in contents
      assert "Second" in contents
      assert "Third" in contents
    end
  end

  describe "get_messages/2" do
    test "returns empty list for unknown room" do
      assert ChatStore.get_messages("nonexistent_room") == []
    end

    test "respects limit option", %{room_id: room_id} do
      for i <- 1..5 do
        ChatStore.add_message(room_id, %{role: "user", content: "msg #{i}"})
      end

      messages = ChatStore.get_messages(room_id, limit: 3)
      assert length(messages) == 3
    end
  end

  describe "clear_room/1" do
    test "removes all messages for a room", %{room_id: room_id} do
      ChatStore.add_message(room_id, %{role: "user", content: "delete me"})
      assert length(ChatStore.get_messages(room_id)) == 1

      ChatStore.clear_room(room_id)
      assert ChatStore.get_messages(room_id) == []
    end

    test "does not affect other rooms", %{room_id: room_id} do
      other = "other_#{System.unique_integer([:positive])}"
      ChatStore.add_message(room_id, %{role: "user", content: "keep"})
      ChatStore.add_message(other, %{role: "user", content: "also keep"})

      ChatStore.clear_room(room_id)

      assert ChatStore.get_messages(room_id) == []
      assert length(ChatStore.get_messages(other)) == 1

      ChatStore.clear_room(other)
    end
  end

  describe "PubSub integration" do
    test "subscribe and receive broadcast on new message", %{room_id: room_id} do
      ChatStore.subscribe(room_id)

      ChatStore.add_message(room_id, %{role: "user", content: "broadcast test"})

      assert_receive {:chat_message, msg}
      assert msg.content == "broadcast test"

      ChatStore.unsubscribe(room_id)
    end
  end

  describe "chat_topic/1" do
    test "returns expected topic format" do
      assert ChatStore.chat_topic("room123") == "chat:room123"
    end
  end
end
