defmodule SensoctoWeb.LvnController do
  use SensoctoWeb, :controller
  use AshAuthentication.Phoenix.Controller
  require Logger
  alias AshAuthentication.Info
  alias AshAuthentication.Strategy
  # alias AshAuthentication.Plug
  alias Plug.Conn

  def checkauth(conn, _params) do
    # user = get_session(conn, :user)
    user = conn.assigns.current_user

    Logger.info("lvn check_auth #{inspect(user)}")

    if user != nil do
      Logger.info("lvn check_auth got user #{inspect(user.id)}")
      redirect(conn, to: "/lvn") |> halt()
    else
      Logger.info("lvn check_auth no user available")
      # text(conn, "<Text>No user available #{inspect(conn)}</Text>")
      redirect(conn, to: "/lvn-signin")
    end
  end

  def authenticate(conn, %{"token" => token} = params) do
    Logger.debug("lvn authenticate token: #{token} #{inspect(params)}")

    strategy = AshAuthentication.Info.strategy!(Sensocto.Accounts.User, :magic_link)

    # # conn = conn(:get, "/user/magic_link", %{"token" => token})
    # conn = Strategy.plug(strategy, :sign_in, conn)
    # {_conn, {:ok, signed_in_user}} = Plug.Helpers.get_authentication_result(conn)

    # Logger.debug("lvn auth OK stragegy user: #{inspect(signed_in_user.id)}")

    # # signed_in_user.id == user.id

    # conn

    case Strategy.action(strategy, :sign_in, %{"token" => token}) do
      {:ok, user} ->
        Logger.debug("lvn auth OK stragegy conn status: #{conn.status} user: #{inspect(user.id)}")

        # return_to = get_session(conn, :return_to) || ~p"/"
        return_to = ~p"/lvn"

        conn
        |> delete_session(:return_to)
        |> store_in_session(user)
        |> assign(:current_user, user)
        |> Conn.put_resp_header("location", return_to)
        |> Conn.send_resp(302, "Redirect")
        |> halt()

      # |> redirect(to: return_to)

      _ ->
        Logger.debug("lvn auth NOK")

        conn
        # |> redirect(to: "/lvn-signin")
        |> Conn.put_resp_header("location", ~p"/lvn-signin")
        |> Conn.send_resp(302, "Redirect")
    end
  end
end
