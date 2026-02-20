defmodule Sensocto.RoomMarkdown.AdminProtectionTest do
  @moduledoc """
  Tests for AdminProtection — Ed25519 signing and verification
  of admin section changes. Security-critical, pure functions only.
  """
  use ExUnit.Case, async: true

  alias Sensocto.RoomMarkdown.{AdminProtection, RoomDocument}

  defp sample_doc(overrides \\ %{}) do
    Map.merge(
      %{
        id: "room-1",
        name: "Protected Room",
        owner_id: "owner-1",
        admins: %{
          members: [
            %{id: "owner-1", role: :owner},
            %{id: "admin-1", role: :admin}
          ]
        }
      },
      overrides
    )
    |> RoomDocument.new()
  end

  # ── generate_keypair/0 ────────────────────────────────────────────

  describe "generate_keypair/0" do
    test "returns two binaries (public, private)" do
      {pub, priv} = AdminProtection.generate_keypair()
      assert is_binary(pub)
      assert is_binary(priv)
      assert byte_size(pub) == 32
    end

    test "generates different keypairs each time" do
      {pub1, _} = AdminProtection.generate_keypair()
      {pub2, _} = AdminProtection.generate_keypair()
      assert pub1 != pub2
    end
  end

  # ── encode/decode public key ──────────────────────────────────────

  describe "encode_public_key/1 and decode_public_key/1" do
    test "round-trip encoding" do
      {pub, _} = AdminProtection.generate_keypair()
      encoded = AdminProtection.encode_public_key(pub)
      assert is_binary(encoded)
      assert {:ok, decoded} = AdminProtection.decode_public_key(encoded)
      assert decoded == pub
    end

    test "decode rejects invalid base64" do
      assert :error = AdminProtection.decode_public_key("not!!valid!!base64!!")
    end
  end

  # ── sign + verify ─────────────────────────────────────────────────

  describe "sign_admin_change/3 and verify_admin_signature/2" do
    test "sign then verify succeeds with correct key" do
      {pub, priv} = AdminProtection.generate_keypair()
      doc = sample_doc()

      assert {:ok, signed_doc} = AdminProtection.sign_admin_change(doc, priv, "owner-1")
      assert signed_doc.admins.signature != nil
      assert signed_doc.admins.updated_by == "owner-1"

      assert :ok = AdminProtection.verify_admin_signature(signed_doc, pub)
    end

    test "verify fails with wrong key" do
      {_pub, priv} = AdminProtection.generate_keypair()
      {wrong_pub, _} = AdminProtection.generate_keypair()

      doc = sample_doc()
      {:ok, signed_doc} = AdminProtection.sign_admin_change(doc, priv, "owner-1")

      assert {:error, :invalid_signature} =
               AdminProtection.verify_admin_signature(signed_doc, wrong_pub)
    end

    test "verify fails with no signature" do
      {pub, _} = AdminProtection.generate_keypair()
      doc = sample_doc()

      assert {:error, :missing_signature} =
               AdminProtection.verify_admin_signature(doc, pub)
    end
  end

  # ── admin_section_changed?/2 ──────────────────────────────────────

  describe "admin_section_changed?/2" do
    test "returns false when members are the same" do
      doc = sample_doc()
      refute AdminProtection.admin_section_changed?(doc, doc)
    end

    test "returns true when members differ" do
      old = sample_doc()
      new = RoomDocument.add_member(old, "new-user", :member)
      assert AdminProtection.admin_section_changed?(old, new)
    end

    test "returns true when role changes" do
      old = sample_doc()
      new = RoomDocument.add_member(old, "admin-1", :member)
      assert AdminProtection.admin_section_changed?(old, new)
    end

    test "returns true when member removed" do
      old = sample_doc()
      new = RoomDocument.remove_member(old, "admin-1")
      assert AdminProtection.admin_section_changed?(old, new)
    end
  end

  # ── verify_admin_changes/3 ────────────────────────────────────────

  describe "verify_admin_changes/3" do
    test "no changes returns :ok without needing signature" do
      doc = sample_doc()
      get_key = fn _id -> nil end
      assert :ok = AdminProtection.verify_admin_changes(doc, doc, get_key)
    end

    test "changes with valid signature from authorized signer succeed" do
      {pub, priv} = AdminProtection.generate_keypair()
      old = sample_doc()
      new = RoomDocument.add_member(old, "new-user", :member)
      {:ok, signed_new} = AdminProtection.sign_admin_change(new, priv, "owner-1")

      get_key = fn "owner-1" -> pub end
      assert :ok = AdminProtection.verify_admin_changes(old, signed_new, get_key)
    end

    test "changes without signer return error" do
      old = sample_doc()
      new = RoomDocument.add_member(old, "new-user", :member)

      get_key = fn _id -> nil end
      assert {:error, :missing_signer} = AdminProtection.verify_admin_changes(old, new, get_key)
    end

    test "changes from unauthorized signer return error" do
      {_pub, priv} = AdminProtection.generate_keypair()
      old = sample_doc()
      new = RoomDocument.add_member(old, "new-user", :member)
      # Sign with a non-admin user
      {:ok, signed_new} = AdminProtection.sign_admin_change(new, priv, "random-user")

      get_key = fn _id -> nil end

      assert {:error, :unauthorized_signer} =
               AdminProtection.verify_admin_changes(old, signed_new, get_key)
    end

    test "changes with unknown signer key return error" do
      {_pub, priv} = AdminProtection.generate_keypair()
      old = sample_doc()
      new = RoomDocument.add_member(old, "new-user", :member)
      {:ok, signed_new} = AdminProtection.sign_admin_change(new, priv, "owner-1")

      # Key lookup returns nil
      get_key = fn _id -> nil end

      assert {:error, :unknown_signer} =
               AdminProtection.verify_admin_changes(old, signed_new, get_key)
    end
  end
end
