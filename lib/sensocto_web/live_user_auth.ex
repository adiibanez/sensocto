defmodule SensoctoWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use SensoctoWeb, :verified_routes
  require Logger

  alias Sensocto.Accounts.UserPreferences

  def on_mount(:live_user_optional, _params, session, socket) do
    cond do
      socket.assigns[:current_user] ->
        {:cont, socket}

      session["is_guest"] == true ->
        # Load guest user from the in-memory store
        guest_id = session["guest_id"]

        case Sensocto.Accounts.GuestUserStore.get_guest(guest_id) do
          {:ok, guest} ->
            Sensocto.Accounts.GuestUserStore.touch_guest(guest_id)
            {:cont, assign(socket, :current_user, guest)}

          {:error, :not_found} ->
            {:cont, assign(socket, :current_user, nil)}
        end

      true ->
        {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, params, session, socket) do
    cond do
      socket.assigns[:current_user] ->
        {:cont, socket}

      session["is_guest"] == true ->
        # Load guest user from the in-memory store
        guest_id = session["guest_id"]

        case Sensocto.Accounts.GuestUserStore.get_guest(guest_id) do
          {:ok, guest} ->
            # Touch guest to update last_active
            Sensocto.Accounts.GuestUserStore.touch_guest(guest_id)
            {:cont, assign(socket, :current_user, guest)}

          {:error, :not_found} ->
            Logger.debug("Guest session expired or invalid: #{inspect(guest_id)}")
            {:halt, Phoenix.LiveView.redirect(socket, to: get_sign_from_params(params))}
        end

      true ->
        Logger.debug(
          "live_user_required: socket assigns: #{inspect(socket.assigns)} params: #{inspect(params)} session:#{inspect(session)}"
        )

        {:halt, Phoenix.LiveView.redirect(socket, to: get_sign_from_params(params))}
    end
  end

  def on_mount(:live_no_user, params, session, socket) do
    Logger.debug(
      "live_no_user: socket assigns: #{inspect(socket.assigns)} params: #{inspect(params)} session:#{inspect(session)}"
    )

    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  @doc """
  Gets the last visited path for a user, if available.
  Used to redirect users back to where they were after login.
  """
  def get_last_visited_path(user_id) when is_binary(user_id) do
    UserPreferences.get_last_visited_path(user_id)
  end

  def get_last_visited_path(_), do: nil

  defp get_sign_from_params(params) do
    Logger.debug("get_sign_in_path_from_params params: #{inspect(params)}")

    case Map.has_key?(params, "_format") do
      true -> ~p"/lvn-signin"
      _ -> ~p"/sign-in"
    end
  end
end
