defmodule VrexServer.Repo.Migrations.AddMediaToWorldsAndItems do
  use Ecto.Migration

  def change do
    alter table(:worlds) do
      add :media, :map, default: %{}
    end

    alter table(:items) do
      add :media, :map, default: %{}
    end
  end
end
