defmodule Sensocto.Repo do
  use AshPostgres.Repo, otp_app: :sensocto

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  def installed_extensions do
    # Ash installs some functions that it needs to run the
    # first time you generate migrations.
    ["citext", "ash-functions"]
  end

  # use Ecto.Repo,
  #  otp_app: :sensocto,
  #  adapter: Ecto.Adapters.Postgres
end
