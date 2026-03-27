defmodule VrexServer.Worlds.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "items" do
    field :name, :string
    field :asset_url, :string
    field :thumbnail_url, :string
    field :position, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
    field :rotation, :map, default: %{"x" => 0.0, "y" => 0.0, "z" => 0.0, "w" => 1.0}
    field :scale, :map, default: %{"x" => 1.0, "y" => 1.0, "z" => 1.0}
    field :asset_format, :string, default: "glb"
    field :collider_enabled, :boolean, default: true
    field :script, :string
    field :script_enabled, :boolean, default: false
    field :properties, :map, default: %{}
    field :media, :map, default: %{}

    belongs_to :world, VrexServer.Worlds.World

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :asset_url, :asset_format, :collider_enabled, :thumbnail_url,
                    :position, :rotation, :scale,
                    :script, :script_enabled, :properties, :media, :world_id])
    |> validate_required([:name, :world_id])
    |> validate_length(:name, min: 1, max: 128)
  end
end
