defmodule SensoctoWeb.SimulatorLive do
  @moduledoc """
  LiveView admin page for simulator control.
  Allows starting, stopping, and monitoring the integrated simulator.
  """

  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Simulator.Manager
  alias Sensocto.Simulator.Supervisor, as: SimSupervisor

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh_status)
    end

    {:ok,
     socket
     |> assign(:selected_scenario, nil)
     |> assign(:selected_room_id, nil)
     |> assign_status()
     |> assign_rooms()}
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

  @impl true
  def handle_event("select_scenario", %{"scenario" => scenario_name}, socket) do
    # Just select the scenario without starting it
    {:noreply, assign(socket, :selected_scenario, scenario_name)}
  end

  @impl true
  def handle_event("select_room", %{"room_id" => room_id}, socket) do
    room_id = if room_id == "", do: nil, else: room_id
    {:noreply, assign(socket, :selected_room_id, room_id)}
  end

  @impl true
  def handle_event("start_scenario", _params, socket) do
    scenario_name = socket.assigns[:selected_scenario]
    room_id = socket.assigns[:selected_room_id]

    if scenario_name do
      case Manager.start_scenario(scenario_name, room_id: room_id) do
        :ok ->
          room_info = if room_id, do: " (room: #{room_id})", else: ""

          {:noreply,
           socket
           |> put_flash(:info, "Started scenario: #{scenario_name}#{room_info}")
           |> assign(:selected_scenario, nil)
           |> assign_status()}

        {:error, :already_running} ->
          {:noreply, put_flash(socket, :error, "Scenario #{scenario_name} is already running")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start scenario: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No scenario selected")}
    end
  end

  @impl true
  def handle_event("stop_scenario", %{"scenario" => scenario_name}, socket) do
    case Manager.stop_scenario(scenario_name) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Stopped scenario: #{scenario_name}")
         |> assign_status()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop scenario: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("load_scenario", _params, socket) do
    scenario_name = socket.assigns[:selected_scenario]
    room_id = socket.assigns[:selected_room_id]

    if scenario_name do
      case Manager.switch_scenario(scenario_name, room_id: room_id) do
        :ok ->
          room_info = if room_id, do: " (room: #{room_id})", else: ""

          {:noreply,
           socket
           |> put_flash(:info, "Loaded scenario: #{scenario_name}#{room_info}")
           |> assign_status()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to load scenario: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No scenario selected")}
    end
  end

  defp assign_status(socket) do
    {connectors, config, scenarios, running_scenarios} =
      if SimSupervisor.enabled?() do
        {
          Manager.get_connectors(),
          Manager.get_config(),
          Manager.list_scenarios(),
          Manager.get_running_scenarios()
        }
      else
        {%{}, %{}, [], %{}}
      end

    # Count running connectors
    running_count = Enum.count(connectors, fn {_id, c} -> c.status == :running end)

    socket
    |> assign(:connectors, connectors)
    |> assign(:config, config)
    |> assign(:running_count, running_count)
    |> assign(:scenarios, scenarios)
    |> assign(:running_scenarios, running_scenarios)
  end

  defp assign_rooms(socket) do
    rooms = Sensocto.RoomStore.list_all_rooms()
    assign(socket, :rooms, rooms)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-6">
      <div class="max-w-6xl mx-auto">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold text-orange-400">Simulator Control</h1>
          <div class="flex items-center gap-3">
            <span class={[
              "px-3 py-1 rounded-full text-sm font-medium",
              @running_count > 0 && "bg-green-600",
              @running_count == 0 && "bg-gray-600"
            ]}>
              {if @running_count > 0, do: "#{@running_count} Running", else: "Stopped"}
            </span>
          </div>
        </div>
        
    <!-- Running Scenarios -->
        <%= if map_size(@running_scenarios) > 0 do %>
          <div class="bg-gray-800 rounded-lg p-6 mb-6">
            <h2 class="text-xl font-semibold text-orange-300 mb-4">Running Scenarios</h2>
            <div class="grid gap-3">
              <%= for {scenario_name, info} <- @running_scenarios do %>
                <div class="bg-gray-700 rounded-lg p-4 flex items-center justify-between">
                  <div>
                    <h3 class="text-lg font-medium text-white capitalize">
                      {String.replace(scenario_name, "_", " ")}
                    </h3>
                    <div class="flex items-center gap-4 mt-1 text-sm text-gray-400">
                      <span>{length(info.connector_ids)} connectors</span>
                      <%= if info.room_name do %>
                        <span class="flex items-center gap-1">
                          <span class="text-blue-400">Room:</span>
                          <span class="text-blue-300">{info.room_name}</span>
                        </span>
                      <% else %>
                        <span class="text-gray-500">No room assigned</span>
                      <% end %>
                    </div>
                  </div>
                  <button
                    phx-click="stop_scenario"
                    phx-value-scenario={scenario_name}
                    class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg text-sm font-medium transition-colors"
                  >
                    Stop
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Scenario Selection -->
        <div class="bg-gray-800 rounded-lg p-6 mb-6">
          <div class="flex flex-col gap-4 mb-4">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h2 class="text-xl font-semibold text-orange-300">Available Scenarios</h2>
                <p class="text-sm text-gray-400 mt-1">
                  Select a scenario and optionally assign sensors to a room. You can run multiple scenarios simultaneously.
                </p>
              </div>
              <form
                phx-change="select_room"
                phx-submit="start_scenario"
                class="flex flex-wrap items-center gap-3"
              >
                <div class="flex items-center gap-2">
                  <label class="text-sm text-gray-400">Room:</label>
                  <select
                    name="room_id"
                    class="bg-gray-700 border border-gray-600 text-white rounded-lg px-3 py-2 text-sm focus:ring-orange-500 focus:border-orange-500"
                  >
                    <option value="">No Room</option>
                    <%= for room <- @rooms do %>
                      <option value={room.id} selected={@selected_room_id == room.id}>
                        {room.name}
                      </option>
                    <% end %>
                  </select>
                </div>
                <button
                  type="submit"
                  disabled={is_nil(@selected_scenario)}
                  class={[
                    "px-4 py-2 rounded-lg transition-colors font-medium whitespace-nowrap",
                    @selected_scenario && "bg-green-600 hover:bg-green-700 cursor-pointer",
                    is_nil(@selected_scenario) && "bg-gray-600 cursor-not-allowed opacity-50"
                  ]}
                >
                  Start Scenario
                </button>
              </form>
            </div>
          </div>

          <%= if length(@scenarios) > 0 do %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <%= for scenario <- @scenarios do %>
                <% is_running = Map.has_key?(@running_scenarios, scenario.name) %>
                <% running_info = Map.get(@running_scenarios, scenario.name) %>
                <div
                  class={[
                    "rounded-lg p-4 border-2 cursor-pointer transition-all hover:border-orange-400",
                    is_running && "border-green-500 bg-gray-700",
                    @selected_scenario == scenario.name && !is_running &&
                      "border-orange-500 bg-gray-700",
                    @selected_scenario != scenario.name && !is_running &&
                      "border-gray-600 bg-gray-700/50"
                  ]}
                  phx-click="select_scenario"
                  phx-value-scenario={scenario.name}
                >
                  <div class="flex items-center justify-between mb-2">
                    <h3 class="text-lg font-medium text-white capitalize">
                      {String.replace(scenario.name, "_", " ")}
                    </h3>
                    <div class="flex gap-1">
                      <%= if @selected_scenario == scenario.name && !is_running do %>
                        <span class="px-2 py-1 bg-orange rounded text-xs font-medium">Selected</span>
                      <% end %>
                      <%= if is_running do %>
                        <span class="px-2 py-1 bg-green-600 rounded text-xs font-medium">
                          Running
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <p class="text-sm text-gray-300 mb-2">{scenario.description}</p>
                  <div class="flex gap-4 text-xs text-gray-400">
                    <span>{scenario.sensor_count} sensors</span>
                    <span>{scenario.attribute_count} attributes</span>
                  </div>
                  <%= if is_running && running_info && running_info.room_name do %>
                    <div class="mt-2 text-xs text-blue-400">
                      Room: {running_info.room_name}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-400">No scenarios found in config/simulator_scenarios/</p>
          <% end %>
        </div>

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
            <p class="text-gray-400">No connectors configured. Start a scenario above.</p>
          <% else %>
            <div class="grid gap-4">
              <%= for {connector_id, connector} <- @connectors do %>
                <div class="bg-gray-700 rounded-lg p-4">
                  <div class="flex items-center justify-between mb-3">
                    <div>
                      <h3 class="text-lg font-medium text-white">{connector.name || connector_id}</h3>
                      <div class="flex items-center gap-3 mt-1 text-sm">
                        <span class="text-gray-400">ID: {connector_id}</span>
                        <%= if connector.scenario do %>
                          <span class="text-purple-400">Scenario: {connector.scenario}</span>
                        <% end %>
                        <%= if connector.room_name do %>
                          <span class="text-blue-400">Room: {connector.room_name}</span>
                        <% end %>
                      </div>
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
                      <h4 class="text-sm font-medium text-gray-300 mb-2">
                        Sensors ({map_size(connector.sensors)})
                      </h4>
                      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
                        <%= for {sensor_id, sensor} <- connector.sensors do %>
                          <div class="bg-gray-800 rounded px-3 py-2">
                            <p class="text-sm font-medium text-white truncate">
                              {sensor.name || sensor_id}
                            </p>
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
      </div>
    </div>
    """
  end
end
