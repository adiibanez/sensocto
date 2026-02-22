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
     |> assign(:current_path, "/simulator")
     |> assign(:selected_scenario, nil)
     |> assign(:selected_room_id, nil)
     |> assign(:show_start_modal, nil)
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
    if Map.has_key?(socket.assigns.running_scenarios, scenario_name) do
      # Running scenario → stop it directly
      handle_event("stop_scenario", %{"scenario" => scenario_name}, socket)
    else
      # Not running → open start modal
      {:noreply,
       socket
       |> assign(:selected_scenario, scenario_name)
       |> assign(:show_start_modal, scenario_name)}
    end
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("close_start_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_start_modal, nil)
     |> assign(:selected_scenario, nil)}
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
           |> assign(:show_start_modal, nil)
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
  catch
    :exit, {:timeout, _} ->
      {:noreply,
       socket
       |> put_flash(:warning, "Stopping scenario is taking longer than expected, please wait...")
       |> assign_status()}
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
  catch
    :exit, {:timeout, _} ->
      {:noreply,
       socket
       |> put_flash(:warning, "Scenario switch is taking longer than expected, please wait...")
       |> assign_status()}
  end

  defp assign_status(socket) do
    {connectors, config, scenarios, running_scenarios, startup_phase} =
      if SimSupervisor.enabled?() do
        try do
          phase = Manager.startup_phase()

          {
            Manager.get_connectors(),
            Manager.get_config(),
            Manager.list_scenarios(),
            Manager.get_running_scenarios(),
            phase
          }
        catch
          :exit, _ ->
            Logger.warning("Simulator Manager busy during startup, will retry on next refresh")
            {%{}, %{}, [], %{}, :loading_config}
        end
      else
        {%{}, %{}, [], %{}, :ready}
      end

    # Count running connectors
    running_count = Enum.count(connectors, fn {_id, c} -> c.status == :running end)

    socket
    |> assign(:connectors, connectors)
    |> assign(:config, config)
    |> assign(:running_count, running_count)
    |> assign(:scenarios, scenarios)
    |> assign(:running_scenarios, running_scenarios)
    |> assign(:startup_phase, startup_phase)
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
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-orange-400">Simulator Control</h1>
        </div>

        <%= if @startup_phase != :ready do %>
          <div class="bg-amber-900/30 border border-amber-700/50 rounded-lg p-4 mb-6 flex items-center gap-3">
            <svg class="w-5 h-5 text-amber-400 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
              >
              </path>
            </svg>
            <span class="text-amber-300 text-sm font-medium">
              {case @startup_phase do
                :loading_config -> "Loading simulator configuration..."
                :starting_connectors -> "Starting connectors..."
                _ -> "Initializing..."
              end}
            </span>
          </div>
        <% end %>

        <%= if length(@scenarios) > 0 do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <%= for scenario <- @scenarios do %>
              <% is_running = Map.has_key?(@running_scenarios, scenario.name) %>
              <% running_info = Map.get(@running_scenarios, scenario.name) %>
              <div
                class={[
                  "rounded-lg p-4 border-2 cursor-pointer transition-all",
                  is_running && "border-green-500 bg-gray-700 hover:border-red-400",
                  !is_running && "border-gray-600 bg-gray-700/50 hover:border-orange-400"
                ]}
                phx-click="select_scenario"
                phx-value-scenario={scenario.name}
              >
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-lg font-medium text-white capitalize">
                    {String.replace(scenario.name, "_", " ")}
                  </h3>
                  <%= if is_running do %>
                    <span class="px-2 py-1 bg-green-600 rounded text-xs font-medium">
                      Running
                    </span>
                  <% end %>
                </div>
                <p class="text-sm text-gray-300 mb-2">{scenario.description}</p>
                <div class="flex gap-4 text-xs text-gray-400">
                  <span>{scenario.sensor_count} sensors</span>
                  <span>{scenario.attribute_count} attributes</span>
                </div>
                <%= if is_running && running_info do %>
                  <div class="mt-3 pt-3 border-t border-gray-600 flex items-center justify-between">
                    <div class="text-xs text-gray-400">
                      <span>{length(running_info.connector_ids)} connectors</span>
                      <%= if running_info.room_name do %>
                        <span class="ml-2 text-blue-400">Room: {running_info.room_name}</span>
                      <% end %>
                    </div>
                    <button
                      phx-click="stop_scenario"
                      phx-value-scenario={scenario.name}
                      class="px-3 py-1 bg-red-600 hover:bg-red-700 rounded text-xs font-medium transition-colors"
                    >
                      Stop
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-gray-400">No scenarios found in config/simulator_scenarios/</p>
        <% end %>
      </div>
    </div>

    <%= if @show_start_modal do %>
      <% modal_scenario = Enum.find(@scenarios, &(&1.name == @show_start_modal)) %>
      <%= if modal_scenario do %>
        <div
          class="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4"
          phx-click="close_start_modal"
          phx-window-keydown="close_start_modal"
          phx-key="Escape"
        >
          <div
            class="bg-gray-800 border border-gray-600 rounded-xl p-6 max-w-md w-full shadow-2xl"
            phx-click="noop"
          >
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-xl font-semibold text-white capitalize">
                {String.replace(modal_scenario.name, "_", " ")}
              </h3>
              <button
                phx-click="close_start_modal"
                class="text-gray-400 hover:text-white transition-colors"
              >
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            <p class="text-sm text-gray-300 mb-4">{modal_scenario.description}</p>

            <div class="flex gap-4 text-sm text-gray-400 mb-6">
              <span>{modal_scenario.sensor_count} sensors</span>
              <span>{modal_scenario.attribute_count} attributes</span>
            </div>

            <form phx-submit="start_scenario" phx-change="select_room">
              <div class="mb-4">
                <label class="block text-sm text-gray-400 mb-2">Assign to Room (optional)</label>
                <select
                  name="room_id"
                  class="w-full bg-gray-700 border border-gray-600 text-white rounded-lg px-3 py-2 text-sm focus:ring-orange-500 focus:border-orange-500"
                >
                  <option value="">No Room</option>
                  <%= for room <- @rooms do %>
                    <option value={room.id} selected={@selected_room_id == room.id}>
                      {room.name}
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="flex gap-3">
                <button
                  type="submit"
                  class="flex-1 px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg font-medium transition-colors"
                >
                  Start Scenario
                </button>
                <button
                  type="button"
                  phx-click="close_start_modal"
                  class="px-4 py-2 bg-gray-600 hover:bg-gray-500 rounded-lg font-medium transition-colors"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end
end
