defmodule VrexServer.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :display_name, :string
    field :avatar_id, :binary_id
    field :is_admin, :boolean, default: false
    field :password, :string, virtual: true

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password, :display_name])
    |> validate_required([:username, :email, :password])
    |> validate_length(:username, min: 3, max: 32)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:password, min: 8)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> hash_password()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :avatar_id, :is_admin])
    |> validate_length(:display_name, max: 64)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end
end
