defmodule VrexServerWeb.Admin.DashboardLive do
  use VrexServerWeb, :live_view
  import Ecto.Query
  alias VrexServer.{Repo, Accounts.User, Worlds.World, Worlds.Item, Rooms.Room, Rooms.RoomPlayer}

  @refresh_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    admin = load_admin(session)
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:page_title, "ダッシュボード · Vrex Admin")
     |> assign(:active_nav, :dashboard)
     |> assign(:current_admin, admin)
     |> assign_stats()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign_stats(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2 style="font-size:1.4rem; font-weight:700; margin-bottom:24px; color:#00e676; font-family:'Courier New',monospace; letter-spacing:.08em; text-shadow:0 0 12px rgba(0,230,118,.5);">// ダッシュボード</h2>

    <!-- 統計カード: 2行 3列 -->
    <div style="display:grid; grid-template-columns:repeat(3,1fr); gap:16px; margin-bottom:28px;">
      <div class="stat-card">
        <div class="stat-label">総ユーザー</div>
        <div class="stat-value" style="color:#00e676">{@stats.user_count}</div>
        <div class="stat-sub">登録アカウント数</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">ワールド数</div>
        <div class="stat-value" style="color:#69ff47">{@stats.world_count}</div>
        <div class="stat-sub">公開 {@stats.public_world_count} / 非公開 {@stats.private_world_count}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">アイテム数</div>
        <div class="stat-value" style="color:#26f5d8">{@stats.item_count}</div>
        <div class="stat-sub">スクリプト有効 {@stats.scripted_item_count} 件</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">アクティブルーム</div>
        <div class="stat-value" style="color:#f59e0b">{@stats.active_room_count}</div>
        <div class="stat-sub">現在オープン中</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">接続中プレイヤー</div>
        <div class="stat-value" style="color:#ef4444">{@stats.player_count}</div>
        <div class="stat-sub">リアルタイム</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">スクリプト有効ワールド</div>
        <div class="stat-value" style="color:#b9f6ca">{@stats.scripted_world_count}</div>
        <div class="stat-sub">Elixir スクリプト実行中</div>
      </div>
    </div>

    <div style="display:grid; grid-template-columns:1fr 1fr; gap:20px; margin-bottom:20px;">
      <!-- 最近のユーザー -->
      <div class="card">
        <div class="card-header">
          <span class="card-title">最近のユーザー</span>
          <a href="/admin/users" class="btn btn-ghost">一覧</a>
        </div>
        <div class="card-body">
          <table>
            <thead>
              <tr>
                <th>ユーザー名</th>
                <th>メール</th>
                <th>登録日</th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- @stats.recent_users do %>
                <tr>
                  <td>
                    <%= if user.is_admin do %>
                      <span class="badge badge-purple" style="margin-right:6px">Admin</span>
                    <% end %>
                    {user.display_name || user.username}
                  </td>
                  <td style="color:#888">{user.email}</td>
                  <td style="color:#888">{Calendar.strftime(user.inserted_at, "%m/%d")}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <!-- アクティブルーム -->
      <div class="card">
        <div class="card-header">
          <span class="card-title">アクティブルーム</span>
          <a href="/admin/rooms" class="btn btn-ghost">モニター</a>
        </div>
        <div class="card-body">
          <table>
            <thead>
              <tr>
                <th>ルーム</th>
                <th>ワールド</th>
                <th>プレイヤー</th>
              </tr>
            </thead>
            <tbody>
              <%= for room <- @stats.active_rooms do %>
                <tr>
                  <td>{room.name || "Room #{String.slice(room.id, 0, 6)}"}</td>
                  <td style="color:#888">{room.world && room.world.name}</td>
                  <td>
                    <span class={"badge #{if room.player_count >= room.max_players, do: "badge-red", else: "badge-green"}"}>
                      {room.player_count}/{room.max_players}
                    </span>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@stats.active_rooms) do %>
                <tr><td colspan="3" style="color:#888; text-align:center; padding:20px;">アクティブルームなし</td></tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- ワールド別アイテム内訳 -->
    <div class="card">
      <div class="card-header">
        <span class="card-title">ワールド別アイテム</span>
        <a href="/admin/worlds" class="btn btn-ghost">ワールド管理</a>
      </div>
      <div class="card-body">
        <table>
          <thead>
            <tr>
              <th>ワールド</th>
              <th>公開</th>
              <th>容量</th>
              <th>アイテム数</th>
              <th>スクリプト</th>
            </tr>
          </thead>
          <tbody>
            <%= for w <- @stats.worlds_with_items do %>
              <tr>
                <td>
                  <div style="font-weight:600">{w.name}</div>
                  <%= if w.description do %>
                    <div style="color:#888; font-size:.78rem;">{String.slice(w.description, 0, 40)}</div>
                  <% end %>
                </td>
                <td>
                  <span class={"badge #{if w.is_public, do: "badge-green", else: "badge-gray"}"}>
                    {if w.is_public, do: "公開", else: "非公開"}
                  </span>
                </td>
                <td style="color:#888">{w.capacity} 人</td>
                <td>
                  <span class="badge badge-purple">{w.item_count} 件</span>
                </td>
                <td>
                  <span class={"badge #{if w.script_enabled, do: "badge-purple", else: "badge-gray"}"}>
                    {if w.script_enabled, do: "✓ 有効", else: "無効"}
                  </span>
                </td>
              </tr>
            <% end %>
            <%= if Enum.empty?(@stats.worlds_with_items) do %>
              <tr><td colspan="5" style="color:#888; text-align:center; padding:20px;">ワールドがありません</td></tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp assign_stats(socket) do
    user_count   = Repo.aggregate(User, :count, :id)
    world_count  = Repo.aggregate(World, :count, :id)
    public_count = Repo.aggregate(from(w in World, where: w.is_public == true), :count, :id)
    scripted_world_count = Repo.aggregate(from(w in World, where: w.script_enabled == true), :count, :id)
    item_count   = Repo.aggregate(Item, :count, :id)
    scripted_item_count = Repo.aggregate(from(i in Item, where: i.script_enabled == true), :count, :id)
    room_count   = Repo.aggregate(from(r in Room, where: r.status == "open"), :count, :id)
    player_count = Repo.aggregate(RoomPlayer, :count, :id)

    recent_users =
      Repo.all(from u in User, order_by: [desc: u.inserted_at], limit: 5)

    active_rooms =
      Repo.all(from r in Room, where: r.status == "open", preload: [:world], limit: 5)
      |> Enum.map(fn room ->
        count = Repo.aggregate(from(p in RoomPlayer, where: p.room_id == ^room.id), :count, :id)
        Map.put(room, :player_count, count)
      end)

    # ワールド別アイテム数
    worlds_with_items =
      Repo.all(from w in World, order_by: [desc: w.inserted_at])
      |> Enum.map(fn world ->
        count = Repo.aggregate(from(i in Item, where: i.world_id == ^world.id), :count, :id)
        Map.put(world, :item_count, count)
      end)

    assign(socket,
      stats: %{
        user_count:           user_count,
        world_count:          world_count,
        public_world_count:   public_count,
        private_world_count:  world_count - public_count,
        scripted_world_count: scripted_world_count,
        item_count:           item_count,
        scripted_item_count:  scripted_item_count,
        active_room_count:    room_count,
        player_count:         player_count,
        recent_users:         recent_users,
        active_rooms:         active_rooms,
        worlds_with_items:    worlds_with_items
      }
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp load_admin(%{"admin_user_id" => id}), do: VrexServer.Accounts.get_user(id)
  defp load_admin(_), do: nil
end
