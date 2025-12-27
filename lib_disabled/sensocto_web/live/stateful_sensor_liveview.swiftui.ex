defmodule SensoctoWeb.StatefulSensorLiveview.SwiftUI do
  use SensoctoNative, [:render_component, format: :swiftui]

  def render(assigns, _interface) do
    ~LVN"""
    <Text>Stateful {inspect(assigns)}</Text>
    """
  end
end
