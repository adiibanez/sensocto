defmodule Sensocto.RoomMarkdown.Serializer do
  @moduledoc """
  Serializes RoomDocument structs to markdown with YAML frontmatter.

  Generates markdown files that can be stored in Tigris/S3 and
  synced via CRDT.
  """

  alias Sensocto.RoomMarkdown.RoomDocument

  @frontmatter_delimiter "---"

  @doc """
  Serializes a RoomDocument to markdown string.
  """
  @spec serialize(RoomDocument.t()) :: String.t()
  def serialize(%RoomDocument{} = doc) do
    frontmatter = build_frontmatter(doc)
    yaml = encode_yaml(frontmatter)

    """
    #{@frontmatter_delimiter}
    #{yaml}#{@frontmatter_delimiter}

    #{doc.body}
    """
    |> String.trim_trailing()
  end

  @doc """
  Serializes a RoomDocument to JSON (for CRDT storage).
  """
  @spec to_json(RoomDocument.t()) :: String.t()
  def to_json(%RoomDocument{} = doc) do
    doc
    |> to_map()
    |> Jason.encode!()
  end

  @doc """
  Converts RoomDocument to a plain map (for JSON/CRDT).
  """
  @spec to_map(RoomDocument.t()) :: map()
  def to_map(%RoomDocument{} = doc) do
    %{
      "id" => doc.id,
      "name" => doc.name,
      "description" => doc.description,
      "owner_id" => doc.owner_id,
      "join_code" => doc.join_code,
      "version" => doc.version,
      "created_at" => format_datetime(doc.created_at),
      "updated_at" => format_datetime(doc.updated_at),
      "features" => %{
        "is_public" => doc.features.is_public,
        "calls_enabled" => doc.features.calls_enabled,
        "media_playback_enabled" => doc.features.media_playback_enabled,
        "object_3d_enabled" => doc.features.object_3d_enabled
      },
      "admins" => %{
        "signature" => doc.admins.signature,
        "updated_by" => doc.admins.updated_by,
        "members" => Enum.map(doc.admins.members, &serialize_member/1)
      },
      "configuration" => doc.configuration,
      "body" => doc.body
    }
  end

  @doc """
  Generates the filename for a room document.
  Format: `room-{id}.md`
  """
  @spec filename(RoomDocument.t() | String.t()) :: String.t()
  def filename(%RoomDocument{id: id}), do: "room-#{id}.md"
  def filename(room_id) when is_binary(room_id), do: "room-#{room_id}.md"

  @doc """
  Generates the S3/Tigris key path for a room document.
  Format: `rooms/{id}/room.md`
  """
  @spec storage_key(RoomDocument.t() | String.t()) :: String.t()
  def storage_key(%RoomDocument{id: id}), do: "rooms/#{id}/room.md"
  def storage_key(room_id) when is_binary(room_id), do: "rooms/#{room_id}/room.md"

  # Private functions

  defp build_frontmatter(%RoomDocument{} = doc) do
    %{
      "id" => doc.id,
      "name" => doc.name,
      "description" => doc.description,
      "owner_id" => doc.owner_id,
      "join_code" => doc.join_code,
      "version" => doc.version,
      "created_at" => format_datetime(doc.created_at),
      "updated_at" => format_datetime(doc.updated_at),
      "features" => %{
        "is_public" => doc.features.is_public,
        "calls_enabled" => doc.features.calls_enabled,
        "media_playback_enabled" => doc.features.media_playback_enabled,
        "object_3d_enabled" => doc.features.object_3d_enabled
      },
      "admins" => %{
        "signature" => doc.admins.signature,
        "updated_by" => doc.admins.updated_by,
        "members" => Enum.map(doc.admins.members, &serialize_member/1)
      },
      "configuration" => doc.configuration
    }
    |> remove_nil_values()
  end

  defp serialize_member(%{id: id, role: role}) do
    %{"id" => id, "role" => Atom.to_string(role)}
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(str) when is_binary(str), do: str

  defp remove_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {k, remove_nil_values(v)} end)
    |> Map.new()
  end

  defp remove_nil_values(list) when is_list(list) do
    Enum.map(list, &remove_nil_values/1)
  end

  defp remove_nil_values(value), do: value

  defp encode_yaml(data) do
    # Simple YAML encoder for our specific structure
    # Using a custom encoder to maintain control over formatting
    encode_yaml_value(data, 0)
  end

  defp encode_yaml_value(map, indent) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> yaml_key_order(k) end)
    |> Enum.map(fn {key, value} ->
      indent_str = String.duplicate("  ", indent)
      encoded_value = encode_yaml_field(key, value, indent)
      "#{indent_str}#{key}: #{encoded_value}"
    end)
    |> Enum.join("\n")
    |> then(&(&1 <> "\n"))
  end

  defp encode_yaml_field(_key, value, indent) when is_map(value) and map_size(value) > 0 do
    "\n" <> encode_yaml_value(value, indent + 1)
  end

  defp encode_yaml_field(_key, value, indent) when is_list(value) and length(value) > 0 do
    items =
      value
      |> Enum.map(fn item ->
        indent_str = String.duplicate("  ", indent + 1)

        if is_map(item) do
          # Format map items with - prefix on first field
          item_lines =
            item
            |> Enum.map(fn {k, v} -> "#{k}: #{encode_yaml_primitive(v)}" end)
            |> Enum.join("\n#{indent_str}  ")

          "#{indent_str}- #{item_lines}"
        else
          "#{indent_str}- #{encode_yaml_primitive(item)}"
        end
      end)
      |> Enum.join("\n")

    "\n" <> items
  end

  defp encode_yaml_field(_key, value, _indent) do
    encode_yaml_primitive(value)
  end

  defp encode_yaml_primitive(nil), do: "null"
  defp encode_yaml_primitive(true), do: "true"
  defp encode_yaml_primitive(false), do: "false"
  defp encode_yaml_primitive(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_yaml_primitive(value) when is_float(value), do: Float.to_string(value)
  defp encode_yaml_primitive(value) when is_atom(value), do: Atom.to_string(value)

  defp encode_yaml_primitive(value) when is_binary(value) do
    if needs_quoting?(value) do
      ~s("#{escape_yaml_string(value)}")
    else
      value
    end
  end

  defp encode_yaml_primitive(value) when is_map(value) and map_size(value) == 0, do: "{}"
  defp encode_yaml_primitive(value) when is_list(value) and length(value) == 0, do: "[]"

  defp needs_quoting?(str) do
    String.contains?(str, [
      "\n",
      "\"",
      "'",
      ":",
      "#",
      "{",
      "}",
      "[",
      "]",
      ",",
      "&",
      "*",
      "!",
      "|",
      ">",
      "%",
      "@",
      "`"
    ]) ||
      String.starts_with?(str, " ") ||
      String.ends_with?(str, " ") ||
      String.match?(str, ~r/^\d/) ||
      str in ["true", "false", "null", "yes", "no", "on", "off"]
  end

  defp escape_yaml_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  # Order keys for consistent output
  defp yaml_key_order("id"), do: 0
  defp yaml_key_order("name"), do: 1
  defp yaml_key_order("description"), do: 2
  defp yaml_key_order("owner_id"), do: 3
  defp yaml_key_order("join_code"), do: 4
  defp yaml_key_order("version"), do: 5
  defp yaml_key_order("created_at"), do: 6
  defp yaml_key_order("updated_at"), do: 7
  defp yaml_key_order("features"), do: 8
  defp yaml_key_order("admins"), do: 9
  defp yaml_key_order("configuration"), do: 10
  defp yaml_key_order(_), do: 99
end
