defmodule VrexServer.Repo.Migrations.CreateWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :asset_bundle_url, :string
      add :thumbnail_url, :string
      add :capacity, :integer, default: 16
      add :is_public, :boolean, default: true
      # Elixir script for world behavior
      add :script, :text
      add :script_enabled, :boolean, default: false
      add :properties, :map, default: %{}
      add :created_by, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:worlds, [:created_by])
    create index(:worlds, [:is_public])
  end
end
