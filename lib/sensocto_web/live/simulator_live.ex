defmodule SensoctoWeb.SimulatorLive do
  @moduledoc """
  LiveView admin page for simulator control.
  Allows starting, stopping, and monitoring the integrated simulator.
  """

  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Simulator.Manager
  alias Sensocto.Simulator.Supervisor, as: SimSupervisor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh_status)
    end

    {:ok, assign_status(socket)}
  end

  @impl true
  def handle_info(:refresh_status, socket) do
    {:noreply, assign_status(socket)}
  end

  @impl true
  def handle_event("reload_config", _params, socket) do
    case Manager.reload_config() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Configuration reloaded successfully")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reload config: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_connector", %{"id" => connector_id}, socket) do
    case Manager.start_connector(connector_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Connector #{connector_id} started")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start connector: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_connector", %{"id" => connector_id}, socket) do
    case Manager.stop_connector(connector_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Connector #{connector_id} stopped")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop connector: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_all", _params, socket) do
    case Manager.start_all() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "All connectors started")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start all: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_all", _params, socket) do
    case Manager.stop_all() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "All connectors stopped")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop all: #{inspect(reason)}")}
    end
  end

  defp assign_status(socket) do
    enabled = SimSupervisor.enabled?()

    {connectors, config} =
      if enabled do
        {Manager.get_connectors(), Manager.get_config()}
      else
        {%{}, %{}}
      end

    socket
    |> assign(:enabled, enabled)
    |> assign(:connectors, connectors)
    |> assign(:config, config)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-6">
      <div class="max-w-6xl mx-auto">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold text-orange-400">Simulator Control</h1>
          <div class="flex items-center gap-2">
            <span class={[
              "px-3 py-1 rounded-full text-sm font-medium",
              @enabled && "bg-green-600",
              !@enabled && "bg-red-600"
            ]}>
              {if @enabled, do: "Enabled", else: "Disabled"}
            </span>
          </div>
        </div>

        <%= if @enabled do %>
          <div class="mb-6 flex gap-4">
            <button
              phx-click="reload_config"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors"
            >
              Reload Config
            </button>
            <button
              phx-click="start_all"
              class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg transition-colors"
            >
              Start All
            </button>
            <button
              phx-click="stop_all"
              class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors"
            >
              Stop All
            </button>
          </div>

          <div class="bg-gray-800 rounded-lg p-6 mb-6">
            <h2 class="text-xl font-semibold mb-4 text-orange-300">Connectors</h2>

            <%= if map_size(@connectors) == 0 do %>
              <p class="text-gray-400">No connectors configured. Check config/simulators.yaml</p>
            <% else %>
              <div class="grid gap-4">
                <%= for {connector_id, connector} <- @connectors do %>
                  <div class="bg-gray-700 rounded-lg p-4">
                    <div class="flex items-center justify-between mb-3">
                      <div>
                        <h3 class="text-lg font-medium text-white">{connector.name || connector_id}</h3>
                        <p class="text-sm text-gray-400">ID: {connector_id}</p>
                      </div>
                      <div class="flex items-center gap-3">
                        <span class={[
                          "px-2 py-1 rounded text-xs font-medium",
                          connector.status == :running && "bg-green-600",
                          connector.status == :stopped && "bg-gray-600",
                          connector.status not in [:running, :stopped] && "bg-yellow-600"
                        ]}>
                          {connector.status || :unknown}
                        </span>
                        <%= if connector.status == :running do %>
                          <button
                            phx-click="stop_connector"
                            phx-value-id={connector_id}
                            class="px-3 py-1 bg-red-600 hover:bg-red-700 rounded text-sm transition-colors"
                          >
                            Stop
                          </button>
                        <% else %>
                          <button
                            phx-click="start_connector"
                            phx-value-id={connector_id}
                            class="px-3 py-1 bg-green-600 hover:bg-green-700 rounded text-sm transition-colors"
                          >
                            Start
                          </button>
                        <% end %>
                      </div>
                    </div>

                    <%= if Map.has_key?(connector, :sensors) and map_size(connector.sensors) > 0 do %>
                      <div class="mt-3 border-t border-gray-600 pt-3">
                        <h4 class="text-sm font-medium text-gray-300 mb-2">Sensors ({map_size(connector.sensors)})</h4>
                        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
                          <%= for {sensor_id, sensor} <- connector.sensors do %>
                            <div class="bg-gray-800 rounded px-3 py-2">
                              <p class="text-sm font-medium text-white truncate">{sensor.name || sensor_id}</p>
                              <p class="text-xs text-gray-400">{sensor_id}</p>
                              <%= if Map.has_key?(sensor, :attributes) do %>
                                <p class="text-xs text-gray-500 mt-1">
                                  {map_size(sensor.attributes)} attributes
                                </p>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="bg-gray-800 rounded-lg p-6">
            <h2 class="text-xl font-semibold mb-4 text-orange-300">Configuration</h2>
            <div class="bg-gray-900 rounded p-4 overflow-x-auto">
              <pre class="text-sm text-gray-300"><code>{inspect(@config, pretty: true, limit: :infinity)}</code></pre>
            </div>
            <p class="text-sm text-gray-500 mt-2">
              Config file: config/simulators.yaml
            </p>
          </div>
        <% else %>
          <div class="bg-gray-800 rounded-lg p-6 text-center">
            <p class="text-gray-400 mb-4">
              The simulator is disabled. Enable it in your config:
            </p>
            <div class="bg-gray-900 rounded p-4 text-left inline-block">
              <pre class="text-sm text-gray-300"><code># config/dev.exs
config :sensocto, :simulator,
  enabled: true,
  config_path: "config/simulators.yaml"</code></pre>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
