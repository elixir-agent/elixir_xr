defmodule VrexServer.Avatars do
  import Ecto.Query
  alias VrexServer.Repo
  alias VrexServer.Avatars.Avatar

  def list_public_avatars do
    Repo.all(from a in Avatar, where: a.is_public == true)
  end

  def list_avatars_by_user(user_id) do
    Repo.all(from a in Avatar, where: a.user_id == ^user_id)
  end

  def get_avatar!(id), do: Repo.get!(Avatar, id)

  def get_avatar(id), do: Repo.get(Avatar, id)

  def create_avatar(attrs) do
    %Avatar{}
    |> Avatar.changeset(attrs)
    |> Repo.insert()
  end

  def update_avatar(avatar, attrs) do
    avatar
    |> Avatar.changeset(attrs)
    |> Repo.update()
  end

  def delete_avatar(avatar), do: Repo.delete(avatar)
end
