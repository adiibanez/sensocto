defmodule SensoctoWeb.PollsLive do
  use SensoctoWeb, :live_view
  require Logger
  require Ash.Query

  alias Sensocto.Collaboration.{Poll, PollOption}

  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_path, "/polls")
     |> assign(:polls, [])
     |> assign(:poll, nil)
     |> assign(:options_count, 2)
     |> assign(:option_values, %{})
     |> assign(:form, new_poll_form())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    polls = load_polls(socket.assigns.current_user)

    socket
    |> assign(:page_title, "Polls")
    |> assign(:polls, polls)
    |> assign(:poll, nil)
  end

  defp apply_action(socket, :new, _params) do
    if Map.get(socket.assigns.current_user, :is_guest) do
      socket
      |> put_flash(:error, "Sign in to create polls")
      |> push_navigate(to: ~p"/polls")
    else
      socket
      |> assign(:page_title, "New Poll")
      |> assign(:form, new_poll_form())
      |> assign(:options_count, 2)
      |> assign(:option_values, %{})
    end
  end

  defp apply_action(socket, :show, %{"id" => poll_id}) do
    case Ash.get(Poll, poll_id, authorize?: false) do
      {:ok, poll} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "poll:#{poll_id}")
        end

        socket
        |> assign(:page_title, poll.title)
        |> assign(:poll, poll)

      _ ->
        socket
        |> put_flash(:error, "Poll not found")
        |> push_navigate(to: ~p"/polls")
    end
  end

  @impl true
  def handle_event("add_option", _params, socket) do
    {:noreply, assign(socket, :options_count, socket.assigns.options_count + 1)}
  end

  def handle_event("validate_poll", params, socket) do
    option_values =
      for i <- 0..(socket.assigns.options_count - 1),
          val = params["option_#{i}"],
          into: %{},
          do: {i, val}

    {:noreply, assign(socket, :option_values, option_values)}
  end

  def handle_event(
        "create_poll",
        _params,
        %{assigns: %{current_user: %{is_guest: true}}} = socket
      ) do
    {:noreply, put_flash(socket, :error, "Sign in to create polls")}
  end

  def handle_event("create_poll", params, socket) do
    user = socket.assigns.current_user

    options =
      for i <- 0..(socket.assigns.options_count - 1),
          label = String.trim(params["option_#{i}"] || ""),
          label != "",
          do: {i, label}

    if length(options) < 2 do
      {:noreply, put_flash(socket, :error, "At least 2 options required")}
    else
      poll_attrs = %{
        title: params["title"],
        description: blank_to_nil(params["description"]),
        poll_type: String.to_existing_atom(params["poll_type"] || "single_choice"),
        visibility: :public,
        creator_id: user.id
      }

      case Poll
           |> Ash.Changeset.for_create(:create, poll_attrs)
           |> Ash.create(authorize?: false) do
        {:ok, poll} ->
          Enum.each(options, fn {pos, label} ->
            PollOption
            |> Ash.Changeset.for_create(:create, %{poll_id: poll.id, label: label, position: pos})
            |> Ash.create!(authorize?: false)
          end)

          {:noreply,
           socket
           |> put_flash(:info, "Poll created!")
           |> push_navigate(to: ~p"/polls/#{poll.id}")}

        {:error, error} ->
          Logger.warning("Poll creation failed: #{inspect(error)}")
          {:noreply, put_flash(socket, :error, "Failed to create poll")}
      end
    end
  end

  def handle_event("close_poll", %{"id" => poll_id}, socket) do
    case Ash.get(Poll, poll_id, authorize?: false) do
      {:ok, poll} ->
        poll
        |> Ash.Changeset.for_update(:close, %{})
        |> Ash.update!(authorize?: false)

        {:noreply, push_navigate(socket, to: ~p"/polls/#{poll_id}")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:vote_cast, poll_id}, socket) do
    if socket.assigns.poll && socket.assigns.poll.id == poll_id do
      send_update(SensoctoWeb.Components.PollComponent,
        id: "poll-#{poll_id}",
        vote_update: poll_id
      )
    end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_polls(user) do
    public_polls = Ash.read!(Poll, action: :public_open, authorize?: false)

    my_polls =
      if Map.get(user, :is_guest) do
        []
      else
        Poll
        |> Ash.Query.for_read(:by_creator, %{creator_id: user.id})
        |> Ash.read!(authorize?: false)
      end

    (public_polls ++ my_polls)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp new_poll_form do
    to_form(%{
      "title" => "",
      "description" => "",
      "poll_type" => "single_choice"
    })
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val
end
