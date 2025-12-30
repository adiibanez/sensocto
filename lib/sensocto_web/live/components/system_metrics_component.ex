defmodule SensoctoWeb.SystemMetricsComponent do
  @moduledoc """
  LiveComponent that displays real-time system load metrics in the header.
  Updates via PubSub when system load changes.
  """

  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, metrics: get_metrics())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(metrics: get_metrics())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, metrics: get_metrics())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-1.5 text-[10px] font-mono" phx-hook="SystemMetricsRefresh" phx-target={@myself}>
      <div class="flex items-center gap-0.5" title="System Load Level">
        <span class={[
          "w-1.5 h-1.5 rounded-full",
          load_level_color(@metrics.load_level)
        ]}></span>
        <span class="text-gray-400 uppercase">{@metrics.load_level}</span>
      </div>

      <div class="text-gray-600">|</div>

      <div class="flex items-center gap-0.5" title="CPU/Scheduler Utilization">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-2.5 w-2.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
        </svg>
        <span class={cpu_color(@metrics.scheduler_utilization)}>
          {format_percent(@metrics.scheduler_utilization)}
        </span>
      </div>

      <div class="flex items-center gap-0.5" title="Memory Pressure">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-2.5 w-2.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
        </svg>
        <span class={mem_color(@metrics.memory_pressure)}>
          {format_percent(@metrics.memory_pressure)}
        </span>
      </div>

      <div class="flex items-center gap-0.5" title="Batch Window Multiplier (higher = slower updates when load is high)">
        <span class="text-gray-500">x</span>
        <span class={multiplier_color(@metrics.load_multiplier)}>
          {Float.round(@metrics.load_multiplier, 1)}
        </span>
      </div>
    </div>
    """
  end

  defp get_metrics do
    try do
      Sensocto.SystemLoadMonitor.get_metrics()
    catch
      :exit, {:noproc, _} ->
        %{
          load_level: :unknown,
          scheduler_utilization: 0.0,
          memory_pressure: 0.0,
          message_queue_pressure: 0.0,
          load_multiplier: 1.0
        }
    end
  end

  defp format_percent(value) when is_float(value) do
    "#{Float.round(value * 100, 1)}%"
  end
  defp format_percent(_), do: "-%"

  defp load_level_color(:normal), do: "bg-green-500"
  defp load_level_color(:elevated), do: "bg-yellow-500"
  defp load_level_color(:high), do: "bg-orange-500"
  defp load_level_color(:critical), do: "bg-red-500"
  defp load_level_color(_), do: "bg-gray-500"

  defp cpu_color(value) when value >= 0.85, do: "text-red-400"
  defp cpu_color(value) when value >= 0.7, do: "text-orange-400"
  defp cpu_color(value) when value >= 0.5, do: "text-yellow-400"
  defp cpu_color(_), do: "text-green-400"

  defp mem_color(value) when value >= 0.85, do: "text-red-400"
  defp mem_color(value) when value >= 0.7, do: "text-orange-400"
  defp mem_color(value) when value >= 0.5, do: "text-yellow-400"
  defp mem_color(_), do: "text-green-400"

  defp multiplier_color(value) when value >= 3.0, do: "text-red-400"
  defp multiplier_color(value) when value >= 1.5, do: "text-yellow-400"
  defp multiplier_color(_), do: "text-green-400"
end
