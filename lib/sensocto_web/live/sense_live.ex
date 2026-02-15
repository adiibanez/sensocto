defmodule SensoctoWeb.SenseLive do
  use SensoctoWeb, :live_view
  require Logger

  # NOTE: This LiveView is rendered in the layout footer via live_render with sticky: true
  # It should NOT require authentication since it needs to work on all pages including public ones
  # and requiring auth would cause a redirect loop on the sign-in page

  @impl true
  def mount(_params, session, socket) do
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")

    # Get bearer token from session
    # For regular users: use user_token (JWT from Ash Authentication)
    # For guests: use guest_token (from GuestUserStore)
    bearer_token =
      cond do
        # Check for regular user token first
        token = Map.get(session, "user_token") ->
          token

        # Check for guest token
        session["is_guest"] == true ->
          guest_id = Map.get(session, "guest_id")
          guest_token = Map.get(session, "guest_token")

          if guest_id && guest_token do
            # Prefix with "guest:" so channel can identify it as a guest token
            "guest:#{guest_id}:#{guest_token}"
          else
            nil
          end

        true ->
          nil
      end

    Logger.debug(
      "SenseLive mount - bearer_token present: #{bearer_token != nil}, is_guest: #{session["is_guest"]}"
    )

    parent_id = Map.get(session, "parent_id")

    {:ok,
     assign(socket,
       parent_id: parent_id,
       bearer_token: bearer_token,
       number: -1,
       bluetooth_enabled: false,
       sensor_names: ["PressureSensor", "Movesense", "BlueNRG", "FlexSenseSensor", "vívosmart"],
       attributes: [
         # pressure
         "453b02b0-71a1-11ea-ab12-0800200c9a66",
         "heart_rate",
         "battery_service",
         "61353090-8231-49cc-b57a-886370740041",
         # oximeter
         "a688bc90-09e2-4643-8e9a-ff3076703bc3",
         "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
         # flexsense
         "897fdb8d-dec3-40bc-98e8-2310a58b0189"
       ]
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.svelte name="SenseApp" props={%{bearerToken: @bearer_token}} socket={@socket} />
    <!--<%= if assigns.bluetooth_enabled == true do %>
      <button class="btn btn-blue" phx-click="toggle_bluetooth">No sense</button>
      <.svelte name="SenseApp" props={%{}} socket={@socket} />
    <% else %>
      <button class="btn btn-blue" phx-click="toggle_bluetooth">Sense</button>
    <% end %>-->
    """
  end

  defp send_test_event() do
    # push_event(socket, "test_event", %{points: 100, user: "josé"})
    Process.send_after(self(), :test_event, 1000)
  end

  @impl true
  def handle_info(:test_event, socket) do
    Logger.debug("Test event received")
    send_test_event()
    put_flash(socket, :info, "It worked!")
    {:noreply, push_event(socket, "test_event", %{points: 100, user: "josé"})}
    # {:noreply, socket}
  end

  # {:signal, %{test: 1}}
  def handle_info({:signal, msg}, socket) do
    Logger.debug("SenseLive handled signal: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Catch-all for unmatched messages
  def handle_info(msg, socket) do
    Logger.debug("SenseLive unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("trigger_parent_flash", _, socket) do
    send(socket.assigns.parent_id, {:trigger_parent_flash, "Flash from nested LiveView"})
    {:noreply, socket}
  end

  def handle_event("toggle_bluetooth", _, socket) do
    {:noreply, assign(socket, :bluetooth_enabled, !socket.assigns.bluetooth_enabled)}
  end
end
