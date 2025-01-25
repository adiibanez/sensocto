defmodule SensoctoWeb.SensorLive.Show do
  use SensoctoWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Sensor {@sensor.id}
      <:subtitle>This is a sensor record from your database.</:subtitle>

      <:actions>
        <.link patch={~p"/sensors/#{@sensor}/edit"} phx-click={JS.push_focus()}>
          <.button>Edit sensor</.button>
        </.link>
      </:actions>
    </.header>

    <.list>
      <:item title="Id">{@sensor.id}</:item>

      <:item title="Name">{@sensor.name}</:item>

      <:item title="Sensor type">{@sensor.sensor_type_id}</:item>

      <:item title="Mac address">{@sensor.mac_address}</:item>

      <:item title="Configuration">{@sensor.configuration}</:item>
    </.list>

    <.back navigate={~p"/sensors"}>Back to sensors</.back>

    <.modal
      :if={@live_action == :edit}
      id="sensor-modal"
      show
      on_cancel={JS.patch(~p"/sensors/#{@sensor}")}
    >
      <.live_component
        module={SensoctoWeb.SensorLive.FormComponent}
        id={@sensor.id}
        title={@page_title}
        action={@live_action}
        current_user={@current_user}
        sensor={@sensor}
        patch={~p"/sensors/#{@sensor}"}
      />
    </.modal>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:sensor, Ash.get!(Sensocto.Sensors.Sensor, id, actor: socket.assigns.current_user))}
  end

  defp page_title(:show), do: "Show Sensor"
  defp page_title(:edit), do: "Edit Sensor"
end
