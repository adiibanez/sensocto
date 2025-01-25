defmodule SensoctoWeb.SensorLive.FormComponent do
  use SensoctoWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage sensor records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="sensor-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" /><.input
          field={@form[:sensor_type_id]}
          type="text"
          label="Sensor type"
        /><.input field={@form[:mac_address]} type="text" label="Mac address" /><.input
          field={@form[:configuration]}
          type="text"
          label="Configuration"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Sensor</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"sensor" => sensor_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, sensor_params))}
  end

  def handle_event("save", %{"sensor" => sensor_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: sensor_params) do
      {:ok, sensor} ->
        notify_parent({:saved, sensor})

        socket =
          socket
          |> put_flash(:info, "Sensor #{socket.assigns.form.source.type}d successfully")
          |> push_patch(to: socket.assigns.patch)

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp assign_form(%{assigns: %{sensor: sensor}} = socket) do
    form =
      if sensor do
        AshPhoenix.Form.for_update(sensor, :update,
          as: "sensor",
          actor: socket.assigns.current_user
        )
      else
        AshPhoenix.Form.for_create(Sensocto.Sensors.Sensor, :create,
          as: "sensor",
          actor: socket.assigns.current_user
        )
      end

    assign(socket, form: to_form(form))
  end
end
