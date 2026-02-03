defmodule SensoctoWeb.AboutLive do
  @moduledoc """
  About page that displays information about Sensocto's vision, use cases, and technology.
  Uses the shared AboutContentComponent for consistent content across pages.
  """
  use SensoctoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "About")

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => "research"}, _uri, socket) do
    {:noreply, assign(socket, :initial_detail_level, :research)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :initial_detail_level, :spark)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800">
      <.live_component
        module={SensoctoWeb.Components.AboutContentComponent}
        id="about-content"
        initial_detail_level={@initial_detail_level}
      />
    </div>
    """
  end
end
