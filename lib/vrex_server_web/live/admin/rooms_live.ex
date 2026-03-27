defmodule VrexServerWeb.Admin.RoomsLive do
  use VrexServerWeb, :live_view
  import Ecto.Query
  alias VrexServer.{Repo, Rooms, Rooms.Room, Rooms.RoomPlayer}

  @refresh_ms 3_000

  @impl true
  def mount(_params, session, socket) do
    admin = load_admin(session)
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:page_title, "ルームモニター · Vrex Admin")
     |> assign(:active_nav, :rooms)
     |> assign(:current_admin, admin)
     |> assign(:rooms, list_rooms_with_players())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign(socket, :rooms, list_rooms_with_players())}
  end

  @impl true
  def handle_event("close_room", %{"id" => id}, socket) do
    room = Rooms.get_room!(id)
    {:ok, _} = Rooms.update_room(room, %{status: "closed"})
    {:noreply,
     socket
     |> put_flash(:info, "ルームをクローズしました")
     |> assign(:rooms, list_rooms_with_players())}
  end

  def handle_event("kick_player", %{"room_id" => room_id, "user_id" => user_id}, socket) do
    Rooms.leave_room(room_id, user_id)
    # WebSocket 経由でプレイヤーに通知
    VrexServerWeb.Endpoint.broadcast("room:#{room_id}", "kicked", %{user_id: user_id})
    {:noreply,
     socket
     |> put_flash(:info, "プレイヤーをキックしました")
     |> assign(:rooms, list_rooms_with_players())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:24px;">
      <h2 style="font-size:1.4rem; font-weight:700;">
        <span class="live-dot"></span>ルームモニター (リアルタイム)
      </h2>
      <span style="color:#888; font-size:.875rem;">
        {@rooms |> Enum.count(& &1.status == "open")} / {length(@rooms)} オープン
      </span>
    </div>

    <%= if Enum.empty?(@rooms) do %>
      <div class="card" style="padding:48px; text-align:center; color:#888;">
        現在アクティブなルームはありません
      </div>
    <% end %>

    <%= for room <- @rooms do %>
      <div class="card" style="margin-bottom:16px;">
        <div class="card-header">
          <div style="display:flex; align-items:center; gap:12px;">
            <span class="card-title">
              {room.name || "Room #{String.slice(room.id, 0, 8)}"}
            </span>
            <span class={"badge #{status_badge(room.status)}"}>
              {room.status}
            </span>
            <span style="color:#888; font-size:.8rem;">
              🌍 {room.world && room.world.name || "不明"}
            </span>
          </div>
          <div style="display:flex; align-items:center; gap:10px;">
            <span class={"badge #{player_badge(length(room.players), room.max_players)}"}>
              👥 {length(room.players)} / {room.max_players}
            </span>
            <%= if room.status == "open" do %>
              <button
                class="btn btn-danger"
                phx-click="close_room"
                phx-value-id={room.id}
                style="font-size:.75rem; padding:5px 10px;"
                data-confirm="このルームをクローズしますか？"
              >
                クローズ
              </button>
            <% end %>
          </div>
        </div>

        <%= if not Enum.empty?(room.players) do %>
          <div class="card-body">
            <table>
              <thead>
                <tr>
                  <th>プレイヤー</th>
                  <th>位置 (X, Y, Z)</th>
                  <th>アバター</th>
                  <th>参加時刻</th>
                  <th>操作</th>
                </tr>
              </thead>
              <tbody>
                <%= for player <- room.players do %>
                  <tr>
                    <td>
                      <div style="font-weight:600;">{player.user && (player.user.display_name || player.user.username) || "—"}</div>
                      <div style="color:#888; font-size:.78rem;">{player.user_id |> String.slice(0, 8)}</div>
                    </td>
                    <td style="font-family:monospace; font-size:.8rem; color:#888;">
                      <%= if player.position do %>
                        {Float.round(player.position["x"] || 0.0, 1)},
                        {Float.round(player.position["y"] || 0.0, 1)},
                        {Float.round(player.position["z"] || 0.0, 1)}
                      <% else %>
                        —
                      <% end %>
                    </td>
                    <td>
                      <%= if player.avatar_id do %>
                        <span class="badge badge-green">あり</span>
                      <% else %>
                        <span style="color:#888; font-size:.8rem;">なし</span>
                      <% end %>
                    </td>
                    <td style="color:#888; font-size:.8rem;">
                      {player.joined_at && Calendar.strftime(player.joined_at, "%H:%M:%S") || "—"}
                    </td>
                    <td>
                      <button
                        class="btn btn-danger"
                        phx-click="kick_player"
                        phx-value-room-id={room.id}
                        phx-value-user-id={player.user_id}
                        style="font-size:.72rem; padding:4px 8px;"
                        data-confirm="このプレイヤーをキックしますか？"
                      >
                        キック
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>

        <div style="padding:10px 16px; border-top:1px solid #2a2a4a; display:flex; gap:16px; font-size:.78rem; color:#888;">
          <span>ID: {room.id}</span>
          <span>作成: {Calendar.strftime(room.inserted_at, "%Y/%m/%d %H:%M")}</span>
          <%= if room.is_private do %>
            <span class="badge badge-yellow">🔒 プライベート</span>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp list_rooms_with_players do
    rooms = Repo.all(
      from r in Room,
      order_by: [desc: r.inserted_at],
      preload: [:world]
    )

    Enum.map(rooms, fn room ->
      players =
        Repo.all(
          from p in RoomPlayer,
          where: p.room_id == ^room.id,
          preload: [:user, :avatar]
        )
      Map.put(room, :players, players)
    end)
  end

  defp status_badge("open"),   do: "badge-green"
  defp status_badge("full"),   do: "badge-yellow"
  defp status_badge("closed"), do: "badge-red"
  defp status_badge(_),        do: "badge-gray"

  defp player_badge(count, max) when count >= max, do: "badge-red"
  defp player_badge(count, max) when count >= div(max, 2), do: "badge-yellow"
  defp player_badge(_, _), do: "badge-green"

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp load_admin(%{"admin_user_id" => id}), do: VrexServer.Accounts.get_user(id)
  defp load_admin(_), do: nil
end
