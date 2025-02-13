defmodule SensoctoWeb.Controllers.AuthController do
  use SensoctoWeb, :controller
  use AshAuthentication.Phoenix.Controller
  require Logger

  def success(conn, activity, user, token) do
    Logger.debug(
      "authcontroller success #{inspect(activity)} #{inspect(user.id)} #{inspect(token)}"
    )

    return_to = get_session(conn, :return_to) || ~p"/"

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

  def sign_out(conn, params) do
    Logger.debug("authcontroller sign_out #{inspect(params)}")
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session()
    |> redirect(to: return_to)
  end

  # @impl
  # def action(conn, opts) do
  #   Logger.debug("authcontroller action #{inspect(opts)}")
  #   super(conn, opts)
  # end
end
