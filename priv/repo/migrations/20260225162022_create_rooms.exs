defmodule VrexServer.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :is_private, :boolean, default: false
      add :password_hash, :string
      add :max_players, :integer, default: 16
      add :status, :string, default: "open"
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:rooms, [:world_id])
    create index(:rooms, [:owner_id])
    create index(:rooms, [:status])

    create table(:room_players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :avatar_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :position, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
      add :rotation, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0, "w" => 1.0}
      add :joined_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:room_players, [:room_id])
    create unique_index(:room_players, [:room_id, :user_id])
  end
end
