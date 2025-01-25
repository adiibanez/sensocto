defmodule SensoctoWeb.SensorLive.Index do
  use SensoctoWeb, :live_view
  require Logger
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Listing Sensors
      <:actions>
        <.link patch={~p"/sensors/new"}>
          <.button>New Sensor</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="sensors"
      rows={@streams.sensors}
      row_click={fn {_id, sensor} -> JS.navigate(~p"/sensors/#{sensor}") end}
    >
      <:col :let={{_id, sensor}} label="Id">{sensor.id}</:col>

      <:col :let={{_id, sensor}} label="Name">{sensor.name}</:col>

      <:col :let={{_id, sensor}} label="Sensor type">{sensor.sensor_type_id}</:col>

      <:col :let={{_id, sensor}} label="Mac address">{sensor.mac_address}</:col>

      <:col :let={{_id, sensor}} label="Configuration">{sensor.configuration}</:col>

      <:action :let={{_id, sensor}}>
        <div class="sr-only">
          <.link navigate={~p"/sensors/#{sensor}"}>Show</.link>
        </div>

        <.link patch={~p"/sensors/#{sensor}/edit"}>Edit</.link>
      </:action>

      <:action :let={{id, sensor}}>
        <.link
          phx-click={JS.push("delete", value: %{id: sensor.id}) |> hide("##{id}")}
          data-confirm="Are you sure?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="sensor-modal"
      show
      on_cancel={JS.patch(~p"/sensors")}
    >
      <.live_component
        module={SensoctoWeb.SensorLive.FormComponent}
        id={(@sensor && @sensor.id) || :new}
        title={@page_title}
        current_user={@current_user}
        action={@live_action}
        sensor={@sensor}
        patch={~p"/sensors"}
      />
    </.modal>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:sensors, Ash.read!(Sensocto.Sensors.Sensor, actor: socket.assigns[:current_user]))
     |> assign_new(:current_user, fn -> nil end)}
  end

  def handle_params(%{:id => id} = params, url, socket) do
    Logger.info("Here I am #{id} #{inspect(params)} #{url}")
    #case socket.assigns.live_action do
    #  nil -> {:noreply, apply_action(socket, :index, params)}
    #  _ -> {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    #end
    {:noreply, socket}
    #{:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    Logger.info("Here I am #{_url} #{inspect(params)} #{inspect(socket.assigns.live_action)} #{inspect(@live_action)}")
    #case socket.assigns.live_action do
    #  nil -> {:noreply, apply_action(socket, :index, params)}
    #  _ -> {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    #end
    {:noreply, apply_action(socket, @live_action, params)}
    #{:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Sensors")
    |> assign(:sensor, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Sensor")
    |> assign(:sensor, Ash.get!(Sensocto.Sensors.Sensor, id, actor: socket.assigns.current_user))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Sensor")
    |> assign(:sensor, nil)
  end

  defp apply_action(socket, action, params) do
    Logger.debug("Apply fallback action: #{inspect(action)} #{inspect(params)} ")
   socket
   |> assign(:live_action, :index)
   |> assign(:page_title, "Listing Sensors")
   #|> assign(:sensor, nil)
  end


  @impl true
  def handle_info({SensoctoWeb.SensorLive.FormComponent, {:saved, sensor}}, socket) do
    {:noreply, stream_insert(socket, :sensors, sensor)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    sensor = Ash.get!(Sensocto.Sensors.Sensor, id, actor: socket.assigns.current_user)
    Ash.destroy!(sensor, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :sensors, sensor)}
  end
end
