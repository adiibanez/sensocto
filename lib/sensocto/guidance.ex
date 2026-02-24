defmodule Sensocto.Guidance do
  use Ash.Domain, otp_app: :sensocto, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sensocto.Guidance.GuidedSession
  end
end
