defmodule SensoctoWeb.Live.Components.SensorComponent do
  # use SensoctoWeb, :live_view
  use Phoenix.LiveComponent

  alias SensoctoWeb.Live.Components.AttributeComponent

  def mount(_params, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="sensor flex flex-col rounded-lg shadow-md p-2 sm:p-2 md:p-2 lg:p-2 xl:p-2 cursor-pointer bg-dark-gray text-light-gray">
      <div class="w-full h-full">
        SensorComponent pid: {inspect(self())}
        <p>
          Sensor ID:{@sensor_id}
        </p>

        <div>
          <.live_component
            :for={{attribute_id, attribute} <- @attributes}
            id={"attribute_#{@sensor_id}_#{attribute_id}"}
            module={AttributeComponent}
            attribute={
              Map.put(List.last(attribute), :attribute_id, attribute_id)
              |> Map.put(:attribute_type, @sensor_type)
            }
            sensor_id={@sensor_id}
            attribute_type={@sensor_type}
            attribute_id={attribute_id}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end
end
