defmodule Sensocto.RoomMarkdown.RoomMarkdownTest do
  @moduledoc """
  Tests for the RoomMarkdown system: Parser, Serializer, and RoomDocument.
  These are pure function tests — no DB, no GenServer, no PubSub.
  """
  use ExUnit.Case, async: true

  alias Sensocto.RoomMarkdown.{Parser, Serializer, RoomDocument}

  defp sample_doc(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-room-123",
        name: "Test Room",
        description: "A test room",
        owner_id: "owner-uuid",
        join_code: "ABC12345",
        version: 1,
        body: "# Welcome\n\nThis is a test room."
      },
      overrides
    )
    |> RoomDocument.new()
  end

  # ══════════════════════════════════════════════════════════════════
  # RoomDocument
  # ══════════════════════════════════════════════════════════════════

  describe "RoomDocument.new/1" do
    test "creates document with provided attributes" do
      doc = sample_doc()

      assert doc.id == "test-room-123"
      assert doc.name == "Test Room"
      assert doc.owner_id == "owner-uuid"
      assert doc.version == 1
    end

    test "generates UUID if id not provided" do
      doc = RoomDocument.new(%{name: "No ID"})
      assert is_binary(doc.id)
      assert String.length(doc.id) == 36
    end

    test "generates join_code if not provided" do
      doc = RoomDocument.new(%{name: "No Code"})
      assert is_binary(doc.join_code)
      assert String.length(doc.join_code) == 8
    end

    test "defaults name to 'Untitled Room'" do
      doc = RoomDocument.new(%{})
      assert doc.name == "Untitled Room"
    end

    test "sets default feature flags" do
      doc = RoomDocument.new(%{})
      assert doc.features.is_public == true
      assert doc.features.calls_enabled == true
      assert doc.features.media_playback_enabled == true
      assert doc.features.object_3d_enabled == false
    end

    test "adds owner to admins.members automatically" do
      doc = RoomDocument.new(%{owner_id: "owner-1"})
      assert Enum.any?(doc.admins.members, &(&1.id == "owner-1" && &1.role == :owner))
    end

    test "sets timestamps" do
      doc = RoomDocument.new(%{})
      assert %DateTime{} = doc.created_at
      assert %DateTime{} = doc.updated_at
    end
  end

  describe "RoomDocument.add_member/3" do
    test "adds a new member" do
      doc = sample_doc() |> RoomDocument.add_member("user-1", :member)
      assert RoomDocument.member?(doc, "user-1")
      assert RoomDocument.get_member_role(doc, "user-1") == :member
    end

    test "updates role of existing member" do
      doc =
        sample_doc()
        |> RoomDocument.add_member("user-1", :member)
        |> RoomDocument.add_member("user-1", :admin)

      assert RoomDocument.get_member_role(doc, "user-1") == :admin
      # Should not duplicate
      member_count = Enum.count(doc.admins.members, &(&1.id == "user-1"))
      assert member_count == 1
    end
  end

  describe "RoomDocument.remove_member/2" do
    test "removes an existing member" do
      doc =
        sample_doc()
        |> RoomDocument.add_member("user-1", :member)
        |> RoomDocument.remove_member("user-1")

      refute RoomDocument.member?(doc, "user-1")
    end

    test "no-op for unknown user" do
      doc = sample_doc()
      original_count = length(doc.admins.members)
      doc = RoomDocument.remove_member(doc, "nonexistent")
      assert length(doc.admins.members) == original_count
    end
  end

  describe "RoomDocument.get_member_role/2" do
    test "returns role for known member" do
      doc = sample_doc()
      assert RoomDocument.get_member_role(doc, "owner-uuid") == :owner
    end

    test "returns nil for unknown member" do
      doc = sample_doc()
      assert RoomDocument.get_member_role(doc, "unknown") == nil
    end
  end

  describe "RoomDocument.member?/2" do
    test "true for member" do
      doc = sample_doc()
      assert RoomDocument.member?(doc, "owner-uuid")
    end

    test "false for non-member" do
      doc = sample_doc()
      refute RoomDocument.member?(doc, "stranger")
    end
  end

  describe "RoomDocument.can_modify_admins?/2" do
    test "owner can modify" do
      doc = sample_doc()
      assert RoomDocument.can_modify_admins?(doc, "owner-uuid")
    end

    test "admin can modify" do
      doc = sample_doc() |> RoomDocument.add_member("admin-1", :admin)
      assert RoomDocument.can_modify_admins?(doc, "admin-1")
    end

    test "regular member cannot modify" do
      doc = sample_doc() |> RoomDocument.add_member("member-1", :member)
      refute RoomDocument.can_modify_admins?(doc, "member-1")
    end

    test "unknown user cannot modify" do
      doc = sample_doc()
      refute RoomDocument.can_modify_admins?(doc, "unknown")
    end
  end

  describe "RoomDocument.bump_version/1" do
    test "increments version" do
      doc = sample_doc()
      bumped = RoomDocument.bump_version(doc)
      assert bumped.version == doc.version + 1
    end

    test "updates updated_at timestamp" do
      doc = sample_doc()
      old_ts = doc.updated_at
      Process.sleep(10)
      bumped = RoomDocument.bump_version(doc)
      assert DateTime.compare(bumped.updated_at, old_ts) in [:gt, :eq]
    end
  end

  describe "RoomDocument.update_feature/3" do
    test "updates a feature flag" do
      doc = sample_doc()
      updated = RoomDocument.update_feature(doc, :object_3d_enabled, true)
      assert updated.features.object_3d_enabled == true
    end
  end

  describe "RoomDocument.update_configuration/2" do
    test "merges new config" do
      doc = sample_doc()
      updated = RoomDocument.update_configuration(doc, %{theme: "dark"})
      assert updated.configuration.theme == "dark"
    end
  end

  describe "RoomDocument.update_body/2" do
    test "replaces body content" do
      doc = sample_doc()
      updated = RoomDocument.update_body(doc, "# New Content")
      assert updated.body == "# New Content"
    end
  end

  describe "RoomDocument room_store round-trip" do
    test "from_room_store -> to_room_store preserves key data" do
      store_data = %{
        id: "room-1",
        name: "Store Room",
        description: "From store",
        owner_id: "owner-1",
        join_code: "XYZ99999",
        is_public: true,
        members: %{"owner-1" => :owner, "member-1" => :member}
      }

      doc = RoomDocument.from_room_store(store_data)
      round_tripped = RoomDocument.to_room_store(doc)

      assert round_tripped.id == "room-1"
      assert round_tripped.name == "Store Room"
      assert round_tripped.owner_id == "owner-1"
      assert round_tripped.is_public == true
      assert round_tripped.members["owner-1"] == :owner
      assert round_tripped.members["member-1"] == :member
    end
  end

  # ══════════════════════════════════════════════════════════════════
  # Parser
  # ══════════════════════════════════════════════════════════════════

  describe "Parser.parse/1" do
    test "parses valid frontmatter + body" do
      markdown = """
      ---
      id: "room-abc"
      name: "Parsed Room"
      owner_id: "owner-1"
      join_code: "JOIN1234"
      version: 3
      ---

      # Room Body

      Some content here.
      """

      assert {:ok, doc} = Parser.parse(markdown)
      assert doc.id == "room-abc"
      assert doc.name == "Parsed Room"
      assert doc.owner_id == "owner-1"
      assert doc.version == 3
      assert doc.body =~ "Room Body"
    end

    test "parses content with no frontmatter" do
      assert {:ok, doc} = Parser.parse("# Just a body\nNo YAML here.")
      assert doc.body =~ "Just a body"
      assert doc.name == "Untitled Room"
    end

    test "handles missing closing delimiter" do
      markdown = """
      ---
      id: "no-close"
      name: "Unclosed"
      """

      assert {:ok, doc} = Parser.parse(markdown)
      assert doc.id == "no-close"
    end

    test "rejects non-binary input" do
      assert {:error, :invalid_content} = Parser.parse(nil)
      assert {:error, :invalid_content} = Parser.parse(123)
    end
  end

  describe "Parser.parse!/1" do
    test "returns document on success" do
      doc = Parser.parse!("---\nname: Test\n---\nBody")
      assert doc.name == "Test"
    end

    test "raises on invalid input" do
      assert_raise RuntimeError, fn -> Parser.parse!(nil) end
    end
  end

  describe "Parser.validate/1" do
    test "valid document passes" do
      doc = sample_doc()
      assert :ok = Parser.validate(doc)
    end

    test "missing id fails" do
      doc = %{sample_doc() | id: nil}
      assert {:error, errors} = Parser.validate(doc)
      assert {:missing_required_field, :id} in errors
    end

    test "missing name fails" do
      doc = %{sample_doc() | name: nil}
      assert {:error, errors} = Parser.validate(doc)
      assert {:missing_required_field, :name} in errors
    end

    test "missing owner_id fails" do
      doc = %{sample_doc() | owner_id: nil}
      assert {:error, errors} = Parser.validate(doc)
      assert {:missing_required_field, :owner_id} in errors
    end

    test "empty string counts as missing" do
      doc = %{sample_doc() | name: "  "}
      assert {:error, errors} = Parser.validate(doc)
      assert {:missing_required_field, :name} in errors
    end
  end

  describe "Parser.extract_protected_sections/1" do
    test "extracts protected sections" do
      body = """
      Regular content

      <!-- PROTECTED:admins -->
      Protected admin content
      <!-- /PROTECTED:admins -->

      More content
      """

      sections = Parser.extract_protected_sections(body)
      assert Map.has_key?(sections, "admins")
      assert sections["admins"] =~ "Protected admin content"
    end

    test "returns empty map when no sections" do
      assert %{} = Parser.extract_protected_sections("Just regular content")
    end

    test "handles missing end tag" do
      body = "<!-- PROTECTED:admins -->\nContent without close"
      assert %{} = Parser.extract_protected_sections(body)
    end

    test "returns empty for non-binary" do
      assert %{} = Parser.extract_protected_sections(nil)
    end
  end

  # ══════════════════════════════════════════════════════════════════
  # Serializer
  # ══════════════════════════════════════════════════════════════════

  describe "Serializer.serialize/1" do
    test "produces markdown with YAML frontmatter" do
      doc = sample_doc()
      result = Serializer.serialize(doc)

      assert String.starts_with?(result, "---\n")
      assert result =~ "name: Test Room"
      assert result =~ "owner_id: owner-uuid"
      assert result =~ "# Welcome"
    end

    test "contains closing delimiter" do
      result = Serializer.serialize(sample_doc())
      # Should have two ---  delimiters
      assert length(String.split(result, "---")) >= 3
    end
  end

  describe "Serializer.to_map/1" do
    test "produces correctly keyed map" do
      doc = sample_doc()
      map = Serializer.to_map(doc)

      assert map["id"] == "test-room-123"
      assert map["name"] == "Test Room"
      assert map["owner_id"] == "owner-uuid"
      assert map["features"]["is_public"] == true
      assert is_list(map["admins"]["members"])
    end
  end

  describe "Serializer.to_json/1" do
    test "produces valid JSON" do
      json = Serializer.to_json(sample_doc())
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["name"] == "Test Room"
    end
  end

  describe "Serializer.filename/1" do
    test "from document" do
      assert Serializer.filename(sample_doc()) == "room-test-room-123.md"
    end

    test "from string id" do
      assert Serializer.filename("abc-123") == "room-abc-123.md"
    end
  end

  describe "Serializer.storage_key/1" do
    test "from document" do
      assert Serializer.storage_key(sample_doc()) == "rooms/test-room-123/room.md"
    end

    test "from string id" do
      assert Serializer.storage_key("abc-123") == "rooms/abc-123/room.md"
    end
  end

  # ══════════════════════════════════════════════════════════════════
  # Round-trip: Serialize → Parse
  # ══════════════════════════════════════════════════════════════════

  describe "serialize → parse round-trip" do
    test "preserves core fields" do
      original = sample_doc()
      serialized = Serializer.serialize(original)
      assert {:ok, parsed} = Parser.parse(serialized)

      assert parsed.id == original.id
      assert parsed.name == original.name
      assert parsed.owner_id == original.owner_id
      assert parsed.join_code == original.join_code
      assert parsed.version == original.version
    end

    test "preserves body content" do
      original = sample_doc(%{body: "# Custom Content\n\nWith paragraphs."})
      serialized = Serializer.serialize(original)
      {:ok, parsed} = Parser.parse(serialized)

      assert parsed.body =~ "Custom Content"
      assert parsed.body =~ "With paragraphs"
    end
  end
end
