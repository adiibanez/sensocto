defmodule SensoctoWeb.MagicSignInLive do
  @moduledoc """
  Custom magic link confirmation page with friendly greeting.
  """

  use SensoctoWeb, :live_view
  alias AshAuthentication.Phoenix.Components

  @impl true
  def mount(_params, session, socket) do
    overrides =
      session
      |> Map.get("overrides", [AshAuthentication.Phoenix.Overrides.Default])

    socket =
      socket
      |> assign(overrides: overrides)
      |> assign_new(:otp_app, fn -> nil end)
      |> assign(:current_tenant, session["tenant"])
      |> assign(:context, session["context"] || %{})
      |> assign(:auth_routes_prefix, session["auth_routes_prefix"])
      |> assign(:gettext_fn, session["gettext_fn"])
      |> assign(:strategy, session["strategy"])
      |> assign(:resource, session["resource"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :token, params["token"] || params["magic_link"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh] p-8">
      <div class="text-center mb-8">
        <h1 class="text-3xl font-bold text-white mb-4">Hello, lovely human being!</h1>
        <p class="text-gray-300 text-lg">
          One more click and you're in. Press the button below to complete your sign-in.
        </p>
      </div>

      <.live_component
        module={Components.MagicLink.SignIn}
        otp_app={@otp_app}
        id="magic_sign_in"
        token={@token}
        strategy={@strategy}
        auth_routes_prefix={@auth_routes_prefix}
        overrides={@overrides}
        resource={@resource}
        current_tenant={@current_tenant}
        context={@context}
        gettext_fn={@gettext_fn}
      />
    </div>
    """
  end
end
