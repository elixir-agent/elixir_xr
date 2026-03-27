defmodule VrexServer.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :asset_url, :string
      add :thumbnail_url, :string
      # 3D transform
      add :position, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
      add :rotation, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0, "w" => 1.0}
      add :scale, :map, default: %{"x" => 1.0, "y" => 1.0, "z" => 1.0}
      # Elixir script for item interaction
      add :script, :text
      add :script_enabled, :boolean, default: false
      add :properties, :map, default: %{}
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create index(:items, [:world_id])
  end
end
