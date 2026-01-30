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
    <div id={@id} phx-hook="SystemMetricsRefresh" phx-target={@myself}>
      <.link
        navigate={~p"/system-status"}
        class="flex items-center hover:bg-gray-700/50 rounded-lg px-2 py-1 transition-colors"
        title={"System: #{@metrics.load_level} | CPU: #{format_percent(@metrics.scheduler_utilization)} | Memory: #{format_percent(@metrics.memory_pressure)} | Multiplier: #{Float.round(@metrics.load_multiplier, 1)}x"}
      >
        <div
          id="system-pulse-heart"
          phx-hook="PulsatingLogo"
          class={["system-pulse-heart", "load-#{@metrics.load_level}"]}
        >
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor">
            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
          </svg>
        </div>
      </.link>
    </div>
    """
  end

  defp get_metrics do
    try do
      Sensocto.SystemLoadMonitor.get_metrics()
    catch
      :exit, _ ->
        # Handle noproc, timeout, or any other exit reason
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
end
