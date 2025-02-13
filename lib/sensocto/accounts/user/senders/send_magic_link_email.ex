defmodule Sensocto.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use SensoctoWeb, :verified_routes

  import Swoosh.Email
  alias Sensocto.Mailer

  @impl true
  def send(user_or_email, token, _) do
    # if you get a user, its for a user that already exists.
    # if you get an email, then the user does not yet exist.

    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    email =
      new()
      # TODO: replace with your email
      |> from({"noreply", "hello@adrianibanez.info"})
      |> to(to_string(email))
      |> subject("Your magic login link")
      |> html_body(body(token: token, email: email))
      |> Mailer.deliver!()

    IO.inspect(email)
    email
  end

  # iOS: #{url("sensocto://token=#{params[:token]}")}
  defp body(params) do
    """
    Hello, #{params[:email]}! Click this link to sign in:

    Web: #{url(~p"/auth/user/magic_link/?token=#{params[:token]}")}

    """
  end
end
