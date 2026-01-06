defmodule SensoctoWeb.Components.BottomNav do
  @moduledoc """
  Mobile bottom navigation bar component.
  Shows 5 primary navigation items fixed at the bottom of the screen on mobile devices.
  """
  use Phoenix.Component
  use SensoctoWeb, :verified_routes

  attr :current_path, :string, required: true
  attr :class, :string, default: nil

  def bottom_nav(assigns) do
    ~H"""
    <nav
      id="bottom-nav"
      class={[
        "md:hidden fixed left-0 right-0 bg-gray-800 border-t border-gray-700 z-40",
        "bottom-[60px]",
        @class
      ]}
    >
      <div class="grid grid-cols-5 h-14">
        <.nav_item
          href={~p"/"}
          icon="home"
          label="Home"
          active={@current_path == "/"}
        />
        <.nav_item
          href={~p"/lobby"}
          icon="squares-2x2"
          label="Lobby"
          active={String.starts_with?(@current_path, "/lobby")}
        />
        <.nav_item
          href={~p"/rooms"}
          icon="building-office"
          label="Rooms"
          active={String.starts_with?(@current_path, "/rooms")}
        />
        <.nav_item
          href={~p"/sensors"}
          icon="signal"
          label="Sensors"
          active={String.starts_with?(@current_path, "/sensors")}
        />
        <.nav_item
          href={~p"/simulator"}
          icon="cpu-chip"
          label="Sim"
          active={String.starts_with?(@current_path, "/simulator")}
        />
      </div>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <a
      href={@href}
      data-phx-link="redirect"
      data-phx-link-state="push"
      class={[
        "flex flex-col items-center justify-center gap-0.5 transition-colors touch-manipulation",
        "min-h-[44px]",
        @active && "text-blue-400",
        !@active && "text-gray-400 hover:text-gray-200 active:text-blue-400"
      ]}
    >
      <Heroicons.icon name={@icon} type="outline" class="w-5 h-5" />
      <span class="text-[10px] font-medium"><%= @label %></span>
    </a>
    """
  end
end
