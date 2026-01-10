defmodule SensoctoWeb.RoomJoinLive do
  @moduledoc """
  LiveView for joining a room via join code.
  Shows room preview and allows authenticated users to join.
  """
  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Rooms

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    user = socket.assigns.current_user

    case Rooms.get_room_by_code(code) do
      {:ok, nil} ->
        socket =
          socket
          |> assign(:page_title, "Room Not Found")
          |> assign(:room, nil)
          |> assign(:error, "Invalid join code")
          |> assign(:code, code)

        {:ok, socket}

      {:ok, room} ->
        is_member = user != nil and Rooms.member?(room, user)
        is_owner = user != nil and Rooms.owner?(room, user)

        socket =
          socket
          |> assign(:page_title, "Join #{room.name}")
          |> assign(:room, room)
          |> assign(:error, nil)
          |> assign(:code, code)
          |> assign(:is_member, is_member)
          |> assign(:is_owner, is_owner)

        {:ok, socket}

      {:error, _} ->
        socket =
          socket
          |> assign(:page_title, "Room Not Found")
          |> assign(:room, nil)
          |> assign(:error, "Invalid join code")
          |> assign(:code, code)

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("join_room", _params, socket) do
    user = socket.assigns.current_user
    room = socket.assigns.room

    if user do
      case Rooms.join_room(room, user) do
        {:ok, _room} ->
          socket =
            socket
            |> put_flash(:info, "Successfully joined the room!")
            |> push_navigate(to: ~p"/rooms/#{room.id}")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to join room. You may already be a member.")}
      end
    else
      {:noreply, push_navigate(socket, to: ~p"/sign-in?return_to=/rooms/join/#{socket.assigns.code}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4">
      <div class="bg-gray-800 rounded-lg p-8 w-full max-w-md text-center">
        <%= if @error do %>
          <div class="mb-6">
            <svg class="w-16 h-16 mx-auto text-red-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <h1 class="text-2xl font-bold mb-2">Room Not Found</h1>
            <p class="text-gray-400">The join code "<%= @code %>" is invalid or the room no longer exists.</p>
          </div>
          <.link
            navigate={~p"/rooms"}
            class="inline-block bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-6 rounded-lg transition-colors"
          >
            Browse Rooms
          </.link>
        <% else %>
          <div class="mb-6">
            <svg class="w-16 h-16 mx-auto text-blue-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
            <h1 class="text-2xl font-bold mb-2">Join Room</h1>
            <h2 class="text-xl text-gray-300"><%= @room.name %></h2>
          </div>

          <%= if @room.description do %>
            <p class="text-gray-400 mb-6"><%= @room.description %></p>
          <% end %>

          <div class="flex justify-center gap-4 mb-6 text-sm text-gray-400">
            <%= if @room.is_public do %>
              <span class="flex items-center gap-1">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Public
              </span>
            <% else %>
              <span class="flex items-center gap-1">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                Private
              </span>
            <% end %>
            <span class="flex items-center gap-1">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
              </svg>
              <%= Map.get(@room, :sensor_count, 0) %> sensors
            </span>
          </div>

          <%= if @is_member or @is_owner do %>
            <div class="space-y-3">
              <p class="text-green-400 mb-2">You're already a member of this room!</p>
              <.link
                navigate={~p"/rooms/#{@room.id}"}
                class="inline-block bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-6 rounded-lg transition-colors"
              >
                Go to Room
              </.link>
            </div>
          <% else %>
            <%= if @current_user do %>
              <button
                phx-click="join_room"
                class="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-6 rounded-lg transition-colors"
              >
                Join Room
              </button>
            <% else %>
              <div class="space-y-4">
                <p class="text-gray-400">Sign in to join this room</p>
                <.link
                  navigate={~p"/sign-in?return_to=/rooms/join/#{@code}"}
                  class="inline-block w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-6 rounded-lg transition-colors"
                >
                  Sign In
                </.link>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
