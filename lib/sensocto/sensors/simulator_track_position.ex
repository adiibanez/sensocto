defmodule Sensocto.Sensors.SimulatorTrackPosition do
  @moduledoc """
  Ash resource for persisting GPS track playback positions.
  Allows track playback to resume from where it left off after restart.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "simulator_track_positions"
    repo Sensocto.Repo

    references do
      reference :connector, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :sensor_id,
        :track_name,
        :track_mode,
        :current_time_s,
        :playback_speed,
        :loop,
        :last_position,
        :connector_id
      ]
    end

    create :sync_create do
      accept [
        :sensor_id,
        :track_name,
        :track_mode,
        :current_time_s,
        :playback_speed,
        :loop,
        :last_position,
        :connector_id
      ]

      argument :id, :uuid, allow_nil?: true

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :id) do
          nil -> changeset
          id -> Ash.Changeset.force_change_attribute(changeset, :id, id)
        end
      end
    end

    update :sync_position do
      accept [:current_time_s, :playback_speed, :loop, :last_position]
    end

    read :by_connector do
      argument :connector_id, :uuid, allow_nil?: false
      filter expr(connector_id == ^arg(:connector_id))
    end

    read :by_sensor do
      argument :sensor_id, :string, allow_nil?: false
      get? true
      filter expr(sensor_id == ^arg(:sensor_id))
    end

    read :all
  end

  attributes do
    uuid_primary_key :id

    attribute :sensor_id, :string do
      allow_nil? false
      description "Sensor ID within the connector"
    end

    attribute :track_name, :string do
      allow_nil? true
      description "Name of the GPS track"
    end

    attribute :track_mode, :atom do
      constraints one_of: [:walk, :cycle, :car, :train, :bird, :drone, :boat, :stationary]
      allow_nil? true
    end

    attribute :current_time_s, :float do
      default 0.0
      description "Current playback position in seconds"
    end

    attribute :playback_speed, :float do
      default 1.0
    end

    attribute :loop, :boolean do
      default true
    end

    attribute :last_position, :map do
      default %{}
      description "Last known position {lat, lng, alt, speed, heading}"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :connector, Sensocto.Sensors.SimulatorConnector do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_sensor_track, [:connector_id, :sensor_id]
  end
end
