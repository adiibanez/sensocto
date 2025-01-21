defmodule SensoctoWeb.Sensocto.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """

  # https://medium.com/@alvinlindstam/phoenix-presence-for-social-networks-5fb67143f0ad https://github.com/alvinlindstam/phoenix_social_presence/
  use Phoenix.Presence,
    otp_app: :sensocto,
    pubsub_server: Sensocto.PubSub
end
