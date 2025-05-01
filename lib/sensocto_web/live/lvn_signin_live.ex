defmodule SensoctoWeb.Live.LvnSigninLive do
  use SensoctoWeb, :live_view
  use SensoctoNative, :live_view
  # alias Sensocto.Accounts.User
  alias AshAuthentication.Info
  alias AshAuthentication.Strategy

  require Logger

  def mount(params, session, socket) do
    Logger.debug("#{__MODULE__} mount #{inspect(params)}, session: #{inspect(session)}")

    {:ok,
     socket
     |> assign(:form, to_form(%{"email" => "adi.ibanez@freestyleair.com", "token" => ""}))
     |> assign(:token_requested, false)}
  end

  def render(assigns) do
    ~H"""
    <div>HTML lvn signin</div>

    <button phx-click="test">Test</button>

    <.simple_form id="magiclink" for={@form} phx-submit="request_magiclink">
      <.input type="TextField" field={@form[:email]} label="Email" />
      <:actions>
        <.button type="submit">Request Magic link</.button>
      </:actions>
    </.simple_form>

    <.simple_form
      id="tokenentry"
      for={@form}
      phx-trigger-action="true"
      action={~p"/auth/user/magic_link"}
      method="GET"
    >
      <.input type="TextField" name="token" field={@form[:token]} label="Token" />
      <:actions>
        <.button type="submit">Login</.button>
      </:actions>
    </.simple_form>
    """
  end

  def handle_event("test", _params, socket) do
    Logger.debug("test")
    {:noreply, socket}
  end

  @spec handle_event(<<_::136>>, map(), any()) :: {:noreply, any()}
  def handle_event("request_magiclink", %{"email" => email} = params, socket) do
    Logger.debug("handle_event request_magiclink #{inspect(params)}")

    strategy = Info.strategy!(Sensocto.Accounts.User, :magic_link)
    Strategy.action(strategy, :request, %{"email" => email})

    {:noreply,
     socket
     |> assign(:token_requested, true)}
  end

  def terminate(reason, state) do
    Logger.debug("LVN terminated")
  end
end
