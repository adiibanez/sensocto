defmodule SensoctoWeb.GuestAuthController do
  @moduledoc """
  Handles guest user authentication.
  Creates temporary in-memory sessions without database persistence.
  """
  use SensoctoWeb, :controller
  require Logger

  alias Sensocto.Accounts.GuestUserStore

  def sign_in(conn, %{"guest_id" => guest_id, "token" => token}) do
    case GuestUserStore.get_guest(guest_id) do
      {:ok, guest} ->
        if Plug.Crypto.secure_compare(guest.token, token) do
          # Valid guest, create session
          conn
          |> put_session(:guest_id, guest_id)
          |> put_session(:guest_token, token)
          |> put_session(:is_guest, true)
          |> put_flash(
            :info,
            "Welcome, #{guest.display_name}! You're browsing as a guest (in-memory session only)."
          )
          |> redirect(to: ~p"/lobby")
        else
          conn
          |> put_flash(:error, "Invalid guest token")
          |> redirect(to: ~p"/sign-in")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Guest session not found or expired")
        |> redirect(to: ~p"/sign-in")
    end
  end
end
