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
    <div id={@id} class="flex items-center gap-2 text-xs font-mono" phx-hook="SystemMetricsRefresh" phx-target={@myself}>
      <div class="flex items-center gap-1" title="System Load Level">
        <div
          id="system-pulse-heart"
          phx-hook="PulsatingLogo"
          class={["system-pulse-heart", "load-#{@metrics.load_level}"]}
        >
          <svg viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor">
            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
          </svg>
        </div>
        <span class="text-gray-400 uppercase">{@metrics.load_level}</span>
      </div>

      <div class="text-gray-600">|</div>

      <div class="flex items-center gap-1" title="CPU/Scheduler Utilization">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
        </svg>
        <span class={cpu_color(@metrics.scheduler_utilization)}>
          {format_percent(@metrics.scheduler_utilization)}
        </span>
      </div>

      <div class="flex items-center gap-1" title="Memory Pressure">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
        </svg>
        <span class={mem_color(@metrics.memory_pressure)}>
          {format_percent(@metrics.memory_pressure)}
        </span>
      </div>

      <div class="flex items-center gap-1" title="Batch Window Multiplier (higher = slower updates when load is high)">
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
