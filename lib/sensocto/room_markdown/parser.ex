defmodule Sensocto.RoomMarkdown.Parser do
  @moduledoc """
  Parses room markdown files with YAML frontmatter.

  Extracts structured data from the frontmatter and preserves the
  markdown body for custom room content.

  ## Format

  The expected format is:
  ```markdown
  ---
  id: "uuid"
  name: "Room Name"
  # ... other YAML fields
  ---

  # Markdown Body

  Content here...

  <!-- PROTECTED:section_name -->
  Protected content
  <!-- /PROTECTED:section_name -->
  ```
  """

  alias Sensocto.RoomMarkdown.RoomDocument

  @frontmatter_delimiter "---"
  @protected_start_pattern ~r/<!--\s*PROTECTED:(\w+)\s*-->/

  @doc """
  Parses a markdown string into a RoomDocument.

  Returns `{:ok, document}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def parse(content) when is_binary(content) do
    {yaml_content, body} = split_frontmatter(content)

    case parse_yaml(yaml_content) do
      {:ok, frontmatter} ->
        document = build_document(frontmatter, body)
        {:ok, document}

      {:error, reason} ->
        {:error, {:yaml_parse_error, reason}}
    end
  end

  def parse(_), do: {:error, :invalid_content}

  @doc """
  Parses a markdown string, raising on error.
  """
  @spec parse!(String.t()) :: RoomDocument.t()
  def parse!(content) do
    case parse(content) do
      {:ok, document} -> document
      {:error, reason} -> raise "Failed to parse room markdown: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts protected sections from the body.
  Returns a map of section_name => content.
  """
  @spec extract_protected_sections(String.t()) :: %{String.t() => String.t()}
  def extract_protected_sections(body) when is_binary(body) do
    # Find all protected sections
    Regex.scan(@protected_start_pattern, body)
    |> Enum.reduce(%{}, fn [_full_match, section_name], acc ->
      case extract_section_content(body, section_name) do
        {:ok, content} -> Map.put(acc, section_name, content)
        :error -> acc
      end
    end)
  end

  def extract_protected_sections(_), do: %{}

  @doc """
  Validates that a parsed document has all required fields.
  """
  @spec validate(RoomDocument.t()) :: :ok | {:error, [atom()]}
  def validate(%RoomDocument{} = doc) do
    errors =
      []
      |> validate_required(doc, :id)
      |> validate_required(doc, :name)
      |> validate_required(doc, :owner_id)
      |> validate_required(doc, :join_code)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  # Private functions

  defp split_frontmatter(content) do
    content = String.trim(content)

    if String.starts_with?(content, @frontmatter_delimiter) do
      # Remove the leading delimiter
      rest = String.slice(content, String.length(@frontmatter_delimiter), String.length(content))
      rest = String.trim_leading(rest, "\n")

      # Find the closing delimiter
      case String.split(rest, "\n#{@frontmatter_delimiter}", parts: 2) do
        [yaml_content, body] ->
          {String.trim(yaml_content), String.trim(body)}

        [_only_yaml] ->
          # No closing delimiter found, treat entire rest as YAML
          {String.trim(rest), ""}
      end
    else
      # No frontmatter, treat as body only
      {"", content}
    end
  end

  defp parse_yaml(""), do: {:ok, %{}}

  defp parse_yaml(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, data} when is_map(data) ->
        {:ok, data}

      {:ok, nil} ->
        {:ok, %{}}

      {:ok, _other} ->
        {:error, :invalid_yaml_structure}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_document(frontmatter, body) do
    # Extract features from frontmatter
    features = Map.get(frontmatter, "features") || %{}

    # Extract admins from frontmatter
    admins = Map.get(frontmatter, "admins") || %{}

    attrs = %{
      id: Map.get(frontmatter, "id"),
      name: Map.get(frontmatter, "name"),
      description: Map.get(frontmatter, "description"),
      owner_id: Map.get(frontmatter, "owner_id"),
      join_code: Map.get(frontmatter, "join_code"),
      version: Map.get(frontmatter, "version") || 1,
      created_at: Map.get(frontmatter, "created_at"),
      updated_at: Map.get(frontmatter, "updated_at"),
      features: %{
        is_public: Map.get(features, "is_public", true),
        calls_enabled: Map.get(features, "calls_enabled", true),
        media_playback_enabled: Map.get(features, "media_playback_enabled", true),
        object_3d_enabled: Map.get(features, "object_3d_enabled", false)
      },
      admins: %{
        signature: Map.get(admins, "signature"),
        updated_by: Map.get(admins, "updated_by"),
        members: parse_members(Map.get(admins, "members") || [])
      },
      configuration: Map.get(frontmatter, "configuration") || %{},
      body: body
    }

    RoomDocument.new(attrs)
  end

  defp parse_members(members) when is_list(members) do
    Enum.map(members, fn member ->
      %{
        id: Map.get(member, "id"),
        role: parse_role(Map.get(member, "role"))
      }
    end)
  end

  defp parse_members(_), do: []

  defp parse_role("owner"), do: :owner
  defp parse_role("admin"), do: :admin
  defp parse_role("member"), do: :member
  defp parse_role(:owner), do: :owner
  defp parse_role(:admin), do: :admin
  defp parse_role(:member), do: :member
  defp parse_role(_), do: :member

  defp extract_section_content(body, section_name) do
    start_pattern = ~r/<!--\s*PROTECTED:#{Regex.escape(section_name)}\s*-->/
    end_pattern = ~r/<!--\s*\/PROTECTED:#{Regex.escape(section_name)}\s*-->/

    case Regex.run(start_pattern, body, return: :index) do
      [{start_pos, start_len}] ->
        content_start = start_pos + start_len

        case Regex.run(end_pattern, body, return: :index) do
          [{end_pos, _end_len}] when end_pos > content_start ->
            content = String.slice(body, content_start, end_pos - content_start)
            {:ok, String.trim(content)}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp validate_required(errors, doc, field) do
    value = Map.get(doc, field)

    if is_nil(value) || (is_binary(value) && String.trim(value) == "") do
      [{:missing_required_field, field} | errors]
    else
      errors
    end
  end
end
