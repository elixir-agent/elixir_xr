defmodule VrexServerWeb.RoomChannel do
  use Phoenix.Channel
  alias VrexServer.{Rooms, Worlds, Scripting}

  @impl true
  def join("room:" <> room_id, params, socket) do
    avatar_id = Map.get(params, "avatar_id")
    user = socket.assigns.current_user

    case Rooms.get_room(room_id) do
      nil ->
        {:error, %{reason: "room_not_found"}}

      room ->
        case Rooms.join_room(room_id, user.id, avatar_id) do
          {:ok, _player} ->
            send(self(), {:after_join, room, avatar_id})
            socket = socket |> assign(:room_id, room_id) |> assign(:room, room)
            {:ok, %{room_id: room_id}, socket}

          {:error, reason} ->
            {:error, %{reason: inspect(reason)}}
        end
    end
  end

  @impl true
  def handle_info({:after_join, room, avatar_id}, socket) do
    user = socket.assigns.current_user

    # Notify others that a player joined
    broadcast!(socket, "player_joined", %{
      user_id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar_id: avatar_id
    })

    # Send current player list to the new player
    players = Rooms.get_room_players(room.id)
    push(socket, "room_state", %{
      players: Enum.map(players, &format_player/1),
      world_id: room.world_id
    })

    # Run world's on_join script if enabled
    world = Worlds.get_world!(room.world_id)
    if world.script_enabled && world.script do
      Scripting.run_event(world.script, :on_player_join, %{
        user_id: user.id,
        room_id: room.id
      })
    end

    {:noreply, socket}
  end

  # Player movement - broadcast position to all others in room
  @impl true
  def handle_in("move", %{"position" => pos, "rotation" => rot}, socket) do
    user = socket.assigns.current_user
    room_id = socket.assigns.room_id

    Rooms.update_player_position(room_id, user.id, pos, rot)

    broadcast_from!(socket, "player_moved", %{
      user_id: user.id,
      position: pos,
      rotation: rot
    })

    {:noreply, socket}
  end

  # Avatar state (expressions, blendshapes, hand gestures)
  def handle_in("avatar_state", payload, socket) do
    user = socket.assigns.current_user

    broadcast_from!(socket, "avatar_state", Map.put(payload, "user_id", user.id))
    {:noreply, socket}
  end

  # Text chat
  def handle_in("chat", %{"message" => message}, socket) do
    user = socket.assigns.current_user

    broadcast!(socket, "chat_message", %{
      user_id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      message: String.slice(message, 0, 500)
    })

    {:noreply, socket}
  end

  # Item interaction - triggers Elixir script
  def handle_in("interact", %{"item_id" => item_id} = payload, socket) do
    user = socket.assigns.current_user
    item = Worlds.get_item!(item_id)

    response =
      if item.script_enabled && item.script do
        case Scripting.run_event(item.script, :on_interact, %{
          user_id: user.id,
          item_id: item_id,
          data: Map.get(payload, "data", %{})
        }) do
          {:ok, result} -> result
          {:error, _} -> %{}
        end
      else
        %{}
      end

    broadcast!(socket, "item_interacted", %{
      item_id: item_id,
      user_id: user.id,
      response: response
    })

    {:reply, {:ok, response}, socket}
  end

  # Voice signaling (WebRTC offer/answer/ice)
  def handle_in("voice_signal", %{"target_id" => target_id} = payload, socket) do
    user = socket.assigns.current_user

    VrexServerWeb.Endpoint.broadcast(
      "user_socket:#{target_id}",
      "voice_signal",
      Map.put(payload, "from_id", user.id)
    )

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    user = socket.assigns[:current_user]
    room_id = socket.assigns[:room_id]

    if user && room_id do
      Rooms.leave_room(room_id, user.id)
      broadcast!(socket, "player_left", %{user_id: user.id})
    end

    :ok
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
end
