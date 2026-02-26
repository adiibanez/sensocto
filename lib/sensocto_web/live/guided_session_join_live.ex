defmodule SensoctoWeb.GuidedSessionJoinLive do
  use SensoctoWeb, :live_view

  alias Sensocto.Guidance.{GuidedSession, SessionSupervisor}

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Ash.read_one(GuidedSession,
           action: :by_invite_code,
           args: [invite_code: code],
           authorize?: false
         ) do
      {:ok, nil} ->
        {:ok,
         socket
         |> assign(:session, nil)
         |> assign(:invite_code, code)
         |> assign(:error, "This invitation is no longer valid.")
         |> assign(:page_title, "Join Guided Session")}

      {:ok, session} ->
        {:ok,
         socket
         |> assign(:session, session)
         |> assign(:invite_code, code)
         |> assign(:error, nil)
         |> assign(:page_title, "Join Guided Session")}

      {:error, _} ->
        {:ok,
         socket
         |> assign(:session, nil)
         |> assign(:invite_code, code)
         |> assign(:error, "Something went wrong.")
         |> assign(:page_title, "Join Guided Session")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:session, nil)
     |> assign(:invite_code, nil)
     |> assign(:error, "No invitation code provided.")
     |> assign(:page_title, "Join Guided Session")}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    session = socket.assigns.session
    current_user = socket.assigns.current_user

    if is_nil(current_user) do
      {:noreply, put_flash(socket, :error, "You must be signed in to join a guided session.")}
    else
      user_id = current_user.id
      user_name = current_user.display_name || current_user.email || "Follower"

      # Set follower and activate the session
      with {:ok, session} <-
             Ash.update(session, %{follower_user_id: user_id},
               action: :assign_follower,
               authorize?: false
             ),
           {:ok, session} <- Ash.update(session, %{}, action: :accept, authorize?: false) do
        # Start the session server
        SessionSupervisor.get_or_start_session(session.id,
          guide_user_id: session.guide_user_id,
          follower_user_id: user_id,
          follower_user_name: user_name,
          room_id: session.room_id,
          drift_back_seconds: session.drift_back_seconds
        )

        # Notify guide via user-specific topic
        Phoenix.PubSub.broadcast(
          Sensocto.PubSub,
          "user:#{session.guide_user_id}:guidance",
          {:guidance_invitation_accepted, %{session_id: session.id, follower_name: user_name}}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Joined guided session!")
         |> push_navigate(to: ~p"/lobby")}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not join this session.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-[60vh]">
      <div class="card bg-base-200 shadow-xl max-w-md w-full">
        <div class="card-body text-center">
          <h2 class="card-title justify-center text-2xl">Guided Session</h2>

          <%= if @error do %>
            <p class="text-error mt-4">{@error}</p>
            <div class="card-actions justify-center mt-4">
              <.link navigate={~p"/lobby"} class="btn btn-primary">
                Go to Lobby
              </.link>
            </div>
          <% else %>
            <p class="mt-4 text-base-content/70">
              You've been invited to a guided session. A trusted guide will help
              navigate the sensor experience with you.
            </p>
            <p class="mt-2 text-sm text-base-content/50">
              You can explore on your own at any time.
            </p>

            <div class="card-actions justify-center mt-6">
              <button phx-click="accept" class="btn btn-primary btn-lg">
                Accept & Join
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
