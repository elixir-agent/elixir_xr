defmodule VrexServer.Rooms.RoomPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "room_players" do
    field :position, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
    field :rotation, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0, "w" => 1.0}
    field :joined_at, :utc_datetime

    belongs_to :room, VrexServer.Rooms.Room
    belongs_to :user, VrexServer.Accounts.User
    belongs_to :avatar, VrexServer.Avatars.Avatar

    timestamps(updated_at: false)
  end

  def changeset(room_player, attrs) do
    room_player
    |> cast(attrs, [:room_id, :user_id, :avatar_id, :position, :rotation, :joined_at])
    |> validate_required([:room_id, :user_id])
    |> unique_constraint([:room_id, :user_id])
    |> put_joined_at()
  end

  def move_changeset(room_player, attrs) do
    cast(room_player, attrs, [:position, :rotation])
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
