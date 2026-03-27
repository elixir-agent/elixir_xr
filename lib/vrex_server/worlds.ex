defmodule VrexServer.Worlds do
  import Ecto.Query
  alias VrexServer.Repo
  alias VrexServer.Worlds.{World, Item}

  def list_public_worlds do
    Repo.all(from w in World, where: w.is_public == true, order_by: [desc: w.inserted_at])
  end

  def list_worlds_by_user(user_id) do
    Repo.all(from w in World, where: w.created_by == ^user_id)
  end

  def get_world!(id), do: Repo.get!(World, id)

  def get_world(id), do: Repo.get(World, id)

  def create_world(attrs) do
    %World{}
    |> World.changeset(attrs)
    |> Repo.insert()
  end

  def update_world(world, attrs) do
    world
    |> World.changeset(attrs)
    |> Repo.update()
  end

  def delete_world(world), do: Repo.delete(world)

  def list_items(world_id) do
    Repo.all(from i in Item, where: i.world_id == ^world_id)
  end

  def get_item!(id), do: Repo.get!(Item, id)

  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def update_item(item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  def delete_item(item), do: Repo.delete(item)
end
