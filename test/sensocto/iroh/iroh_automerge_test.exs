defmodule Sensocto.Iroh.IrohAutomergeTest do
  @moduledoc """
  Tests for iroh_ex automerge CRDT integration.

  These tests verify that the automerge functionality from iroh_ex 0.0.14
  works correctly for collaborative data structures.
  """
  use ExUnit.Case, async: false
  alias IrohEx.Native
  alias IrohEx.NodeConfig

  @moduletag :iroh
  @moduletag timeout: 60_000

  setup do
    # Create a fresh iroh node for each test
    node_config = NodeConfig.build()
    node_ref = Native.create_node(self(), node_config)

    # Give the node time to initialize
    Process.sleep(500)

    on_exit(fn ->
      if is_reference(node_ref) do
        try do
          Native.shutdown(node_ref)
        rescue
          _ -> :ok
        end
      end
    end)

    {:ok, node_ref: node_ref}
  end

  describe "automerge document management" do
    test "creates a new automerge document", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      assert is_binary(doc_id)
      assert byte_size(doc_id) > 0
    end

    test "lists automerge documents", %{node_ref: node_ref} do
      # Create a document
      doc_id = Native.automerge_create_doc(node_ref)

      # List should include the new doc
      docs = Native.automerge_list_docs(node_ref)

      assert is_list(docs)
      assert doc_id in docs
    end

    test "deletes an automerge document", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      result = Native.automerge_delete_doc(node_ref, doc_id)

      assert result == true

      # Verify doc is gone from list
      docs = Native.automerge_list_docs(node_ref)
      refute doc_id in docs
    end

    test "forks an existing document", %{node_ref: node_ref} do
      # Create original doc with data
      doc_id = Native.automerge_create_doc(node_ref)
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "name", "original")

      # Fork the document
      forked_id = Native.automerge_fork_doc(node_ref, doc_id)

      assert is_binary(forked_id)
      assert forked_id != doc_id

      # Forked doc should have same data
      value = Native.automerge_map_get(node_ref, forked_id, [], "name")
      assert value == "original"
    end

    test "saves and loads a document", %{node_ref: node_ref} do
      # Create doc with data
      doc_id = Native.automerge_create_doc(node_ref)
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "key", "value123")

      # Save to binary
      saved_data = Native.automerge_save_doc(node_ref, doc_id)

      assert is_binary(saved_data)
      assert byte_size(saved_data) > 0

      # Load into new doc
      loaded_id = Native.automerge_load_doc(node_ref, saved_data)

      assert is_binary(loaded_id)

      # Verify data is preserved
      value = Native.automerge_map_get(node_ref, loaded_id, [], "key")
      assert value == "value123"
    end
  end

  describe "automerge map operations" do
    test "puts and gets scalar values", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      :ok = Native.automerge_map_put(node_ref, doc_id, [], "string_key", "hello")
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "int_key", 42)
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "float_key", 3.14)
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "bool_key", true)

      assert Native.automerge_map_get(node_ref, doc_id, [], "string_key") == "hello"
      assert Native.automerge_map_get(node_ref, doc_id, [], "int_key") == 42
      assert Native.automerge_map_get(node_ref, doc_id, [], "float_key") == 3.14
      assert Native.automerge_map_get(node_ref, doc_id, [], "bool_key") == true
    end

    test "puts nested objects", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      # Create nested map structure
      _obj_id = Native.automerge_map_put_object(node_ref, doc_id, [], "user", "map")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["user"], "name", "Alice")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["user"], "age", 30)

      # Create deeper nesting
      _addr_id = Native.automerge_map_put_object(node_ref, doc_id, ["user"], "address", "map")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["user", "address"], "city", "Berlin")

      # Verify nested values
      assert Native.automerge_map_get(node_ref, doc_id, ["user"], "name") == "Alice"
      assert Native.automerge_map_get(node_ref, doc_id, ["user"], "age") == 30
      assert Native.automerge_map_get(node_ref, doc_id, ["user", "address"], "city") == "Berlin"
    end

    test "deletes keys from map", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      :ok = Native.automerge_map_put(node_ref, doc_id, [], "to_delete", "value")
      assert Native.automerge_map_get(node_ref, doc_id, [], "to_delete") == "value"

      :ok = Native.automerge_map_delete(node_ref, doc_id, [], "to_delete")

      # Should return :not_found for deleted key
      assert Native.automerge_map_get(node_ref, doc_id, [], "to_delete") == :not_found
    end

    test "lists map keys", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      :ok = Native.automerge_map_put(node_ref, doc_id, [], "key1", "value1")
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "key2", "value2")
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "key3", "value3")

      keys = Native.automerge_map_keys(node_ref, doc_id, [])

      assert is_list(keys)
      assert "key1" in keys
      assert "key2" in keys
      assert "key3" in keys
    end
  end

  describe "automerge list operations" do
    test "pushes and gets list values", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      # Create a list object
      _list_id = Native.automerge_map_put_object(node_ref, doc_id, [], "items", "list")

      # Push items
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "first")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "second")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "third")

      # Verify values
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 0) == "first"
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 1) == "second"
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 2) == "third"

      # Verify length
      assert Native.automerge_list_length(node_ref, doc_id, ["items"]) == 3
    end

    test "inserts into list at index", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      _list_id = Native.automerge_map_put_object(node_ref, doc_id, [], "items", "list")

      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "first")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "third")

      # Insert at index 1
      :ok = Native.automerge_list_insert(node_ref, doc_id, ["items"], 1, "second")

      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 0) == "first"
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 1) == "second"
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 2) == "third"
    end

    test "deletes from list", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      _list_id = Native.automerge_map_put_object(node_ref, doc_id, [], "items", "list")

      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "first")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "second")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["items"], "third")

      # Delete middle item
      :ok = Native.automerge_list_delete(node_ref, doc_id, ["items"], 1)

      assert Native.automerge_list_length(node_ref, doc_id, ["items"]) == 2
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 0) == "first"
      assert Native.automerge_list_get(node_ref, doc_id, ["items"], 1) == "third"
    end
  end

  describe "automerge text operations" do
    test "creates text with initial content", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      _text_id = Native.automerge_text_create(node_ref, doc_id, [], "content", "Hello World")

      text = Native.automerge_text_get(node_ref, doc_id, ["content"])

      assert text == "Hello World"
    end

    test "inserts text at position", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      _text_id = Native.automerge_text_create(node_ref, doc_id, [], "content", "Hello World")

      # Insert " Beautiful" at position 5 (after "Hello")
      :ok = Native.automerge_text_insert(node_ref, doc_id, ["content"], 5, " Beautiful")

      text = Native.automerge_text_get(node_ref, doc_id, ["content"])

      assert text == "Hello Beautiful World"
    end

    test "deletes text at position", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      _text_id =
        Native.automerge_text_create(node_ref, doc_id, [], "content", "Hello Beautiful World")

      # Delete " Beautiful" (positions 5-15, length 10)
      :ok = Native.automerge_text_delete(node_ref, doc_id, ["content"], 5, 10)

      text = Native.automerge_text_get(node_ref, doc_id, ["content"])

      assert text == "Hello World"
    end
  end

  describe "automerge counter operations" do
    test "increments counter", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      # Initial increment creates counter
      result1 = Native.automerge_counter_increment(node_ref, doc_id, [], "visits", 1)
      assert result1 == 1

      # Subsequent increments
      result2 = Native.automerge_counter_increment(node_ref, doc_id, [], "visits", 5)
      assert result2 == 6

      # Can also decrement
      result3 = Native.automerge_counter_increment(node_ref, doc_id, [], "visits", -2)
      assert result3 == 4

      # Get current value
      value = Native.automerge_counter_get(node_ref, doc_id, [], "visits")
      assert value == 4
    end
  end

  describe "automerge merge operations" do
    test "merges forked documents", %{node_ref: node_ref} do
      # Create original doc
      original_id = Native.automerge_create_doc(node_ref)
      :ok = Native.automerge_map_put(node_ref, original_id, [], "original", "value")

      # Fork it to create two divergent copies
      doc1_id = Native.automerge_fork_doc(node_ref, original_id)
      doc2_id = Native.automerge_fork_doc(node_ref, original_id)

      # Make different edits on each fork
      :ok = Native.automerge_map_put(node_ref, doc1_id, [], "from_doc1", "value1")
      :ok = Native.automerge_map_put(node_ref, doc2_id, [], "from_doc2", "value2")

      # Save doc2 as bytes
      doc2_bytes = Native.automerge_save_doc(node_ref, doc2_id)

      # Merge doc2 into doc1
      :ok = Native.automerge_merge(node_ref, doc1_id, doc2_bytes)

      # Doc1 should now have all values
      assert Native.automerge_map_get(node_ref, doc1_id, [], "original") == "value"
      assert Native.automerge_map_get(node_ref, doc1_id, [], "from_doc1") == "value1"
      assert Native.automerge_map_get(node_ref, doc1_id, [], "from_doc2") == "value2"
    end
  end

  describe "automerge JSON export" do
    test "exports document as JSON", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      :ok = Native.automerge_map_put(node_ref, doc_id, [], "name", "Test")
      :ok = Native.automerge_map_put(node_ref, doc_id, [], "count", 42)

      json_str = Native.automerge_to_json(node_ref, doc_id)

      assert is_binary(json_str)

      # Should be valid JSON
      {:ok, decoded} = Jason.decode(json_str)

      assert decoded["name"] == "Test"
      assert decoded["count"] == 42
    end
  end

  describe "room state use case" do
    @tag :integration
    test "stores and syncs room state", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      # Set up room structure
      _room_id = Native.automerge_map_put_object(node_ref, doc_id, [], "room", "map")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["room"], "id", "room-123")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["room"], "name", "Test Room")
      :ok = Native.automerge_map_put(node_ref, doc_id, ["room"], "media_playback_enabled", true)
      :ok = Native.automerge_map_put(node_ref, doc_id, ["room"], "calls_enabled", true)
      :ok = Native.automerge_map_put(node_ref, doc_id, ["room"], "object_3d_enabled", false)

      # Set up participants list
      _participants_id =
        Native.automerge_map_put_object(node_ref, doc_id, ["room"], "participants", "list")

      # Add participants
      :ok = Native.automerge_list_push(node_ref, doc_id, ["room", "participants"], "user-1")
      :ok = Native.automerge_list_push(node_ref, doc_id, ["room", "participants"], "user-2")

      # Set up shared state (e.g., media player position)
      _media_id =
        Native.automerge_map_put_object(node_ref, doc_id, ["room"], "media_state", "map")

      :ok =
        Native.automerge_map_put(
          node_ref,
          doc_id,
          ["room", "media_state"],
          "current_url",
          "https://youtube.com/watch?v=abc"
        )

      :ok = Native.automerge_map_put(node_ref, doc_id, ["room", "media_state"], "position_ms", 0)

      :ok =
        Native.automerge_map_put(node_ref, doc_id, ["room", "media_state"], "is_playing", false)

      # Export and verify
      json_str = Native.automerge_to_json(node_ref, doc_id)
      {:ok, state} = Jason.decode(json_str)

      assert state["room"]["id"] == "room-123"
      assert state["room"]["name"] == "Test Room"
      assert state["room"]["participants"] == ["user-1", "user-2"]
      assert state["room"]["media_state"]["current_url"] == "https://youtube.com/watch?v=abc"
    end

    @tag :integration
    test "handles concurrent edits with counter", %{node_ref: node_ref} do
      doc_id = Native.automerge_create_doc(node_ref)

      # Track participant count with counter
      Native.automerge_counter_increment(node_ref, doc_id, [], "participant_count", 1)
      Native.automerge_counter_increment(node_ref, doc_id, [], "participant_count", 1)

      count = Native.automerge_counter_get(node_ref, doc_id, [], "participant_count")
      assert count == 2

      # Someone leaves
      Native.automerge_counter_increment(node_ref, doc_id, [], "participant_count", -1)

      count = Native.automerge_counter_get(node_ref, doc_id, [], "participant_count")
      assert count == 1
    end
  end
end
