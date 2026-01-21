defmodule SensoctoWeb.RoomComponents do
  @moduledoc """
  Reusable components for the rooms feature.
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes,
    endpoint: SensoctoWeb.Endpoint,
    router: SensoctoWeb.Router,
    statics: SensoctoWeb.static_paths()

  @doc """
  Renders a room card for listing pages.

  ## Examples

      <.room_card room={@room} current_user={@current_user} />
  """
  attr :room, :map, required: true
  attr :current_user, :map, required: true
  attr :on_delete, :string, default: nil

  def room_card(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 hover:bg-gray-750 transition-colors">
      <.link navigate={~p"/rooms/#{@room.id}"} class="block">
        <div class="flex items-start justify-between mb-2">
          <h3 class="text-lg font-semibold truncate"><%= @room.name %></h3>
          <div class="flex gap-1">
            <.visibility_badge is_public={@room.is_public} />
            <.persistence_badge is_persisted={Map.get(@room, :is_persisted, true)} />
          </div>
        </div>
        <%= if @room.description do %>
          <p class="text-gray-400 text-sm mb-3 line-clamp-2"><%= @room.description %></p>
        <% end %>
        <div class="flex items-center gap-4 text-sm text-gray-500">
          <span class="flex items-center gap-1">
            <.sensor_count_icon />
            <%= Map.get(@room, :sensor_count, 0) %> sensors
          </span>
          <span class="flex items-center gap-1">
            <.member_count_icon />
            <%= Map.get(@room, :member_count, 0) %> members
          </span>
        </div>
      </.link>
      <%= if @room.owner_id == @current_user.id && @on_delete do %>
        <div class="mt-3 pt-3 border-t border-gray-700 flex justify-end">
          <button
            phx-click={@on_delete}
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

  @doc """
  Renders a compact sensor summary with icon and activity status.

  ## Examples

      <.sensor_summary sensor={@sensor} activity_status={:active} />
  """
  attr :sensor, :map, required: true
  attr :activity_status, :atom, default: :unknown
  attr :on_remove, :string, default: nil

  def sensor_summary(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4">
      <div class="flex items-start justify-between mb-3">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-gray-700 rounded-lg">
            <.sensor_type_icon type={@sensor.sensor_type} />
          </div>
          <div>
            <h3 class="font-semibold truncate max-w-[120px]"><%= @sensor.sensor_name %></h3>
            <p class="text-xs text-gray-500"><%= @sensor.sensor_type %></p>
          </div>
        </div>
        <.activity_indicator status={@activity_status} />
      </div>

      <div class="text-sm text-gray-400">
        <%= length(Map.keys(@sensor.attributes || %{})) %> attributes
      </div>

      <%= if @on_remove do %>
        <div class="mt-3 pt-3 border-t border-gray-700">
          <button
            phx-click={@on_remove}
            phx-value-sensor_id={@sensor.sensor_id}
            class="text-red-400 hover:text-red-300 text-sm"
          >
            Remove
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders an activity indicator based on sensor status.

  ## Examples

      <.activity_indicator status={:active} />
  """
  attr :status, :atom, required: true

  def activity_indicator(assigns) do
    ~H"""
    <div class="relative flex items-center gap-1">
      <%= case @status do %>
        <% :active -> %>
          <span class="relative flex h-3 w-3">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
          </span>
          <span class="text-xs text-green-400">Active</span>
        <% :idle -> %>
          <span class="relative flex h-3 w-3">
            <span class="relative inline-flex rounded-full h-3 w-3 bg-yellow-500"></span>
          </span>
          <span class="text-xs text-yellow-400">Idle</span>
        <% _ -> %>
          <span class="relative flex h-3 w-3">
            <span class="relative inline-flex rounded-full h-3 w-3 bg-gray-500"></span>
          </span>
          <span class="text-xs text-gray-400">Inactive</span>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a visibility badge (public/private).
  """
  attr :is_public, :boolean, required: true

  def visibility_badge(assigns) do
    ~H"""
    <%= if @is_public do %>
      <span class="px-2 py-0.5 text-xs bg-green-600/20 text-green-400 rounded">Public</span>
    <% else %>
      <span class="px-2 py-0.5 text-xs bg-yellow-600/20 text-yellow-400 rounded">Private</span>
    <% end %>
    """
  end

  @doc """
  Renders a persistence badge (persisted/temporary).
  """
  attr :is_persisted, :boolean, required: true

  def persistence_badge(assigns) do
    ~H"""
    <%= if not @is_persisted do %>
      <span class="px-2 py-0.5 text-xs bg-purple-600/20 text-purple-400 rounded">Temporary</span>
    <% end %>
    """
  end

  @doc """
  Renders a sensor type icon based on the sensor type.
  """
  attr :type, :any, required: true
  attr :class, :string, default: "w-6 h-6 text-gray-400"

  def sensor_type_icon(assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <%= case @type do %>
        <% :ecg -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        <% :imu -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5M14 4l-2-1-2 1M4 7l2-1M4 7l2 1M4 7v2.5M12 21l-2-1m2 1l2-1m-2 1v-2.5M6 18l-2-1v-2.5M18 18l2-1v-2.5" />
        <% :html5 -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
        <% :buttplug -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
        <% :skeleton -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 2C13.1 2 14 2.9 14 4C14 5.1 13.1 6 12 6C10.9 6 10 5.1 10 4C10 2.9 10.9 2 12 2ZM21 9H15V22H13V16H11V22H9V9H3V7H21V9Z" />
        <% _ -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
      <% end %>
    </svg>
    """
  end

  defp sensor_count_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
    </svg>
    """
  end

  defp member_count_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
    """
  end
end
