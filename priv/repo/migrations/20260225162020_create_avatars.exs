defmodule VrexServer.Repo.Migrations.CreateAvatars do
  use Ecto.Migration

  def change do
    create table(:avatars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :vrm_url, :string
      add :thumbnail_url, :string
      add :is_public, :boolean, default: false
      # JSON customization: colors, accessories, scale, etc.
      add :customization, :map, default: %{}
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create index(:avatars, [:user_id])
    create index(:avatars, [:is_public])
  end
end
