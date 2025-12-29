defmodule SensoctoWeb.IndexLive do
  # alias Sensocto.SimpleSensor
  use SensoctoWeb, :live_view
  # LVN_ACTIVATION use SensoctoNative, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.StatefulSensorLive

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 6
  @grid_cols_2xl_default 6

  # https://dev.to/ivor/how-to-unsubscribe-from-all-topics-in-phoenixpubsub-dka
  # https://hexdocs.pm/phoenix_live_view/bindings.html#js-commands

  @impl true
  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
    # Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurement")
    # Phoenix.PubSub.subscribe(Sensocto.PubSub, "measurements_batch")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")

    # presence tracking

    new_socket =
      socket
      |> assign(
        sensors_online_count: 0,
        sensors_online: %{},
        sensors_offline: %{},
        sensors: %{},
        test: %{:test2 => %{:timestamp => 123, :payload => 10}},
        stream_div_class: "",
        grid_cols_sm: @grid_cols_sm_default,
        grid_cols_lg: @grid_cols_lg_default,
        grid_cols_xl: @grid_cols_xl_default,
        grid_cols_2xl: @grid_cols_2xl_default
      )
      |> assign(:sensors, Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view))

    :telemetry.execute(
      [:sensocto, :live, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
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
      "presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
    )

    sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)
    sensors_online_count = Enum.count(socket.assigns.sensors)

    {
      :noreply,
      socket
      |> assign(:sensors_online_count, sensors_online_count)
      |> assign(:sensors_online, sensors_online)
      |> assign(:sensors_offline, payload.leaves)
      |> assign(:grid_cols_sm, min(@grid_cols_sm_default, sensors_online_count))
      |> assign(:grid_cols_lg, min(@grid_cols_lg_default, sensors_online_count))
      |> assign(:grid_cols_xl, min(@grid_cols_xl_default, sensors_online_count))
      |> assign(:grid_cols_2xl, min(@grid_cols_2xl_default, sensors_online_count))
      |> assign(:sensors, Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view))
    }
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Handled message {__MODULE__}")

    {:noreply, put_flash(socket, :info, "You clicked the button!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  @impl true
  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Unknown Message")
    {:noreply, socket}
  end

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end
end
