defmodule VrexServer.Avatars.Avatar do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "avatars" do
    field :name, :string
    field :vrm_url, :string
    field :thumbnail_url, :string
    field :is_public, :boolean, default: false
    field :customization, :map, default: %{}

    belongs_to :user, VrexServer.Accounts.User

    timestamps()
  end

  def changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:name, :vrm_url, :thumbnail_url, :is_public, :customization, :user_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 128)
  end
end
