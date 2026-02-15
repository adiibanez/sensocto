defmodule Sensocto.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
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
    |> subject("Confirm your email address")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    """
    Click this link to confirm your email:

    #{url(~p"/auth/user/confirm_new_user?#{[confirm: params[:token]]}")}
    """
  end
end
