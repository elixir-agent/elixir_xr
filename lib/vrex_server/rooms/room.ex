defmodule VrexServer.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rooms" do
    field :name, :string
    field :is_private, :boolean, default: false
    field :password_hash, :string
    field :password, :string, virtual: true
    field :max_players, :integer, default: 16
    field :status, :string, default: "open"

    belongs_to :world, VrexServer.Worlds.World
    belongs_to :owner, VrexServer.Accounts.User, foreign_key: :owner_id
    has_many :room_players, VrexServer.Rooms.RoomPlayer

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :world_id, :is_private, :password, :max_players, :status, :owner_id])
    |> validate_required([:world_id])
    |> validate_number(:max_players, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:status, ["open", "closed", "full"])
    |> maybe_hash_password()
  end

  defp maybe_hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end
end
