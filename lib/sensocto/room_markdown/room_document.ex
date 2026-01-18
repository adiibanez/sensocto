defmodule Sensocto.RoomMarkdown.RoomDocument do
  @moduledoc """
  Core struct representing a room as a markdown document with YAML frontmatter.

  This struct is the canonical representation of room data that can be:
  - Serialized to markdown for storage (Tigris/S3)
  - Synced via CRDT (Automerge)
  - Broadcast over gossip topics (Iroh P2P)

  ## Structure

  The markdown format uses YAML frontmatter for structured data and
  a markdown body for custom content:

  ```markdown
  ---
  id: "550e8400-e29b-41d4-a716-446655440000"
  name: "My Room"
  description: "A collaborative room"
  owner_id: "user-uuid"
  join_code: "ABC12345"
  version: 1
  created_at: "2025-01-17T12:00:00Z"
  updated_at: "2025-01-17T12:00:00Z"

  features:
    is_public: true
    calls_enabled: true
    media_playback_enabled: true
    object_3d_enabled: false

  admins:
    signature: "base64-sig"
    updated_by: "admin-id"
    members:
      - id: "owner-uuid"
        role: owner
      - id: "admin-uuid"
        role: admin

  configuration:
    theme: "dark"
    layout: "grid"
  ---

  # Room Content

  Custom markdown body for the room.
  ```
  """

  @type role :: :owner | :admin | :member
  @type member :: %{id: String.t(), role: role()}

  @type features :: %{
          is_public: boolean(),
          calls_enabled: boolean(),
          media_playback_enabled: boolean(),
          object_3d_enabled: boolean()
        }

  @type admins :: %{
          signature: String.t() | nil,
          updated_by: String.t() | nil,
          members: [member()]
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          owner_id: String.t(),
          join_code: String.t(),
          version: non_neg_integer(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          features: features(),
          admins: admins(),
          configuration: map(),
          body: String.t()
        }

  defstruct [
    :id,
    :name,
    :description,
    :owner_id,
    :join_code,
    version: 1,
    created_at: nil,
    updated_at: nil,
    features: %{
      is_public: true,
      calls_enabled: true,
      media_playback_enabled: true,
      object_3d_enabled: false
    },
    admins: %{
      signature: nil,
      updated_by: nil,
      members: []
    },
    configuration: %{},
    body: ""
  ]

  @doc """
  Creates a new RoomDocument from basic attributes.
  Generates defaults for timestamps, version, and features.
  """
  @spec new(map()) :: t()
  def new(attrs) do
    now = DateTime.utc_now()
    id = Map.get(attrs, :id) || Map.get(attrs, "id") || Ecto.UUID.generate()
    owner_id = Map.get(attrs, :owner_id) || Map.get(attrs, "owner_id")

    %__MODULE__{
      id: id,
      name: Map.get(attrs, :name) || Map.get(attrs, "name") || "Untitled Room",
      description: Map.get(attrs, :description) || Map.get(attrs, "description"),
      owner_id: owner_id,
      join_code:
        Map.get(attrs, :join_code) || Map.get(attrs, "join_code") || generate_join_code(),
      version: Map.get(attrs, :version) || Map.get(attrs, "version") || 1,
      created_at:
        parse_datetime(Map.get(attrs, :created_at) || Map.get(attrs, "created_at")) || now,
      updated_at:
        parse_datetime(Map.get(attrs, :updated_at) || Map.get(attrs, "updated_at")) || now,
      features: build_features(attrs),
      admins: build_admins(attrs, owner_id),
      configuration: Map.get(attrs, :configuration) || Map.get(attrs, "configuration") || %{},
      body: Map.get(attrs, :body) || Map.get(attrs, "body") || ""
    }
  end

  @doc """
  Creates a RoomDocument from in-memory RoomStore data.
  Converts the RoomStore map format to RoomDocument.
  """
  @spec from_room_store(map()) :: t()
  def from_room_store(room_data) do
    owner_id = Map.get(room_data, :owner_id) || Map.get(room_data, "owner_id")
    members_map = Map.get(room_data, :members) || Map.get(room_data, "members") || %{}

    # Build members list from the map format
    members_list =
      members_map
      |> Enum.map(fn {user_id, role} ->
        %{id: user_id, role: normalize_role(role)}
      end)
      |> Enum.sort_by(& &1.id)

    %__MODULE__{
      id: Map.get(room_data, :id) || Map.get(room_data, "id"),
      name: Map.get(room_data, :name) || Map.get(room_data, "name") || "Untitled Room",
      description: Map.get(room_data, :description) || Map.get(room_data, "description"),
      owner_id: owner_id,
      join_code: Map.get(room_data, :join_code) || Map.get(room_data, "join_code"),
      version: Map.get(room_data, :version) || Map.get(room_data, "version") || 1,
      created_at:
        parse_datetime(Map.get(room_data, :created_at) || Map.get(room_data, "created_at")),
      updated_at:
        parse_datetime(Map.get(room_data, :updated_at) || Map.get(room_data, "updated_at")),
      features: %{
        is_public: Map.get(room_data, :is_public, Map.get(room_data, "is_public", true)),
        calls_enabled:
          Map.get(room_data, :calls_enabled, Map.get(room_data, "calls_enabled", true)),
        media_playback_enabled:
          Map.get(
            room_data,
            :media_playback_enabled,
            Map.get(room_data, "media_playback_enabled", true)
          ),
        object_3d_enabled:
          Map.get(room_data, :object_3d_enabled, Map.get(room_data, "object_3d_enabled", false))
      },
      admins: %{
        signature: nil,
        updated_by: nil,
        members: members_list
      },
      configuration:
        Map.get(room_data, :configuration) || Map.get(room_data, "configuration") || %{},
      body: Map.get(room_data, :body) || Map.get(room_data, "body") || ""
    }
  end

  @doc """
  Converts RoomDocument back to RoomStore map format.
  """
  @spec to_room_store(t()) :: map()
  def to_room_store(%__MODULE__{} = doc) do
    # Convert members list back to map format
    members_map =
      doc.admins.members
      |> Enum.reduce(%{}, fn member, acc ->
        Map.put(acc, member.id, member.role)
      end)

    %{
      id: doc.id,
      name: doc.name,
      description: doc.description,
      owner_id: doc.owner_id,
      join_code: doc.join_code,
      is_public: doc.features.is_public,
      calls_enabled: doc.features.calls_enabled,
      media_playback_enabled: doc.features.media_playback_enabled,
      object_3d_enabled: doc.features.object_3d_enabled,
      configuration: doc.configuration,
      members: members_map,
      sensor_ids: MapSet.new(),
      created_at: doc.created_at,
      updated_at: doc.updated_at
    }
  end

  @doc """
  Increments the version and updates the timestamp.
  Call this before saving changes.
  """
  @spec bump_version(t()) :: t()
  def bump_version(%__MODULE__{} = doc) do
    %{doc | version: doc.version + 1, updated_at: DateTime.utc_now()}
  end

  @doc """
  Adds a member to the room document.
  """
  @spec add_member(t(), String.t(), role()) :: t()
  def add_member(%__MODULE__{} = doc, user_id, role) do
    # Check if member already exists
    existing_index = Enum.find_index(doc.admins.members, &(&1.id == user_id))

    members =
      if existing_index do
        List.update_at(doc.admins.members, existing_index, fn m -> %{m | role: role} end)
      else
        [%{id: user_id, role: role} | doc.admins.members]
      end

    updated_admins = %{doc.admins | members: Enum.sort_by(members, & &1.id)}
    %{doc | admins: updated_admins}
  end

  @doc """
  Removes a member from the room document.
  """
  @spec remove_member(t(), String.t()) :: t()
  def remove_member(%__MODULE__{} = doc, user_id) do
    members = Enum.reject(doc.admins.members, &(&1.id == user_id))
    updated_admins = %{doc.admins | members: members}
    %{doc | admins: updated_admins}
  end

  @doc """
  Gets a member's role.
  """
  @spec get_member_role(t(), String.t()) :: role() | nil
  def get_member_role(%__MODULE__{} = doc, user_id) do
    case Enum.find(doc.admins.members, &(&1.id == user_id)) do
      nil -> nil
      member -> member.role
    end
  end

  @doc """
  Checks if a user is a member of the room.
  """
  @spec member?(t(), String.t()) :: boolean()
  def member?(%__MODULE__{} = doc, user_id) do
    Enum.any?(doc.admins.members, &(&1.id == user_id))
  end

  @doc """
  Checks if a user can modify admin settings (is owner or admin).
  """
  @spec can_modify_admins?(t(), String.t()) :: boolean()
  def can_modify_admins?(%__MODULE__{} = doc, user_id) do
    case get_member_role(doc, user_id) do
      :owner -> true
      :admin -> true
      _ -> false
    end
  end

  @doc """
  Updates a feature flag.
  """
  @spec update_feature(t(), atom(), boolean()) :: t()
  def update_feature(%__MODULE__{} = doc, feature, value)
      when is_atom(feature) and is_boolean(value) do
    updated_features = Map.put(doc.features, feature, value)
    %{doc | features: updated_features}
  end

  @doc """
  Updates configuration.
  """
  @spec update_configuration(t(), map()) :: t()
  def update_configuration(%__MODULE__{} = doc, config) when is_map(config) do
    %{doc | configuration: Map.merge(doc.configuration, config)}
  end

  @doc """
  Updates the body content.
  """
  @spec update_body(t(), String.t()) :: t()
  def update_body(%__MODULE__{} = doc, body) when is_binary(body) do
    %{doc | body: body}
  end

  # Private helpers

  defp generate_join_code(length \\ 8) do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
  end

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  defp normalize_role(:owner), do: :owner
  defp normalize_role(:admin), do: :admin
  defp normalize_role(:member), do: :member
  defp normalize_role("owner"), do: :owner
  defp normalize_role("admin"), do: :admin
  defp normalize_role("member"), do: :member
  defp normalize_role(_), do: :member

  defp build_features(attrs) do
    features = Map.get(attrs, :features) || Map.get(attrs, "features") || %{}

    %{
      is_public: get_feature(attrs, features, :is_public, true),
      calls_enabled: get_feature(attrs, features, :calls_enabled, true),
      media_playback_enabled: get_feature(attrs, features, :media_playback_enabled, true),
      object_3d_enabled: get_feature(attrs, features, :object_3d_enabled, false)
    }
  end

  defp get_feature(attrs, features, key, default) do
    # Check features map first, then root attrs
    Map.get(features, key) ||
      Map.get(features, to_string(key)) ||
      Map.get(attrs, key) ||
      Map.get(attrs, to_string(key)) ||
      default
  end

  defp build_admins(attrs, owner_id) do
    admins = Map.get(attrs, :admins) || Map.get(attrs, "admins") || %{}
    members_list = Map.get(admins, :members) || Map.get(admins, "members") || []

    # Ensure owner is always in the members list
    members =
      members_list
      |> Enum.map(fn member ->
        id = Map.get(member, :id) || Map.get(member, "id")
        role = Map.get(member, :role) || Map.get(member, "role") || :member

        %{id: id, role: normalize_role(role)}
      end)

    members =
      if owner_id && !Enum.any?(members, &(&1.id == owner_id)) do
        [%{id: owner_id, role: :owner} | members]
      else
        members
      end

    %{
      signature: Map.get(admins, :signature) || Map.get(admins, "signature"),
      updated_by: Map.get(admins, :updated_by) || Map.get(admins, "updated_by"),
      members: Enum.sort_by(members, & &1.id)
    }
  end
end
