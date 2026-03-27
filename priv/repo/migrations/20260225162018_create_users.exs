defmodule VrexServer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :display_name, :string
      add :avatar_id, :binary_id
      add :is_admin, :boolean, default: false

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    create table(:user_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :context, :string, null: false
      add :expires_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:user_tokens, [:user_id])
    create unique_index(:user_tokens, [:token])
  end
end
