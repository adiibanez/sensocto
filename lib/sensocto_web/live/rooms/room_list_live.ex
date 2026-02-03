defmodule SensoctoWeb.RoomListLive do
  @moduledoc """
  LiveView for listing and managing rooms.
  Shows user's rooms and public rooms with options to create new rooms.
  """
  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Rooms

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Rooms")
      |> assign(:current_path, "/rooms")
      |> assign(:user_rooms, Rooms.list_user_rooms(user))
      |> assign(:public_rooms, Rooms.list_public_rooms())
      |> assign(:show_create_modal, false)
      |> assign(:active_tab, :all)
      |> assign(
        :form,
        to_form(%{
          "name" => "",
          "description" => "",
          "is_public" => true,
          "is_persisted" => true,
          "calls_enabled" => true
        })
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    tab =
      case params["tab"] do
        "my" -> :my
        "public" -> :public
        _ -> :all
      end

    socket
    |> assign(:page_title, "Rooms")
    |> assign(:show_create_modal, false)
    |> assign(:active_tab, tab)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Room")
    |> assign(:show_create_modal, true)
  end

  @impl true
  def handle_event("open_create_modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/rooms/new")}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/rooms")}
  end

  @impl true
  def handle_event("validate", %{"name" => name, "description" => description} = params, socket) do
    # Checkboxes are only present in params when checked, absent when unchecked
    form =
      to_form(%{
        "name" => name,
        "description" => description,
        "is_public" => Map.has_key?(params, "is_public"),
        "is_persisted" => Map.has_key?(params, "is_persisted"),
        "calls_enabled" => Map.has_key?(params, "calls_enabled")
      })

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event(
        "create_room",
        %{"name" => name, "description" => description} = params,
        socket
      ) do
    user = socket.assigns.current_user

    # Checkboxes are only present in params when checked
    attrs = %{
      name: name,
      description: description,
      is_public: Map.has_key?(params, "is_public"),
      is_persisted: Map.has_key?(params, "is_persisted"),
      calls_enabled: Map.has_key?(params, "calls_enabled")
    }

    case Rooms.create_room(attrs, user) do
      {:ok, room} ->
        room_id = Map.get(room, :id)

        socket =
          socket
          |> put_flash(:info, "Room created successfully!")
          |> push_navigate(to: ~p"/rooms/#{room_id}")

        {:noreply, socket}

      {:error, changeset} ->
        Logger.error("Failed to create room: #{inspect(changeset)}")

        {:noreply, put_flash(socket, :error, "Failed to create room")}
    end
  end

  @impl true
  def handle_event("delete_room", %{"id" => room_id}, socket) do
    user = socket.assigns.current_user

    case Rooms.get_room(room_id) do
      {:ok, room} ->
        if Rooms.owner?(room, user) do
          case Rooms.delete_room(room, user) do
            :ok ->
              socket =
                socket
                |> put_flash(:info, "Room deleted")
                |> assign(:user_rooms, Rooms.list_user_rooms(user))
                |> assign(:public_rooms, Rooms.list_public_rooms())

              {:noreply, socket}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete room")}
          end
        else
          {:noreply, put_flash(socket, :error, "Only the owner can delete a room")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Room not found")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.breadcrumbs>
        <:crumb>Rooms</:crumb>
      </.breadcrumbs>

      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Rooms</h1>
        <button
          phx-click="open_create_modal"
          class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
        >
          <Heroicons.icon name="plus" type="outline" class="h-5 w-5" /> Create Room
        </button>
      </div>

      <.tabs>
        <:tab patch={~p"/rooms"} active={@active_tab == :all}>All Rooms</:tab>
        <:tab patch={~p"/rooms?tab=my"} active={@active_tab == :my}>My Rooms</:tab>
        <:tab patch={~p"/rooms?tab=public"} active={@active_tab == :public}>Public Rooms</:tab>
      </.tabs>

      <%= case @active_tab do %>
        <% :all -> %>
          <%= if Enum.empty?(@user_rooms) and Enum.empty?(@public_rooms) do %>
            <.empty_state />
          <% else %>
            <%= if not Enum.empty?(@user_rooms) do %>
              <div class="mb-8">
                <h2 class="text-lg font-semibold mb-4 text-gray-300">Your Rooms</h2>
                <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                  <%= for room <- @user_rooms do %>
                    <.room_card room={room} current_user={@current_user} />
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if not Enum.empty?(@public_rooms) do %>
              <div>
                <h2 class="text-lg font-semibold mb-4 text-gray-300">Public Rooms</h2>
                <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                  <%= for room <- @public_rooms do %>
                    <.room_card room={room} current_user={@current_user} />
                  <% end %>
                </div>
              </div>
            <% end %>
          <% end %>
        <% :my -> %>
          <%= if Enum.empty?(@user_rooms) do %>
            <.empty_state message="You haven't created or joined any rooms yet." />
          <% else %>
            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              <%= for room <- @user_rooms do %>
                <.room_card room={room} current_user={@current_user} />
              <% end %>
            </div>
          <% end %>
        <% :public -> %>
          <%= if Enum.empty?(@public_rooms) do %>
            <.empty_state message="No public rooms available." />
          <% else %>
            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              <%= for room <- @public_rooms do %>
                <.room_card room={room} current_user={@current_user} />
              <% end %>
            </div>
          <% end %>
      <% end %>

      <%= if @show_create_modal do %>
        <.create_room_modal form={@form} />
      <% end %>
    </div>
    """
  end

  defp empty_state(assigns) do
    assigns = assign_new(assigns, :message, fn -> "No rooms found." end)

    ~H"""
    <div class="text-center py-12">
      <Heroicons.icon name="home" type="outline" class="h-12 w-12 mx-auto mb-4 text-gray-500" />
      <p class="text-gray-400">{@message}</p>
      <button
        phx-click="open_create_modal"
        class="mt-4 text-blue-400 hover:text-blue-300"
      >
        Create your first room
      </button>
    </div>
    """
  end

  defp room_card(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 hover:bg-gray-750 transition-colors">
      <.link navigate={~p"/rooms/#{@room.id}"} class="block">
        <div class="flex items-start justify-between mb-2">
          <h3 class="text-lg font-semibold truncate">{@room.name}</h3>
          <div class="flex gap-1">
            <%= if @room.is_public do %>
              <span class="px-2 py-0.5 text-xs bg-green-600/20 text-green-400 rounded">Public</span>
            <% else %>
              <span class="px-2 py-0.5 text-xs bg-yellow-600/20 text-yellow-400 rounded">
                Private
              </span>
            <% end %>
            <%= if not Map.get(@room, :is_persisted, true) do %>
              <span class="px-2 py-0.5 text-xs bg-purple-600/20 text-purple-400 rounded">
                Temporary
              </span>
            <% end %>
          </div>
        </div>
        <%= if @room.description do %>
          <p class="text-gray-400 text-sm mb-3 line-clamp-2">{@room.description}</p>
        <% end %>
        <div class="flex items-center gap-4 text-sm text-gray-500">
          <span class="flex items-center gap-1">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
              />
            </svg>
            {Map.get(@room, :sensor_count, 0)} sensors
          </span>
          <span class="flex items-center gap-1">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
              />
            </svg>
            {Map.get(@room, :member_count, 0)} members
          </span>
        </div>
      </.link>
      <%= if @room.owner_id == @current_user.id do %>
        <div class="mt-3 pt-3 border-t border-gray-700 flex justify-end">
          <button
            phx-click="delete_room"
            phx-value-id={@room.id}
            data-confirm="Are you sure you want to delete this room?"
            class="text-red-400 hover:text-red-300 text-sm"
          >
            Delete
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp create_room_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-click="close_modal"
    >
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md" phx-click={%JS{}}>
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Create New Room</h2>
          <button phx-click="close_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        <.form for={@form} phx-submit="create_room" phx-change="validate" class="space-y-4">
          <div>
            <label for="name" class="block text-sm font-medium text-gray-300 mb-1">Room Name</label>
            <input
              type="text"
              name="name"
              id="name"
              value={@form[:name].value}
              required
              class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Enter room name..."
            />
          </div>

          <div>
            <label for="description" class="block text-sm font-medium text-gray-300 mb-1">
              Description
            </label>
            <textarea
              name="description"
              id="description"
              rows="3"
              class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Optional description..."
            ><%= @form[:description].value %></textarea>
          </div>

          <div class="space-y-3">
            <div class="flex items-center gap-6">
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="is_public"
                  checked={@form[:is_public].value}
                  class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
                />
                <span class="text-sm text-gray-300">Public room</span>
              </label>

              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="is_persisted"
                  checked={@form[:is_persisted].value}
                  class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
                />
                <span class="text-sm text-gray-300">Persist to database</span>
              </label>
            </div>

            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="calls_enabled"
                checked={@form[:calls_enabled].value}
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-300">Enable video/audio calls</span>
            </label>
          </div>

          <div class="flex gap-3 pt-4">
            <button
              type="button"
              phx-click="close_modal"
              class="flex-1 bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="flex-1 bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
            >
              Create Room
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
