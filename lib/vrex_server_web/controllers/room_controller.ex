defmodule VrexServerWeb.RoomController do
  use VrexServerWeb, :controller
  alias VrexServer.Rooms

  def index(conn, %{"world_id" => world_id}) do
    rooms = Rooms.list_rooms_for_world(world_id)
    json(conn, %{rooms: Enum.map(rooms, &format_room/1)})
  end

  def show(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)
    players = Rooms.get_room_players(room.id)
    json(conn, %{room: format_room(room), players: Enum.map(players, &format_player/1)})
  end

  def create(conn, params) do
    attrs = Map.put(params, "owner_id", conn.assigns.current_user.id)

    case Rooms.create_room(attrs) do
      {:ok, room} ->
        conn
        |> put_status(:created)
        |> json(%{room: format_room(room)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)

    if room.owner_id == conn.assigns.current_user.id || conn.assigns.current_user.is_admin do
      Rooms.delete_room(room)
      send_resp(conn, :no_content, "")
    else
      conn |> put_status(:forbidden) |> json(%{error: "権限がありません"})
    end
  end

  defp format_room(room) do
    %{
      id: room.id,
      name: room.name,
      world_id: room.world_id,
      is_private: room.is_private,
      max_players: room.max_players,
      status: room.status,
      player_count: length(room.room_players || [])
    }
  end

  defp format_player(player) do
    %{
      user_id: player.user_id,
      username: player.user && player.user.username,
      display_name: player.user && (player.user.display_name || player.user.username),
      avatar_id: player.avatar_id,
      position: player.position,
      rotation: player.rotation
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
