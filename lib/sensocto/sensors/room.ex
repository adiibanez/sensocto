defmodule Sensocto.Sensors.Room do
  @moduledoc """
  Room resource for grouping sensors and users.
  Supports both persisted (database) and temporary (in-memory) rooms.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  alias Sensocto.Accounts.User
  alias Sensocto.Sensors.RoomMembership
  alias Sensocto.Sensors.SensorConnection

  postgres do
    table "rooms"
    repo Sensocto.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 100
    end

    attribute :description, :string do
      allow_nil? true
      constraints max_length: 500
    end

    attribute :configuration, :map do
      allow_nil? true
      default %{}
    end

    attribute :is_public, :boolean do
      default true
      allow_nil? false
    end

    attribute :is_persisted, :boolean do
      default true
      allow_nil? false
    end

    attribute :join_code, :string do
      allow_nil? true
      constraints min_length: 6, max_length: 12
    end

    attribute :owner_id, :uuid do
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, User do
      source_attribute :owner_id
      destination_attribute :id
      allow_nil? false
      define_attribute? false
    end

    has_many :room_memberships, RoomMembership

    many_to_many :members, User do
      through RoomMembership
      source_attribute_on_join_resource :room_id
      destination_attribute_on_join_resource :user_id
    end

    has_many :sensor_connections, SensorConnection
  end

  identities do
    identity :unique_join_code, [:join_code]
  end

  calculations do
    calculate :member_count, :integer, expr(count(room_memberships))
    calculate :sensor_count, :integer, expr(count(sensor_connections))
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :configuration, :is_public, :is_persisted]
      argument :owner_id, :uuid, allow_nil?: false

      change set_attribute(:owner_id, arg(:owner_id))

      change fn changeset, _context ->
        join_code = generate_join_code()
        Ash.Changeset.change_attribute(changeset, :join_code, join_code)
      end
    end

    update :update do
      accept [:name, :description, :configuration, :is_public]
    end

    update :regenerate_join_code do
      require_atomic? false

      change fn changeset, _context ->
        join_code = generate_join_code()
        Ash.Changeset.change_attribute(changeset, :join_code, join_code)
      end
    end

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end

    read :by_join_code do
      argument :code, :string, allow_nil?: false
      get? true
      filter expr(join_code == ^arg(:code))
    end

    read :public_rooms do
      filter expr(is_public == true and is_persisted == true)
    end

    read :user_owned_rooms do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
    end

    read :user_member_rooms do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(exists(room_memberships, user_id == ^arg(:user_id)))
    end
  end

  @doc """
  Generates a random alphanumeric join code.
  """
  def generate_join_code(length \\ 8) do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
  end
end
