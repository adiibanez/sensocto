defmodule SensoctoWeb.Components.PollsPanelComponent do
  @moduledoc """
  Embeddable polls panel for lobby and room views.
  Handles listing, creating, and voting on polls inline.
  """
  use SensoctoWeb, :live_component
  require Logger
  require Ash.Query

  alias Sensocto.Collaboration.{Poll, PollOption, Vote}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       view: :list,
       polls: [],
       selected_poll: nil,
       options_count: 2,
       option_values: %{},
       form: new_poll_form(),
       error: nil,
       user_votes: []
     )}
  end

  @impl true
  def update(%{vote_update: poll_id}, socket) do
    if socket.assigns[:selected_poll] && socket.assigns.selected_poll.id == poll_id do
      poll = load_poll(poll_id)
      user_votes = load_user_votes(poll_id, socket.assigns.current_user)
      {:ok, assign(socket, selected_poll: poll, user_votes: user_votes)}
    else
      polls = load_polls(socket.assigns.current_user, socket.assigns[:room_id])
      {:ok, assign(socket, polls: polls)}
    end
  end

  def update(assigns, socket) do
    room_id = assigns[:room_id]

    socket =
      socket
      |> assign(assigns)
      |> assign(:room_id, room_id)

    polls = load_polls(assigns.current_user, room_id)

    if connected?(socket) and not Map.get(socket.assigns, :subscribed, false) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "polls:lobby")
    end

    {:ok, assign(socket, polls: polls, subscribed: true)}
  end

  @impl true
  def handle_event("show_new", _params, socket) do
    if Map.get(socket.assigns.current_user, :is_guest) do
      {:noreply, assign(socket, error: "Sign in to create polls")}
    else
      {:noreply,
       assign(socket,
         view: :new,
         form: new_poll_form(),
         options_count: 2,
         option_values: %{},
         error: nil
       )}
    end
  end

  def handle_event("show_list", _params, socket) do
    polls = load_polls(socket.assigns.current_user, socket.assigns[:room_id])

    {:noreply,
     assign(socket,
       view: :list,
       selected_poll: nil,
       polls: polls,
       error: nil
     )}
  end

  def handle_event("show_poll", %{"id" => poll_id}, socket) do
    case Ash.get(Poll, poll_id, authorize?: false) do
      {:ok, poll} ->
        poll = load_poll(poll.id)
        user_votes = load_user_votes(poll.id, socket.assigns.current_user)

        Phoenix.PubSub.subscribe(Sensocto.PubSub, "poll:#{poll.id}")

        {:noreply,
         assign(socket,
           view: :show,
           selected_poll: poll,
           user_votes: user_votes,
           error: nil
         )}

      _ ->
        {:noreply, assign(socket, error: "Poll not found")}
    end
  end

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
    {:noreply, assign(socket, error: "Sign in to create polls")}
  end

  def handle_event("create_poll", params, socket) do
    user = socket.assigns.current_user
    room_id = socket.assigns[:room_id]

    options =
      for i <- 0..(socket.assigns.options_count - 1),
          label = String.trim(params["option_#{i}"] || ""),
          label != "",
          do: {i, label}

    if length(options) < 2 do
      {:noreply, assign(socket, error: "At least 2 options required")}
    else
      poll_attrs = %{
        title: params["title"],
        description: blank_to_nil(params["description"]),
        poll_type: String.to_existing_atom(params["poll_type"] || "single_choice"),
        visibility: if(room_id, do: :room, else: :public),
        room_id: room_id,
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

          poll = load_poll(poll.id)
          user_votes = load_user_votes(poll.id, user)

          Phoenix.PubSub.subscribe(Sensocto.PubSub, "poll:#{poll.id}")

          {:noreply,
           assign(socket,
             view: :show,
             selected_poll: poll,
             user_votes: user_votes,
             error: nil
           )}

        {:error, error} ->
          Logger.warning("Poll creation failed: #{inspect(error)}")
          {:noreply, assign(socket, error: "Failed to create poll")}
      end
    end
  end

  def handle_event("vote", %{"option_id" => option_id}, socket) do
    user = socket.assigns.current_user

    if is_nil(user) or Map.get(user, :is_guest) do
      {:noreply, assign(socket, error: "Sign in to vote")}
    else
      poll = socket.assigns.selected_poll

      if poll.poll_type == :single_choice do
        retract_existing_votes(poll.id, user.id)
      end

      case Vote
           |> Ash.Changeset.for_create(:cast, %{
             poll_id: poll.id,
             option_id: option_id,
             user_id: user.id
           })
           |> Ash.create(authorize?: false) do
        {:ok, _vote} ->
          poll = load_poll(poll.id)
          user_votes = load_user_votes(poll.id, user)
          {:noreply, assign(socket, selected_poll: poll, user_votes: user_votes, error: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Could not cast vote")}
      end
    end
  end

  def handle_event("close_poll", %{"id" => poll_id}, socket) do
    case Ash.get(Poll, poll_id, authorize?: false) do
      {:ok, poll} ->
        poll
        |> Ash.Changeset.for_update(:close, %{})
        |> Ash.update!(authorize?: false)

        poll = load_poll(poll_id)
        {:noreply, assign(socket, selected_poll: poll)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full">
      <%= case @view do %>
        <% :list -> %>
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-gray-300">Polls</h3>
            <%= unless Map.get(@current_user, :is_guest) do %>
              <button
                phx-click="show_new"
                phx-target={@myself}
                class="text-xs px-2 py-1 bg-purple-600 hover:bg-purple-500 text-white rounded transition-colors"
              >
                + New Poll
              </button>
            <% end %>
          </div>

          <%= if @error do %>
            <p class="text-sm text-red-400 mb-2">{@error}</p>
          <% end %>

          <%= if @polls == [] do %>
            <p class="text-gray-500 text-sm text-center py-6">No active polls</p>
          <% else %>
            <div class="space-y-2">
              <%= for poll <- @polls do %>
                <button
                  phx-click="show_poll"
                  phx-value-id={poll.id}
                  phx-target={@myself}
                  class="w-full text-left p-3 bg-gray-800 rounded-lg hover:bg-gray-750 transition-colors"
                >
                  <div class="flex justify-between items-start">
                    <div class="min-w-0 flex-1">
                      <h4 class="text-sm text-white font-medium truncate">{poll.title}</h4>
                      <%= if poll.description do %>
                        <p class="text-xs text-gray-400 mt-0.5 line-clamp-1">{poll.description}</p>
                      <% end %>
                    </div>
                    <span class={[
                      "text-[10px] px-1.5 py-0.5 rounded-full shrink-0 ml-2",
                      if(poll.status == :open,
                        do: "bg-green-900/50 text-green-400",
                        else: "bg-gray-700 text-gray-400"
                      )
                    ]}>
                      {poll.status}
                    </span>
                  </div>
                </button>
              <% end %>
            </div>
          <% end %>
        <% :new -> %>
          <div class="flex items-center gap-2 mb-3">
            <button
              phx-click="show_list"
              phx-target={@myself}
              class="text-gray-400 hover:text-white transition-colors"
            >
              <Heroicons.icon name="arrow-left" type="solid" class="h-4 w-4" />
            </button>
            <h3 class="text-sm font-medium text-gray-300">New Poll</h3>
          </div>

          <%= if @error do %>
            <p class="text-sm text-red-400 mb-2">{@error}</p>
          <% end %>

          <form
            phx-submit="create_poll"
            phx-change="validate_poll"
            phx-target={@myself}
            class="space-y-3"
          >
            <div>
              <input
                type="text"
                name="title"
                required
                placeholder="What should we decide?"
                class="w-full rounded-md bg-gray-700 border-gray-600 text-white text-sm px-3 py-2"
              />
            </div>

            <div>
              <textarea
                name="description"
                rows="2"
                placeholder="Add context (optional)"
                class="w-full rounded-md bg-gray-700 border-gray-600 text-white text-sm px-3 py-2"
              />
            </div>

            <div>
              <select
                name="poll_type"
                class="rounded-md bg-gray-700 border-gray-600 text-white text-sm px-3 py-2"
              >
                <option value="single_choice">Single Choice</option>
                <option value="multiple_choice">Multiple Choice</option>
              </select>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-400 mb-1">Options</label>
              <div class="space-y-1.5">
                <%= for i <- 0..(@options_count - 1) do %>
                  <input
                    type="text"
                    name={"option_#{i}"}
                    value={Map.get(@option_values, i, "")}
                    placeholder={"Option #{i + 1}"}
                    class="w-full rounded-md bg-gray-700 border-gray-600 text-white text-xs px-3 py-2"
                  />
                <% end %>
              </div>
              <button
                type="button"
                phx-click="add_option"
                phx-target={@myself}
                class="mt-1.5 text-xs text-blue-400 hover:text-blue-300"
              >
                + Add option
              </button>
            </div>

            <button
              type="submit"
              class="w-full px-3 py-2 bg-purple-600 hover:bg-purple-500 text-white text-sm rounded-md transition-colors"
            >
              Create Poll
            </button>
          </form>
        <% :show -> %>
          <div class="flex items-center gap-2 mb-3">
            <button
              phx-click="show_list"
              phx-target={@myself}
              class="text-gray-400 hover:text-white transition-colors"
            >
              <Heroicons.icon name="arrow-left" type="solid" class="h-4 w-4" />
            </button>
            <h3 class="text-sm font-medium text-gray-300 truncate">{@selected_poll.title}</h3>
          </div>

          <%= if @error do %>
            <p class="text-sm text-red-400 mb-2">{@error}</p>
          <% end %>

          <div class="bg-gray-800 rounded-lg p-3">
            <%= if @selected_poll.description do %>
              <p class="text-xs text-gray-400 mb-3">{@selected_poll.description}</p>
            <% end %>

            <div class="space-y-1.5">
              <%= for option <- @selected_poll.options do %>
                <% voted = option.id in Enum.map(@user_votes, & &1.option_id) %>
                <% total = max(@selected_poll.vote_count, 1) %>
                <% pct =
                  if @selected_poll.vote_count > 0,
                    do: round(option.vote_count / total * 100),
                    else: 0 %>

                <button
                  phx-click="vote"
                  phx-value-option_id={option.id}
                  phx-target={@myself}
                  disabled={
                    @selected_poll.status != :open or
                      (not is_nil(@current_user) and Map.get(@current_user, :is_guest))
                  }
                  class={[
                    "w-full text-left rounded-md p-2.5 relative overflow-hidden transition-colors",
                    if(voted,
                      do: "bg-purple-900/40 border border-purple-500",
                      else: "bg-gray-700 hover:bg-gray-650 border border-transparent"
                    )
                  ]}
                >
                  <div
                    class="absolute inset-y-0 left-0 bg-purple-600/20 transition-all"
                    style={"width: #{pct}%"}
                  >
                  </div>
                  <div class="relative flex justify-between items-center">
                    <span class="text-xs text-gray-200">{option.label}</span>
                    <span class="text-[10px] text-gray-400 ml-2">{option.vote_count} ({pct}%)</span>
                  </div>
                </button>
              <% end %>
            </div>

            <div class="mt-2 flex justify-between items-center text-[10px] text-gray-500">
              <span>{@selected_poll.vote_count} total votes</span>
              <span class={[
                "px-1.5 py-0.5 rounded-full",
                if(@selected_poll.status == :open,
                  do: "bg-green-900/50 text-green-400",
                  else: "bg-gray-700 text-gray-400"
                )
              ]}>
                {@selected_poll.status}
              </span>
            </div>

            <%= if @selected_poll.creator_id == @current_user.id and @selected_poll.status == :open do %>
              <div class="mt-2 pt-2 border-t border-gray-700">
                <button
                  phx-click="close_poll"
                  phx-value-id={@selected_poll.id}
                  phx-target={@myself}
                  class="text-xs text-red-400 hover:text-red-300"
                  data-confirm="Close this poll? No more votes will be accepted."
                >
                  Close Poll
                </button>
              </div>
            <% end %>
          </div>
      <% end %>
    </div>
    """
  end

  defp load_polls(user, room_id) do
    if room_id do
      # Room polls: room-specific + public open
      room_polls =
        Poll
        |> Ash.Query.for_read(:for_room, %{room_id: room_id})
        |> Ash.read!(authorize?: false)

      public_polls = Ash.read!(Poll, action: :public_open, authorize?: false)

      (room_polls ++ public_polls)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    else
      # Lobby polls: public open + user's own
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
  end

  defp load_poll(poll_id) do
    Ash.get!(Poll, poll_id,
      load: [:options, :vote_count, options: [:vote_count]],
      authorize?: false
    )
  end

  defp load_user_votes(_poll_id, nil), do: []
  defp load_user_votes(_poll_id, %{is_guest: true}), do: []

  defp load_user_votes(poll_id, user) do
    Vote
    |> Ash.Query.filter(poll_id == ^poll_id and user_id == ^user.id)
    |> Ash.read!(authorize?: false)
  end

  defp retract_existing_votes(poll_id, user_id) do
    Vote
    |> Ash.Query.filter(poll_id == ^poll_id and user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))
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
