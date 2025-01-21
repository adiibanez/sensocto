defmodule Sensocto.Repo do
  use AshPostgres.Repo, otp_app: :sensocto

  def installed_extensions do
    # Ash installs some functions that it needs to run the
    # first time you generate migrations.
    ["citext", "ash-functions"]
  end

  # use Ecto.Repo,
  #  otp_app: :sensocto,
  #  adapter: Ecto.Adapters.Postgres
end
