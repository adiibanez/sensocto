defmodule SensoctoWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use SensoctoWeb, :verified_routes
  require Logger

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, params, session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      Logger.debug(
        "live_user_required: #{inspect(socket.assigns)} #{inspect(params)} #{inspect(session)}"
      )

      {:halt, Phoenix.LiveView.redirect(socket, to: get_sign_from_params(params))}
    end
  end

  def on_mount(:live_no_user, params, session, socket) do
    Logger.debug(
      "live_no_user: #{inspect(socket.assigns)} #{inspect(params)} #{inspect(session)}"
    )

    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  defp get_sign_from_params(params) do
    Logger.debug("get_sign_in_path_from_params #{inspect(params)}")

    case Map.has_key?(params, "_format") do
      true -> ~p"/lvn-signin"
      _ -> ~p"/sign-in"
    end
  end
end
