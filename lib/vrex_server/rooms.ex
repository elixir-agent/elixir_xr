defmodule VrexServer.Rooms do
  import Ecto.Query
  alias VrexServer.Repo
  alias VrexServer.Rooms.{Room, RoomPlayer}

  def list_rooms_for_world(world_id) do
    Repo.all(
      from r in Room,
      where: r.world_id == ^world_id and r.status != "closed",
      preload: [:room_players]
    )
  end

  def get_room!(id), do: Repo.get!(Room, id)

  def get_room(id), do: Repo.get(Room, id)

  def create_room(attrs) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  def update_room(room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  def delete_room(room), do: Repo.delete(room)

  def get_player_count(room_id) do
    Repo.aggregate(from(p in RoomPlayer, where: p.room_id == ^room_id), :count, :id)
  end

  def join_room(room_id, user_id, avatar_id \\ nil) do
    attrs = %{room_id: room_id, user_id: user_id, avatar_id: avatar_id}
    %RoomPlayer{}
    |> RoomPlayer.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  def leave_room(room_id, user_id) do
    Repo.delete_all(
      from p in RoomPlayer,
      where: p.room_id == ^room_id and p.user_id == ^user_id
    )
  end

  def update_player_position(room_id, user_id, position, rotation) do
    case Repo.get_by(RoomPlayer, room_id: room_id, user_id: user_id) do
      nil ->
        {:error, :not_found}
      player ->
        player
        |> RoomPlayer.move_changeset(%{position: position, rotation: rotation})
        |> Repo.update()
    end
  end

  def get_room_players(room_id) do
    Repo.all(
      from p in RoomPlayer,
      where: p.room_id == ^room_id,
      preload: [:user, :avatar]
    )
  end
end
