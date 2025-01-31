defmodule SensoctoWeb.Telemetry.Metrics do
  def emit(value) do
    # :telemetry.execute([:metrics, :emit], %{value: value})
    :telemetry.execute([:sensocto, :sensors, :mps], %{value: value})
    # sensocto.sensors.messages.measurement
  end
end
