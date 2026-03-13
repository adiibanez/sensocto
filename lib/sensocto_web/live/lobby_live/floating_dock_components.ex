defmodule SensoctoWeb.LobbyLive.FloatingDockComponents do
  @moduledoc """
  Function components for the floating sensor dock in lobby.
  Renders a horizontal strip of mini sensor badges at the bottom of the viewport.
  """
  use Phoenix.Component

  attr :sensor_id, :string, required: true
  attr :sensor, :map, required: true
  attr :is_expanded, :boolean, default: false

  def mini_sensor_badge(assigns) do
    status = connection_status(assigns.sensor)
    name = assigns.sensor[:sensor_name] || assigns.sensor[:sensor_id] || assigns.sensor_id

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:name, name)

    ~H"""
    <button
      phx-click="float_expand_sensor"
      phx-value-sensor-id={@sensor_id}
      class={[
        "flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs transition-all shrink-0",
        "hover:bg-gray-700/80",
        if(@is_expanded,
          do: "bg-violet-600/30 ring-1 ring-violet-500/50 text-white",
          else: "bg-gray-800/80 text-gray-300"
        )
      ]}
    >
      <span class={[
        "w-1.5 h-1.5 rounded-full shrink-0",
        status_color(@status)
      ]}>
      </span>
      <span class="truncate max-w-[80px]">{@name}</span>
    </button>
    """
  end

  defp connection_status(sensor) do
    cond do
      sensor[:connection_status] -> sensor[:connection_status]
      map_size(sensor[:attributes] || %{}) > 0 -> :streaming
      true -> :disconnected
    end
  end

  defp status_color(:streaming), do: "bg-green-400"
  defp status_color(:connected), do: "bg-green-400"
  defp status_color(:connecting), do: "bg-yellow-400"
  defp status_color(:error), do: "bg-red-400"
  defp status_color(_), do: "bg-gray-500"
end
