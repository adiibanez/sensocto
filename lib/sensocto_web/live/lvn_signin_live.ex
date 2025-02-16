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
    """
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
end
