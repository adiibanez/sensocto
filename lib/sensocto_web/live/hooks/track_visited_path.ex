defmodule SensoctoWeb.Live.Hooks.TrackVisitedPath do
  @moduledoc """
  LiveView hook that tracks the last visited path for authenticated users.
  Saves the current path to user preferences on each navigation.
  """
  import Phoenix.LiveView

  alias Sensocto.Accounts.UserPreferences

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> attach_hook(:track_path, :handle_params, &track_path/3)

    {:cont, socket}
  end

  defp track_path(_params, uri, socket) do
    # Only track paths for authenticated users
    if user = socket.assigns[:current_user] do
      # Extract path from URI
      path = URI.parse(uri).path

      # Skip tracking certain paths (auth pages, etc.)
      unless skip_path?(path) do
        # Save asynchronously to avoid blocking navigation
        Task.start(fn ->
          UserPreferences.set_last_visited_path(user.id, path)
        end)
      end
    end

    {:cont, socket}
  end

  defp skip_path?(path) do
    # Don't track authentication-related paths
    String.starts_with?(path, "/sign-in") or
      String.starts_with?(path, "/register") or
      String.starts_with?(path, "/reset") or
      String.starts_with?(path, "/auth") or
      String.starts_with?(path, "/admin")
  end
end
