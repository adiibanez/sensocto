defmodule SensoctoWeb.Controllers.AuthController do
  use SensoctoWeb, :controller
  use AshAuthentication.Phoenix.Controller
  require Logger

  alias Sensocto.Accounts.GuestUserStore

  def success(conn, activity, user, token) do
    session_return_to = get_session(conn, :return_to)
    return_to = session_return_to || get_root_return_to_from_params(conn)

    Logger.debug(
      "authcontroller success activity: #{inspect(activity)} user.id: #{inspect(user.id)} token: #{inspect(token)}"
    )

    # Logger.debug(
    #   "authcontroller session_return_to: #{inspect(session_return_to)} return_to: #{inspect(return_to)}"
    # )

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    Logger.debug("authcontroller failure #{inspect(activity)} #{inspect(reason)}")

    conn
    |> put_flash(:error, "Incorrect email or password")
    |> redirect(to: get_redirect_from_params(conn))
  end

  def get_redirect_from_params(conn) do
    Logger.debug("get_redirect_from_params: #{inspect(conn.params)}")

    case Map.has_key?(conn.params, :_format) do
      true ->
        ~p"/lvn-signin"

      _ ->
        ~p"/sign-in"
    end
  end

  def get_root_return_to_from_params(conn) do
    Logger.debug("get_redirect_from_params: #{inspect(conn.params)}")

    case Map.has_key?(conn.params, :_format) do
      true ->
        ~p"/lvn"

      _ ->
        ~p"/"
    end
  end

  def sign_out(conn, params) do
    Logger.debug("authcontroller sign_out #{inspect(params)}")

    # If this is a guest user, remove their persisted session from database
    case get_session(conn, :guest_id) do
      nil ->
        :ok

      guest_id ->
        Logger.info("Removing guest session on logout: #{guest_id}")
        GuestUserStore.remove_guest(guest_id)
    end

    conn
    |> clear_session(:sensocto)
    |> AshAuthentication.Strategy.RememberMe.Plug.Helpers.delete_all_remember_me_cookies(
      :sensocto
    )
    |> redirect(to: ~p"/sign-in")
  end

  # @impl
  # def action(conn, opts) do
  #   Logger.debug("authcontroller action #{inspect(opts)}")
  #   super(conn, opts)
  # end
end
