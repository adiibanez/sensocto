defmodule SensoctoWeb.Components.PollComponent do
  use SensoctoWeb, :live_component
  require Ash.Query

  alias Sensocto.Collaboration.{Poll, Vote}

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, error: nil)}
  end

  @impl true
  def update(%{vote_update: _poll_id}, socket) do
    poll = load_poll(socket.assigns.poll_id)
    user_votes = load_user_votes(socket.assigns.poll_id, socket.assigns.current_user)
    {:ok, assign(socket, poll: poll, user_votes: user_votes)}
  end

  def update(assigns, socket) do
    poll = load_poll(assigns.poll_id)
    user_votes = load_user_votes(assigns.poll_id, assigns.current_user)

    if connected?(socket) and not Map.get(socket.assigns, :subscribed, false) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "poll:#{assigns.poll_id}")
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(poll: poll, user_votes: user_votes, subscribed: true)}
  end

  @impl true
  def handle_event("vote", %{"option_id" => option_id}, socket) do
    user = socket.assigns.current_user

    if is_nil(user) or Map.get(user, :is_guest) do
      {:noreply, assign(socket, error: "Sign in to vote")}
    else
      poll = socket.assigns.poll

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
          {:noreply, assign(socket, poll: poll, user_votes: user_votes, error: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Could not cast vote")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4">
      <h3 class="text-white font-semibold mb-1">{@poll.title}</h3>
      <%= if @poll.description do %>
        <p class="text-sm text-gray-400 mb-3">{@poll.description}</p>
      <% end %>

      <div class="space-y-2">
        <%= for option <- @poll.options do %>
          <% voted = option.id in Enum.map(@user_votes, & &1.option_id) %>
          <% total = max(@poll.vote_count, 1) %>
          <% pct = if @poll.vote_count > 0, do: round(option.vote_count / total * 100), else: 0 %>

          <button
            phx-click="vote"
            phx-value-option_id={option.id}
            phx-target={@myself}
            disabled={
              @poll.status != :open or
                (not is_nil(@current_user) and Map.get(@current_user, :is_guest))
            }
            class={[
              "w-full text-left rounded-md p-3 relative overflow-hidden transition-colors",
              if(voted,
                do: "bg-blue-900/40 border border-blue-500",
                else: "bg-gray-700 hover:bg-gray-650 border border-transparent"
              )
            ]}
          >
            <div
              class="absolute inset-y-0 left-0 bg-blue-600/20 transition-all"
              style={"width: #{pct}%"}
            >
            </div>
            <div class="relative flex justify-between items-center">
              <span class="text-sm text-gray-200">{option.label}</span>
              <span class="text-xs text-gray-400 ml-2">{option.vote_count} ({pct}%)</span>
            </div>
          </button>
        <% end %>
      </div>

      <div class="mt-2 flex justify-between items-center text-xs text-gray-500">
        <span>{@poll.vote_count} total votes</span>
        <span class={[
          "px-2 py-0.5 rounded-full",
          if(@poll.status == :open,
            do: "bg-green-900/50 text-green-400",
            else: "bg-gray-700 text-gray-400"
          )
        ]}>
          {@poll.status}
        </span>
      </div>

      <%= if @error do %>
        <p class="mt-2 text-sm text-red-400">{@error}</p>
      <% end %>
    </div>
    """
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
end
