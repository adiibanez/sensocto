defmodule Sensocto.Repo.Migrations.AddConnectorsTable do
  @moduledoc """
  Updates the connectors table to support persistent storage.
  Adds connected_at column and indexes.
  """

  use Ecto.Migration

  def up do
    alter table(:connectors) do
      add_if_not_exists :connected_at, :utc_datetime_usec
    end

    create_if_not_exists index(:connectors, [:user_id])
    create_if_not_exists index(:connectors, [:status])
  end

  def down do
    drop_if_exists index(:connectors, [:status])
    drop_if_exists index(:connectors, [:user_id])

    alter table(:connectors) do
      remove_if_exists :connected_at, :utc_datetime_usec
    end
  end
end
