defmodule Sensocto.Repo do
  @moduledoc """
  Primary repository for Sensocto, configured for Neon.tech PostgreSQL.

  This repo handles all write operations and can be used for reads.
  For read-heavy operations, consider using `Sensocto.Repo.Replica`.
  """
  use AshPostgres.Repo, otp_app: :sensocto

  def min_pg_version do
    # Neon.tech supports PostgreSQL 14, 15, 16, and 17
    %Version{major: 16, minor: 0, patch: 0}
  end

  def installed_extensions do
    # Ash installs some functions that it needs to run the
    # first time you generate migrations.
    ["citext", "ash-functions"]
  end

  @doc """
  Returns the read replica repo for read-heavy operations.
  Falls back to the primary repo if replica is not configured.
  """
  def replica do
    if Application.get_env(:sensocto, Sensocto.Repo.Replica) do
      Sensocto.Repo.Replica
    else
      __MODULE__
    end
  end
end

defmodule Sensocto.Repo.Replica do
  @moduledoc """
  Read replica repository for Sensocto.

  This repo is read-only and should be used for read-heavy operations
  to offload the primary database. Connects to Neon's read replica endpoint.

  In development/test, this typically points to the same database as primary.
  In production, configure `DATABASE_REPLICA_URL` to point to Neon's read replica.
  """
  use AshPostgres.Repo,
    otp_app: :sensocto,
    read_only: true

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  def installed_extensions do
    ["citext", "ash-functions"]
  end
end
