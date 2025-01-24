defmodule Sensocto.Sensors do
  use Ash.Domain, otp_app: :sensocto, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sensocto.Sensors.Sensor
    resource Sensocto.Sensors.SensorAttribute
    resource Sensocto.Sensors.SensorType
    resource Sensocto.Sensors.Connector
    resource Sensocto.Sensors.ConnectorSensorType
    resource Sensocto.Sensors.RoomSensorType
    resource Sensocto.Sensors.Room
    resource Sensocto.Sensors.SensorConnection
    resource Sensocto.Sensors.SensorSensorConnection
  end
end
