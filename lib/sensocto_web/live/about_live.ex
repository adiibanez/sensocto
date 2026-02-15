defmodule SensoctoWeb.AboutLive do
  @moduledoc """
  About page that displays information about Sensocto's vision, use cases, and technology.
  Uses the shared AboutContentComponent for consistent content across pages.
  """
  use SensoctoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "About")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    detail_level =
      case params["tab"] do
        "story" -> :story
        "deep" -> :deep
        "research" -> :research
        "videos" -> :videos
        _ -> :spark
      end

    {:noreply, assign(socket, :detail_level, detail_level)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-gray-900 via-gray-900 to-gray-800">
      <.live_component
        module={SensoctoWeb.Components.AboutContentComponent}
        id="about-content"
        detail_level={@detail_level}
        patch_base={~p"/about"}
      />
    </div>
    """
  end
end
