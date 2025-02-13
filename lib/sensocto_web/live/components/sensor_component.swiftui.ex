defmodule SensoctoWeb.Live.Components.SensorComponent.SwiftUI do
  use SensoctoNative, [:render_component, format: :swiftui]

  def render(assigns, _interface) do
    ~LVN"""
    <Text>SensorComponent.SwiftUI {inspect(assigns)}</Text>
    """
  end
end
