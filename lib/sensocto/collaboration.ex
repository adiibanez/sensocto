defmodule Sensocto.Collaboration do
  use Ash.Domain, otp_app: :sensocto, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sensocto.Collaboration.Poll
    resource Sensocto.Collaboration.PollOption
    resource Sensocto.Collaboration.Vote
  end
end
