defmodule SensoctoWeb.Live.Components.SensorComponent do
  use SensoctoWeb, :live_component

  alias Sensocto.SimpleSensor
  alias SensoctoWeb.Live.Components.AttributeComponent
  import SensoctoWeb.Live.BaseComponents
  require Logger

  @impl true
  def update(assigns, socket) do
    sensor_state = SimpleSensor.get_state(assigns.sensor.metadata.sensor_id)

    {:ok,
     socket
     # |> assign(:parent_pid, assigns.parent_pid)
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_state.metadata.sensor_id)
     |> assign(:sensor_name, sensor_state.metadata.sensor_name)
     |> assign(:sensor_type, sensor_state.metadata.sensor_type)
     |> assign(:highlighted, false)
     |> assign(:attributes, sensor_state.attributes)
     |> assign(
       :attributes_loaded,
       is_map(sensor_state.attributes) and Enum.count(sensor_state.attributes) > 0
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="sensor flex flex-col rounded-lg shadow-md p-2 sm:p-2 md:p-2 lg:p-2 xl:p-2 cursor-pointer bg-dark-gray text-light-gray h-48"
      style="border:0 solid green"
    >
      <div class="w-full h-full">
        <p class="hidden">
          SensorComponent pid: {inspect(self())} attributes: {inspect(@attributes_loaded)}
        </p>

        <.render_sensor_header
          sensor_id={@sensor_id}
          sensor_name={@sensor_name}
          highlighted={@highlighted}
        >
        </.render_sensor_header>

        <div :if={not @attributes_loaded}>
          {render_loading(8, "#{@sensor_id}", assigns)}
        </div>

        <div>
          Type: {@sensor_type}

          <.live_component
            :for={{attribute_id, attribute} <- @attributes}
            id={"attribute_#{@sensor_id}_#{attribute_id}"}
            attribute_type={@sensor_type}
            module={AttributeComponent}
            attribute={attribute}
            sensor_id={@sensor_id}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end
end
