defmodule Sensocto.Accounts do
  use Ash.Domain, otp_app: :sensocto, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sensocto.Accounts.Token
    resource Sensocto.Accounts.User
    resource Sensocto.Accounts.GuestSession
    resource Sensocto.Accounts.UserSkill
    resource Sensocto.Accounts.UserConnection
  end
end
