defmodule VrexServer.Worlds.World do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "worlds" do
    field :name, :string
    field :description, :string
    field :asset_bundle_url, :string
    field :thumbnail_url, :string
    field :capacity, :integer, default: 16
    field :is_public, :boolean, default: true
    field :script, :string
    field :script_enabled, :boolean, default: false
    field :properties, :map, default: %{}
    field :media, :map, default: %{}

    belongs_to :creator, VrexServer.Accounts.User, foreign_key: :created_by
    has_many :items, VrexServer.Worlds.Item
    has_many :rooms, VrexServer.Rooms.Room

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :description, :asset_bundle_url, :thumbnail_url, :capacity,
                    :is_public, :script, :script_enabled, :properties, :media, :created_by])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 128)
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 100)
  end
end
