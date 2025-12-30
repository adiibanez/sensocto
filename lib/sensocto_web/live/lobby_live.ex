defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.StatefulSensorLive

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 4
  @grid_cols_2xl_default 5

  # Threshold for switching to summary mode (<=3 sensors = normal, >3 = summary)
  @summary_mode_threshold 3

  @impl true
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)

    # Calculate max attributes across all sensors for view mode decision
    max_attributes = calculate_max_attributes(sensors)

    # Determine view mode: normal for <=3 sensors with few attributes, summary otherwise
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    new_socket =
      socket
      |> assign(
        page_title: "Lobby",
        sensors_online_count: sensors_count,
        sensors_online: %{},
        sensors_offline: %{},
        sensors: sensors,
        global_view_mode: default_view_mode,
        grid_cols_sm: min(@grid_cols_sm_default, max(1, sensors_count)),
        grid_cols_lg: min(@grid_cols_lg_default, max(1, sensors_count)),
        grid_cols_xl: min(@grid_cols_xl_default, max(1, sensors_count)),
        grid_cols_2xl: min(@grid_cols_2xl_default, max(1, sensors_count))
      )

    :telemetry.execute(
      [:sensocto, :live, :lobby, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
  end

  defp calculate_max_attributes(sensors) do
    sensors
    |> Enum.map(fn {_id, sensor} -> map_size(sensor.attributes || %{}) end)
    |> Enum.max(fn -> 0 end)
  end

  defp determine_view_mode(_sensors_count, _max_attributes) do
    # Always start in summary mode - users can expand individual tiles as needed
    :summary
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    Logger.debug(
      "Lobby presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
    )

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)
    sensors_count = Enum.count(sensors)

    # Recalculate view mode when sensors change
    max_attributes = calculate_max_attributes(sensors)
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    {
      :noreply,
      socket
      |> assign(:sensors_online_count, sensors_count)
      |> assign(:sensors_online, sensors_online)
      |> assign(:sensors_offline, payload.leaves)
      |> assign(:global_view_mode, default_view_mode)
      |> assign(:grid_cols_sm, min(@grid_cols_sm_default, max(1, sensors_count)))
      |> assign(:grid_cols_lg, min(@grid_cols_lg_default, max(1, sensors_count)))
      |> assign(:grid_cols_xl, min(@grid_cols_xl_default, max(1, sensors_count)))
      |> assign(:grid_cols_2xl, min(@grid_cols_2xl_default, max(1, sensors_count)))
      |> assign(:sensors, sensors)
    }
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Lobby handled signal")
    {:noreply, put_flash(socket, :info, "Signal received!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  @impl true
  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Lobby Unknown Message")
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_all_view_mode", _params, socket) do
    new_mode = if socket.assigns.global_view_mode == :summary, do: :normal, else: :summary
    {:noreply, assign(socket, :global_view_mode, new_mode)}
  end

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Lobby Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end
end
