defmodule Sensocto.Sensors.ConnectorSensorType do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Connector
  alias Sensocto.Sensors.SensorType

  attributes do
    attribute(:id, :uuid, primary_key?: true, allow_nil?: false)
    attribute(:connector_id, :uuid, allow_nil?: false)
    attribute(:sensor_type_id, :uuid, allow_nil?: false)
  end

  relationships do
    # , primary_key?: true, allow_nil?: false
    belongs_to(:connector, Connector)
    # , primary_key?: true, allow_nil?: false
    belongs_to(:sensor_type, SensorType)
  end

  identities do
    identity(:unique, keys: [:id])
  end
end
