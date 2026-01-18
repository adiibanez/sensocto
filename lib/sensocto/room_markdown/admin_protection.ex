defmodule Sensocto.RoomMarkdown.AdminProtection do
  @moduledoc """
  Handles cryptographic protection of admin sections in room documents.

  Uses Ed25519 signatures to ensure admin changes are authorized.
  The signature covers: `room_id:sorted_member_ids:timestamp`

  ## Verification Flow

  1. When admin section is modified, it must be signed by an authorized user
  2. The signature is stored in the admins.signature field
  3. On CRDT merge, signatures are verified - invalid changes are rejected
  4. Owner can always override (owner's public key is trusted)

  ## Key Management

  User keypairs should be generated on signup and stored securely.
  The public key is used for signature verification.
  """

  alias Sensocto.RoomMarkdown.RoomDocument

  @doc """
  Signs an admin section change.

  Creates a signature over the canonical representation of the admin section:
  `room_id:sorted_member_ids:timestamp`

  Returns the updated document with the signature.
  """
  @spec sign_admin_change(RoomDocument.t(), binary(), String.t()) ::
          {:ok, RoomDocument.t()} | {:error, term()}
  def sign_admin_change(%RoomDocument{} = doc, private_key, signer_id)
      when is_binary(private_key) and is_binary(signer_id) do
    message = build_signing_message(doc)

    case sign_message(message, private_key) do
      {:ok, signature} ->
        updated_admins = %{
          doc.admins
          | signature: Base.encode64(signature),
            updated_by: signer_id
        }

        {:ok, %{doc | admins: updated_admins}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies that an admin section signature is valid.

  Checks that the signature matches the current admin section state
  and was created by an authorized user (owner or admin).
  """
  @spec verify_admin_signature(RoomDocument.t(), binary()) :: :ok | {:error, term()}
  def verify_admin_signature(%RoomDocument{} = doc, public_key) when is_binary(public_key) do
    case doc.admins.signature do
      nil ->
        {:error, :missing_signature}

      signature_b64 ->
        with {:ok, signature} <- Base.decode64(signature_b64),
             message <- build_signing_message(doc),
             :ok <- verify_signature(message, signature, public_key) do
          :ok
        else
          :error -> {:error, :invalid_signature_encoding}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Checks if admin changes between two documents are authorized.

  Compares old and new documents to detect admin section changes,
  and verifies the signature if changes were made.
  """
  @spec verify_admin_changes(RoomDocument.t(), RoomDocument.t(), (String.t() -> binary() | nil)) ::
          :ok | {:error, term()}
  def verify_admin_changes(%RoomDocument{} = old_doc, %RoomDocument{} = new_doc, get_public_key)
      when is_function(get_public_key, 1) do
    if admin_section_changed?(old_doc, new_doc) do
      # Admin section was modified - verify signature
      case new_doc.admins.updated_by do
        nil ->
          {:error, :missing_signer}

        signer_id ->
          # Check if signer was authorized in the OLD document
          if can_modify_admins?(old_doc, signer_id) do
            case get_public_key.(signer_id) do
              nil ->
                {:error, :unknown_signer}

              public_key ->
                verify_admin_signature(new_doc, public_key)
            end
          else
            {:error, :unauthorized_signer}
          end
      end
    else
      # No admin changes, no signature needed
      :ok
    end
  end

  @doc """
  Generates an Ed25519 keypair.

  Returns `{public_key, private_key}` as raw binaries.
  """
  @spec generate_keypair() :: {binary(), binary()}
  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {public_key, private_key}
  end

  @doc """
  Encodes a public key for storage (Base64).
  """
  @spec encode_public_key(binary()) :: String.t()
  def encode_public_key(public_key) when is_binary(public_key) do
    Base.encode64(public_key)
  end

  @doc """
  Decodes a public key from storage.
  """
  @spec decode_public_key(String.t()) :: {:ok, binary()} | :error
  def decode_public_key(encoded) when is_binary(encoded) do
    Base.decode64(encoded)
  end

  @doc """
  Checks if the admin section has changed between two documents.
  """
  @spec admin_section_changed?(RoomDocument.t(), RoomDocument.t()) :: boolean()
  def admin_section_changed?(%RoomDocument{} = old_doc, %RoomDocument{} = new_doc) do
    # Compare members lists (ignoring signature/updated_by which are metadata)
    old_members = normalize_members(old_doc.admins.members)
    new_members = normalize_members(new_doc.admins.members)

    old_members != new_members
  end

  # Private functions

  defp build_signing_message(%RoomDocument{} = doc) do
    # Canonical message format: room_id:sorted_member_ids:timestamp
    sorted_member_ids =
      doc.admins.members
      |> Enum.map(fn m -> "#{m.id}:#{m.role}" end)
      |> Enum.sort()
      |> Enum.join(",")

    timestamp = DateTime.to_iso8601(doc.updated_at)

    "#{doc.id}:#{sorted_member_ids}:#{timestamp}"
  end

  defp sign_message(message, private_key) do
    try do
      signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
      {:ok, signature}
    rescue
      e -> {:error, {:signing_error, e}}
    end
  end

  defp verify_signature(message, signature, public_key) do
    try do
      case :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]) do
        true -> :ok
        false -> {:error, :invalid_signature}
      end
    rescue
      e -> {:error, {:verification_error, e}}
    end
  end

  defp can_modify_admins?(%RoomDocument{} = doc, user_id) do
    # Owner can always modify
    if doc.owner_id == user_id do
      true
    else
      # Check if user is an admin in the document
      case RoomDocument.get_member_role(doc, user_id) do
        :owner -> true
        :admin -> true
        _ -> false
      end
    end
  end

  defp normalize_members(members) do
    members
    |> Enum.map(fn m -> {m.id, m.role} end)
    |> Enum.sort()
  end
end
