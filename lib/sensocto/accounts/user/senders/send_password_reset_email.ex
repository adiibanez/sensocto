defmodule Sensocto.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use SensoctoWeb, :verified_routes

  import Swoosh.Email

  alias Sensocto.Mailer

  @impl true
  def send(user, token, _) do
    new()
    |> from(Application.get_env(:sensocto, :mailer_from))
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    """
    Click this link to reset your password:

    #{url(~p"/password-reset/#{params[:token]}")}
    """
  end
end
