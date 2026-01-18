defmodule Sensocto.Sensors do
  use Ash.Domain, otp_app: :sensocto, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sensocto.Sensors.Sensor
    resource Sensocto.Sensors.SensorAttribute
    resource Sensocto.Sensors.SensorAttributeData
    resource Sensocto.Sensors.SensorType
    resource Sensocto.Sensors.Connector
    resource Sensocto.Sensors.ConnectorSensorType
    resource Sensocto.Sensors.RoomSensorType
    resource Sensocto.Sensors.Room
    resource Sensocto.Sensors.RoomMembership
    resource Sensocto.Sensors.SensorConnection
    resource Sensocto.Sensors.SensorSensorConnection

    resource Sensocto.Sensors.SensorManager do
      # define :validate_sensor, args: [:sensor_id, :connector_id, :connector_name, :sensor_name, :sensor_name], action: :validate_sensor
    end

    # Simulator persistence resources
    resource Sensocto.Sensors.SimulatorScenario
    resource Sensocto.Sensors.SimulatorConnector
    resource Sensocto.Sensors.SimulatorTrackPosition
    resource Sensocto.Sensors.SimulatorBatteryState
  end
end
