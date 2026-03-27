defmodule VrexServerWeb.Admin.UsersLive do
  use VrexServerWeb, :live_view
  import Ecto.Query
  alias VrexServer.{Repo, Accounts, Accounts.User, Avatars, Avatars.Avatar}

  @impl true
  def mount(_params, session, socket) do
    admin = load_admin(session)

    {:ok,
     socket
     |> assign(:page_title, "ユーザー管理 · Vrex Admin")
     |> assign(:active_nav, :users)
     |> assign(:current_admin, admin)
     |> assign(:search, "")
     |> assign(:users, list_users(""))
     |> assign(:avatar_counts, load_avatar_counts())
     # 追加モーダル
     |> assign(:adding, false)
     |> assign(:user_form, blank_user_form())
     |> assign(:user_error, nil)
     # 編集モーダル
     |> assign(:editing_user, nil)
     |> assign(:editing_user_avatar, nil)
     |> assign(:edit_user_form, %{})
     |> assign(:edit_user_error, nil)
     # アバターパネル
     |> assign(:avatar_panel_user, nil)
     |> assign(:avatar_panel_avatars, [])
     # アバター編集
     |> assign(:editing_avatar, nil)
     |> assign(:edit_avatar_form, %{})
     |> assign(:avatar_edit_error, nil)
     # アバター 3D プレビュー
     |> assign(:preview_avatar, nil)
     }
  end

  # ── 検索 ─────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:search, q)
     |> assign(:users, list_users(q))
     |> assign(:avatar_counts, load_avatar_counts())}
  end

  # ── ユーザー追加 ──────────────────────────────────────────────

  def handle_event("new_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding, true)
     |> assign(:user_form, blank_user_form())
     |> assign(:user_error, nil)}
  end

  def handle_event("cancel_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding, false)
     |> assign(:user_form, blank_user_form())
     |> assign(:user_error, nil)}
  end

  def handle_event("save_user", %{"user" => params}, socket) do
    attrs = %{
      username:     String.trim(params["username"] || ""),
      email:        String.trim(params["email"] || ""),
      password:     params["password"] || "",
      display_name: String.trim(params["display_name"] || "")
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        if params["is_admin"] == "true" do
          Accounts.update_user(user, %{is_admin: true})
        end

        # 初期アバター作成（アバター名が入力されている場合）
        if (params["avatar_name"] || "") != "" do
          case Avatars.create_avatar(%{
            name:          params["avatar_name"],
            vrm_url:       params["avatar_vrm_url"],
            thumbnail_url: params["avatar_thumbnail_url"],
            is_public:     false,
            user_id:       user.id
          }) do
            {:ok, avatar} -> Accounts.update_user(user, %{avatar_id: avatar.id})
            _             -> :ok
          end
        end

        {:noreply,
         socket
         |> put_flash(:info, "ユーザー「#{user.username}」を作成しました")
         |> assign(:adding, false)
         |> assign(:user_form, blank_user_form())
         |> assign(:user_error, nil)
         |> assign(:users, list_users(socket.assigns.search))
         |> assign(:avatar_counts, load_avatar_counts())}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)

        {:noreply,
         socket
         |> assign(:user_error, msgs)
         |> assign(:user_form, %{
              "username"     => params["username"] || "",
              "display_name" => params["display_name"] || "",
              "email"        => params["email"] || "",
              "is_admin"     => params["is_admin"] || "false"
            })}
    end
  end

  # ── ユーザー編集 ──────────────────────────────────────────────

  def handle_event("edit_user", %{"id" => id}, socket) do
    user   = Accounts.get_user!(id)
    avatar = user.avatar_id && Avatars.get_avatar(user.avatar_id)

    {:noreply,
     socket
     |> assign(:editing_user, user)
     |> assign(:editing_user_avatar, avatar)
     |> assign(:edit_user_form, %{
          "display_name"         => user.display_name || "",
          "is_admin"             => to_string(user.is_admin),
          "avatar_name"          => (avatar && avatar.name) || "",
          "avatar_vrm_url"       => (avatar && avatar.vrm_url) || "",
          "avatar_thumbnail_url" => (avatar && avatar.thumbnail_url) || ""
        })
     |> assign(:edit_user_error, nil)}
  end

  def handle_event("cancel_edit_user", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_user, nil)
     |> assign(:editing_user_avatar, nil)
     |> assign(:edit_user_form, %{})
     |> assign(:edit_user_error, nil)}
  end

  def handle_event("save_edit_user", %{"user" => params}, socket) do
    user  = socket.assigns.editing_user
    attrs = %{
      display_name: String.trim(params["display_name"] || ""),
      is_admin:     params["is_admin"] == "true"
    }

    case Accounts.update_user(user, attrs) do
      {:ok, updated} ->
        if avatar = socket.assigns.editing_user_avatar do
          Avatars.update_avatar(avatar, %{
            name:          String.trim(params["avatar_name"] || ""),
            vrm_url:       String.trim(params["avatar_vrm_url"] || ""),
            thumbnail_url: String.trim(params["avatar_thumbnail_url"] || "")
          })
        end

        {:noreply,
         socket
         |> put_flash(:info, "#{updated.username} を更新しました")
         |> assign(:editing_user, nil)
         |> assign(:editing_user_avatar, nil)
         |> assign(:edit_user_form, %{})
         |> assign(:edit_user_error, nil)
         |> assign(:users, list_users(socket.assigns.search))
         |> assign(:avatar_counts, load_avatar_counts())}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)

        {:noreply,
         socket
         |> assign(:edit_user_error, msgs)
         |> assign(:edit_user_form, %{
              "display_name"         => params["display_name"] || "",
              "is_admin"             => params["is_admin"] || "false",
              "avatar_name"          => params["avatar_name"] || "",
              "avatar_vrm_url"       => params["avatar_vrm_url"] || "",
              "avatar_thumbnail_url" => params["avatar_thumbnail_url"] || ""
            })}
    end
  end

  # ── 権限・削除 ───────────────────────────────────────────────

  def handle_event("toggle_admin", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_admin.id do
      {:noreply, put_flash(socket, :error, "自分自身の管理者権限は変更できません")}
    else
      {:ok, _} = Accounts.update_user(user, %{is_admin: !user.is_admin})

      {:noreply,
       socket
       |> put_flash(:info, "#{user.username} の権限を更新しました")
       |> assign(:users, list_users(socket.assigns.search))}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_admin.id do
      {:noreply, put_flash(socket, :error, "自分自身は削除できません")}
    else
      Repo.delete!(user)

      {:noreply,
       socket
       |> put_flash(:info, "#{user.username} を削除しました")
       |> assign(:users, list_users(socket.assigns.search))
       |> assign(:avatar_counts, load_avatar_counts())}
    end
  end

  # ── アバターパネル ────────────────────────────────────────────

  def handle_event("open_avatars", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    avatars = Avatars.list_avatars_by_user(id)

    {:noreply,
     socket
     |> assign(:avatar_panel_user, user)
     |> assign(:avatar_panel_avatars, avatars)
     |> assign(:editing_avatar, nil)
     |> assign(:edit_avatar_form, %{})
     |> assign(:avatar_edit_error, nil)
     |> assign(:preview_avatar, nil)}
  end

  def handle_event("close_avatars", _params, socket) do
    {:noreply,
     socket
     |> assign(:avatar_panel_user, nil)
     |> assign(:avatar_panel_avatars, [])
     |> assign(:editing_avatar, nil)
     |> assign(:edit_avatar_form, %{})
     |> assign(:avatar_edit_error, nil)
     |> assign(:preview_avatar, nil)}
  end

  # ── アバター編集 ──────────────────────────────────────────────

  def handle_event("edit_avatar", %{"id" => id}, socket) do
    avatar = Avatars.get_avatar!(id)

    {:noreply,
     socket
     |> assign(:editing_avatar, avatar)
     |> assign(:edit_avatar_form, %{
          "name"          => avatar.name,
          "vrm_url"       => avatar.vrm_url || "",
          "thumbnail_url" => avatar.thumbnail_url || "",
          "is_public"     => to_string(avatar.is_public)
        })
     |> assign(:avatar_edit_error, nil)
     |> assign(:preview_avatar, nil)}
  end

  def handle_event("cancel_edit_avatar", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_avatar, nil)
     |> assign(:edit_avatar_form, %{})
     |> assign(:avatar_edit_error, nil)}
  end

  def handle_event("save_edit_avatar", %{"avatar" => params}, socket) do
    avatar = socket.assigns.editing_avatar

    attrs = %{
      name:          String.trim(params["name"] || ""),
      vrm_url:       String.trim(params["vrm_url"] || ""),
      thumbnail_url: String.trim(params["thumbnail_url"] || ""),
      is_public:     params["is_public"] == "true"
    }

    case Avatars.update_avatar(avatar, attrs) do
      {:ok, _} ->
        avatars = Avatars.list_avatars_by_user(socket.assigns.avatar_panel_user.id)

        {:noreply,
         socket
         |> put_flash(:info, "アバター「#{attrs.name}」を更新しました")
         |> assign(:editing_avatar, nil)
         |> assign(:edit_avatar_form, %{})
         |> assign(:avatar_edit_error, nil)
         |> assign(:avatar_panel_avatars, avatars)}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)

        {:noreply, assign(socket, :avatar_edit_error, msgs)}
    end
  end

  # ── アバター削除 ──────────────────────────────────────────────

  def handle_event("delete_avatar", %{"id" => id}, socket) do
    avatar = Avatars.get_avatar!(id)
    Avatars.delete_avatar(avatar)

    avatars = Avatars.list_avatars_by_user(socket.assigns.avatar_panel_user.id)

    {:noreply,
     socket
     |> put_flash(:info, "アバター「#{avatar.name}」を削除しました")
     |> assign(:avatar_panel_avatars, avatars)
     |> assign(:avatar_counts, load_avatar_counts())}
  end

  # ── アバター 3D プレビュー ─────────────────────────────────────

  def handle_event("preview_avatar", %{"id" => id}, socket) do
    avatar = Avatars.get_avatar!(id)
    {:noreply, assign(socket, :preview_avatar, avatar)}
  end

  def handle_event("close_avatar_preview", _params, socket) do
    {:noreply, assign(socket, :preview_avatar, nil)}
  end

  # ── 描画 ─────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:24px;">
      <h2 style="font-size:1.4rem; font-weight:700;">ユーザー管理</h2>
      <div style="display:flex; align-items:center; gap:12px;">
        <span style="color:#888; font-size:.875rem;">{length(@users)} アカウント</span>
        <button class="btn btn-primary" phx-click="new_user">＋ ユーザー追加</button>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">ユーザー一覧</span>
        <form phx-change="search" style="display:inline;">
          <input
            type="search"
            name="q"
            value={@search}
            placeholder="ユーザー名・メールで検索..."
            class="search-input"
            phx-debounce="300"
          />
        </form>
      </div>
      <div class="card-body">
        <table>
          <thead>
            <tr>
              <th>ユーザー</th>
              <th>メール</th>
              <th>権限</th>
              <th>アバター</th>
              <th>登録日</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <%= for user <- @users do %>
              <% count = Map.get(@avatar_counts, user.id, 0) %>
              <tr>
                <td>
                  <div style="font-weight:600;">{user.display_name || user.username}</div>
                  <div style="color:#888; font-size:.78rem;">@{user.username}</div>
                </td>
                <td style="color:#888;">{user.email}</td>
                <td>
                  <%= if user.is_admin do %>
                    <span class="badge badge-purple">Admin</span>
                  <% else %>
                    <span class="badge badge-gray">一般</span>
                  <% end %>
                </td>
                <td>
                  <div style="display:flex; align-items:center; gap:6px;">
                    <%= if count > 0 do %>
                      <span class="badge badge-green">{count} 体</span>
                      <button
                        class="btn btn-ghost"
                        phx-click="open_avatars"
                        phx-value-id={user.id}
                        style="font-size:.72rem; padding:3px 8px;"
                        title="アバター一覧"
                      >
                        👁 一覧
                      </button>
                    <% else %>
                      <span style="color:#888; font-size:.8rem;">なし</span>
                    <% end %>
                  </div>
                </td>
                <td style="color:#888;">{Calendar.strftime(user.inserted_at, "%Y/%m/%d")}</td>
                <td>
                  <div style="display:flex; gap:6px;">
                    <button
                      class="btn btn-primary"
                      phx-click="edit_user"
                      phx-value-id={user.id}
                      style="font-size:.75rem; padding:5px 10px;"
                    >
                      👁 編集
                    </button>
                    <button
                      class="btn btn-ghost"
                      phx-click="toggle_admin"
                      phx-value-id={user.id}
                      style="font-size:.75rem; padding:5px 10px;"
                    >
                      {if user.is_admin, do: "🔓 解除", else: "🔑 Admin"}
                    </button>
                    <button
                      class="btn btn-danger"
                      phx-click="delete_user"
                      phx-value-id={user.id}
                      style="font-size:.75rem; padding:5px 10px;"
                      data-confirm={"#{user.username} を削除しますか？"}
                    >
                      削除
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if Enum.empty?(@users) do %>
              <tr>
                <td colspan="6" style="text-align:center; color:#888; padding:32px;">
                  ユーザーが見つかりません
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ユーザー追加モーダル -->
    <%= if @adding do %>
      <div class="modal-backdrop" phx-window-keydown="cancel_user" phx-key="Escape">
        <div class="modal" phx-click-away="cancel_user">
          <div class="modal-title">＋ ユーザー追加</div>
          <%= if @user_error do %>
            <div style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.3); border-radius:6px; padding:10px 14px; margin-bottom:16px; color:#f87171; font-size:.82rem;">
              ⚠ {@user_error}
            </div>
          <% end %>
          <form phx-submit="save_user">
            <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;" class="form-group">
              <div>
                <label class="form-label">ユーザー名 <span style="color:#ef4444;">*</span></label>
                <input type="text" name="user[username]" value={@user_form["username"]}
                  class="form-input" required placeholder="英数字・_ (3〜32文字)" />
              </div>
              <div>
                <label class="form-label">表示名</label>
                <input type="text" name="user[display_name]" value={@user_form["display_name"]}
                  class="form-input" placeholder="任意" />
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">メールアドレス <span style="color:#ef4444;">*</span></label>
              <input type="email" name="user[email]" value={@user_form["email"]}
                class="form-input" required />
            </div>
            <div class="form-group">
              <label class="form-label">
                パスワード <span style="color:#ef4444;">*</span>
                <span style="color:#666; font-size:.75rem;">(8文字以上)</span>
              </label>
              <input type="password" name="user[password]" class="form-input" required minlength="8" />
            </div>
            <div class="form-group">
              <label class="form-label">権限</label>
              <select name="user[is_admin]" class="form-input">
                <option value="false" selected={@user_form["is_admin"] != "true"}>一般ユーザー</option>
                <option value="true"  selected={@user_form["is_admin"] == "true"}>管理者 (Admin)</option>
              </select>
            </div>

            <!-- 初期アバター (任意) -->
            <div style="border:1px solid #1a3a3a; border-radius:8px; padding:16px; margin-bottom:12px;">
              <div style="font-weight:600; font-size:.85rem; color:#26f5d8; margin-bottom:12px;">🧍 初期アバター（任意）</div>
              <div class="form-group">
                <label class="form-label">アバター名 <span style="color:#666; font-size:.75rem;">（入力時に自動作成・アクティブ設定）</span></label>
                <input type="text" name="user[avatar_name]" value={@user_form["avatar_name"]}
                  class="form-input" placeholder="My Avatar" />
              </div>
              <div class="form-group">
                <label class="form-label">VRM URL</label>
                <input type="text" name="user[avatar_vrm_url]" value={@user_form["avatar_vrm_url"]}
                  class="form-input" placeholder="/vrm/model.vrm" />
              </div>
              <div class="form-group" style="margin-bottom:0;">
                <label class="form-label">サムネイル URL</label>
                <input type="text" name="user[avatar_thumbnail_url]" value={@user_form["avatar_thumbnail_url"]}
                  class="form-input" placeholder="/thumbs/avatar.jpg" />
              </div>
            </div>

            <div class="modal-actions">
              <button type="button" class="btn btn-ghost" phx-click="cancel_user">キャンセル</button>
              <button type="submit" class="btn btn-primary">作成</button>
            </div>
          </form>
        </div>
      </div>
    <% end %>

    <!-- ユーザー編集モーダル (プレビュー統合) -->
    <%= if @editing_user do %>
      <% u  = @editing_user %>
      <% av = @editing_user_avatar %>
      <div class="modal-backdrop" phx-window-keydown="cancel_edit_user" phx-key="Escape">
        <div class="modal" style="max-width:860px; max-height:90vh; overflow-y:auto;" phx-click-away="cancel_edit_user">
          <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:16px;">
            <div>
              <div class="modal-title" style="margin-bottom:4px;">✏ ユーザー編集</div>
              <div style="color:#888; font-size:.82rem;">@{u.username} &nbsp;·&nbsp; {u.email}</div>
            </div>
            <button class="btn btn-ghost" phx-click="cancel_edit_user" style="padding:4px 10px;">✕</button>
          </div>

          <%= if @edit_user_error do %>
            <div style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.3); border-radius:6px; padding:10px 14px; margin-bottom:16px; color:#f87171; font-size:.82rem;">
              ⚠ {@edit_user_error}
            </div>
          <% end %>

          <div style="display:grid; grid-template-columns:260px 1fr; gap:24px; align-items:start;">

            <!-- 左: VRM プレビュー -->
            <div style="position:sticky; top:0;">
              <div style="color:var(--muted); font-size:.75rem; margin-bottom:6px; text-transform:uppercase; letter-spacing:.05em;">3D Preview (VRM)</div>
              <%= if av && av.vrm_url && av.vrm_url != "" do %>
                <div id={"mv-user-#{u.id}"} phx-update="ignore" phx-hook="ModelViewer">
                  <model-viewer
                    src={asset_path(av.vrm_url)}
                    auto-rotate
                    camera-controls
                    shadow-intensity="1"
                    alt={av.name}
                    style="width:100%; height:240px; border-radius:8px; border:1px solid var(--border); background:#010a01; display:block;"
                    loading="eager"
                  ></model-viewer>
                </div>
                <div style="color:var(--muted); font-size:.68rem; margin-top:4px; word-break:break-all;">{av.vrm_url}</div>
              <% else %>
                <div style="width:100%; height:240px; border-radius:8px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:3rem;">🧍</div>
              <% end %>

              <!-- ユーザー情報 -->
              <div style="margin-top:12px; display:flex; flex-direction:column; gap:8px;">
                <div>
                  <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:2px;">登録日</div>
                  <div style="color:#888; font-size:.82rem;">{Calendar.strftime(u.inserted_at, "%Y/%m/%d")}</div>
                </div>
                <div style="display:flex; gap:6px; flex-wrap:wrap; margin-top:4px;">
                  <%= if u.is_admin do %>
                    <span class="badge badge-purple">Admin</span>
                  <% else %>
                    <span class="badge badge-gray">一般</span>
                  <% end %>
                  <%= if av do %>
                    <span class="badge badge-green">アバター設定済み</span>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- 右: フォーム -->
            <form phx-submit="save_edit_user">
              <div class="form-group">
                <label class="form-label">表示名</label>
                <input type="text" name="user[display_name]" value={@edit_user_form["display_name"]}
                  class="form-input" placeholder="未設定の場合はユーザー名が使われます" />
              </div>
              <div class="form-group">
                <label class="form-label">権限</label>
                <select name="user[is_admin]" class="form-input">
                  <option value="false" selected={@edit_user_form["is_admin"] != "true"}>一般ユーザー</option>
                  <option value="true"  selected={@edit_user_form["is_admin"] == "true"}>管理者 (Admin)</option>
                </select>
              </div>

              <!-- アバター設定 -->
              <div style="border:1px solid #1a3a3a; border-radius:8px; padding:16px; margin-bottom:12px;">
                <div style="font-weight:600; font-size:.85rem; color:#26f5d8; margin-bottom:12px;">🧍 アバター設定</div>
                <%= if @editing_user_avatar do %>
                  <div class="form-group">
                    <label class="form-label">アバター名</label>
                    <input type="text" name="user[avatar_name]" value={@edit_user_form["avatar_name"]}
                      class="form-input" />
                  </div>
                  <div class="form-group">
                    <label class="form-label">VRM URL</label>
                    <input type="text" name="user[avatar_vrm_url]" value={@edit_user_form["avatar_vrm_url"]}
                      class="form-input" placeholder="/vrm/model.vrm" />
                  </div>
                  <div class="form-group" style="margin-bottom:0;">
                    <label class="form-label">サムネイル URL</label>
                    <div style="display:flex; align-items:center; gap:8px;">
                      <input type="text" name="user[avatar_thumbnail_url]" value={@edit_user_form["avatar_thumbnail_url"]}
                        class="form-input" placeholder="/thumbs/avatar.jpg" />
                      <%= if (@edit_user_form["avatar_thumbnail_url"] || "") != "" do %>
                        <img src={asset_path(@edit_user_form["avatar_thumbnail_url"])}
                          style="width:40px; height:40px; object-fit:cover; border-radius:6px; border:1px solid var(--border); flex-shrink:0;" />
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <div style="color:var(--muted); font-size:.82rem;">アバターが登録されていません</div>
                <% end %>
              </div>

              <div class="modal-actions">
                <button type="button" class="btn btn-ghost" phx-click="cancel_edit_user">キャンセル</button>
                <button type="submit" class="btn btn-primary">保存</button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>

    <!-- アバター一覧パネル -->
    <%= if @avatar_panel_user do %>
      <% u = @avatar_panel_user %>
      <!-- 子モーダル表示中は Escape を無効化して二重クローズを防ぐ -->
      <div class="modal-backdrop"
        phx-window-keydown={unless @preview_avatar || @editing_avatar, do: "close_avatars"}
        phx-key="Escape">
        <div class="modal" style="max-width:760px; max-height:90vh;"
          phx-click-away={unless @preview_avatar || @editing_avatar, do: "close_avatars"}>
          <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:20px;">
            <div>
              <div class="modal-title" style="margin-bottom:4px;">
                {u.display_name || u.username} のアバター
              </div>
              <div style="color:#888; font-size:.78rem;">
                @{u.username} &nbsp;·&nbsp; {length(@avatar_panel_avatars)} 体
              </div>
            </div>
            <button class="btn btn-ghost" phx-click="close_avatars" style="padding:4px 10px;">✕</button>
          </div>

          <!-- アバターリスト -->
          <%= if Enum.empty?(@avatar_panel_avatars) do %>
            <div style="text-align:center; color:#888; padding:40px 0; font-size:.9rem;">
              アバターが登録されていません
            </div>
          <% else %>
            <div style="display:flex; flex-direction:column; gap:12px;">
              <%= for avatar <- @avatar_panel_avatars do %>
                <div style="background:var(--bg); border:1px solid var(--border); border-radius:10px; padding:14px; display:flex; align-items:flex-start; gap:14px;">
                  <!-- サムネイル -->
                  <div style="flex-shrink:0;">
                    <%= if avatar.thumbnail_url && avatar.thumbnail_url != "" do %>
                      <img src={asset_path(avatar.thumbnail_url)}
                        style="width:72px; height:72px; object-fit:cover; border-radius:8px; border:1px solid var(--border);" />
                    <% else %>
                      <div style="width:72px; height:72px; border-radius:8px; border:1px solid var(--border); background:var(--surface); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:1.6rem;">
                        🧍
                      </div>
                    <% end %>
                  </div>

                  <!-- 情報 -->
                  <div style="flex:1; min-width:0;">
                    <div style="display:flex; align-items:center; gap:8px; margin-bottom:6px; flex-wrap:wrap;">
                      <span style="font-weight:600; font-size:.95rem;">{avatar.name}</span>
                      <%= if avatar.is_public do %>
                        <span class="badge badge-green">公開</span>
                      <% else %>
                        <span class="badge badge-gray">非公開</span>
                      <% end %>
                      <%= if u.avatar_id == avatar.id do %>
                        <span class="badge badge-yellow">アクティブ</span>
                      <% end %>
                    </div>
                    <%= if avatar.vrm_url && avatar.vrm_url != "" do %>
                      <div style="display:flex; align-items:center; gap:6px; margin-bottom:4px;">
                        <span class="badge badge-purple">VRM</span>
                        <span style="color:#888; font-size:.72rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:280px;">
                          {Path.basename(avatar.vrm_url)}
                        </span>
                      </div>
                    <% else %>
                      <div style="color:var(--muted); font-size:.78rem; margin-bottom:4px;">VRM 未設定</div>
                    <% end %>
                    <div style="color:#888; font-size:.72rem;">
                      ID: {String.slice(avatar.id, 0, 8)}...
                    </div>
                  </div>

                  <!-- 操作ボタン -->
                  <div style="flex-shrink:0; display:flex; flex-direction:column; gap:6px; align-items:flex-end;">
                    <button
                      class="btn btn-ghost"
                      phx-click="preview_avatar"
                      phx-value-id={avatar.id}
                      style="font-size:.72rem; padding:4px 10px; white-space:nowrap;"
                    >
                      👁 プレビュー
                    </button>
                    <button
                      class="btn btn-primary"
                      phx-click="edit_avatar"
                      phx-value-id={avatar.id}
                      style="font-size:.72rem; padding:4px 10px;"
                    >
                      ✏ 編集
                    </button>
                    <button
                      class="btn btn-danger"
                      phx-click="delete_avatar"
                      phx-value-id={avatar.id}
                      style="font-size:.72rem; padding:4px 10px;"
                      data-confirm={"「#{avatar.name}」を削除しますか？"}
                    >
                      削除
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <!-- アバタープレビューモーダル (アイテムと同スタイル) -->
    <%= if @preview_avatar do %>
      <% av = @preview_avatar %>
      <div class="modal-backdrop" style="z-index:200;" phx-window-keydown="close_avatar_preview" phx-key="Escape">
        <div class="modal" style="max-width:700px; max-height:90vh;" phx-click-away="close_avatar_preview">
          <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:20px;">
            <div class="modal-title" style="margin-bottom:0;">{av.name}</div>
            <button class="btn btn-ghost" phx-click="close_avatar_preview" style="padding:4px 10px;">✕</button>
          </div>

          <!-- 2 カラム: 3D モデル + メタ情報 -->
          <div style="display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-bottom:16px;">
            <!-- 左: 3D モデル -->
            <div>
              <div style="color:var(--muted); font-size:.75rem; margin-bottom:6px; text-transform:uppercase; letter-spacing:.05em;">3D Preview (VRM)</div>
              <%= if av.vrm_url && av.vrm_url != "" do %>
                <div id={"mv-avatar-#{av.id}"} phx-update="ignore" phx-hook="ModelViewer">
                  <model-viewer
                    src={asset_path(av.vrm_url)}
                    auto-rotate
                    camera-controls
                    shadow-intensity="1"
                    alt={av.name}
                    style="width:100%; height:260px; border-radius:8px; border:1px solid var(--border); background:#010a01; display:block;"
                    loading="eager"
                  ></model-viewer>
                </div>
                <div style="color:var(--muted); font-size:.7rem; margin-top:4px; word-break:break-all;">{av.vrm_url}</div>
              <% else %>
                <div style="width:100%; height:260px; border-radius:8px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:3rem;">🧍</div>
              <% end %>
            </div>

            <!-- メタ情報 -->
            <div style="display:flex; flex-direction:column; gap:10px;">
              <div>
                <div style="color:var(--muted); font-size:.72rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:3px;">オーナー</div>
                <div style="font-weight:600;">
                  {@avatar_panel_user && (@avatar_panel_user.display_name || @avatar_panel_user.username) || "—"}
                </div>
              </div>
              <div>
                <div style="color:var(--muted); font-size:.72rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:3px;">フォーマット</div>
                <span class="badge badge-purple">VRM</span>
              </div>
              <div>
                <div style="color:var(--muted); font-size:.72rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:3px;">ファイル</div>
                <div style="color:#888; font-size:.8rem; word-break:break-all;">
                  {Path.basename(av.vrm_url || "—")}
                </div>
              </div>
              <div style="display:flex; gap:6px; flex-wrap:wrap; margin-top:auto;">
                <span class={"badge #{if av.is_public, do: "badge-green", else: "badge-gray"}"}>
                  {if av.is_public, do: "公開", else: "非公開"}
                </span>
                <%= if @avatar_panel_user && @avatar_panel_user.avatar_id == av.id do %>
                  <span class="badge badge-yellow">アクティブ</span>
                <% end %>
              </div>
            </div>
          </div>

        </div>
      </div>
    <% end %>

    <!-- アバター編集モーダル (アイテムと同スタイル) -->
    <%= if @editing_avatar do %>
      <div class="modal-backdrop" style="z-index:200;" phx-window-keydown="cancel_edit_avatar" phx-key="Escape">
        <div class="modal" style="max-width:560px;" phx-click-away="cancel_edit_avatar">
          <div class="modal-title">✏ アバター編集</div>
          <div style="color:#888; font-size:.82rem; margin-bottom:16px;">
            {@editing_avatar.name}
          </div>
          <%= if @avatar_edit_error do %>
            <div style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.3); border-radius:6px; padding:10px 14px; margin-bottom:16px; color:#f87171; font-size:.82rem;">
              ⚠ {@avatar_edit_error}
            </div>
          <% end %>
          <form phx-submit="save_edit_avatar">
            <div style="display:grid; grid-template-columns:2fr 1fr; gap:12px;" class="form-group">
              <div>
                <label class="form-label">アバター名 <span style="color:#ef4444;">*</span></label>
                <input type="text" name="avatar[name]" value={@edit_avatar_form["name"]}
                  class="form-input" required />
              </div>
              <div>
                <label class="form-label">公開設定</label>
                <select name="avatar[is_public]" class="form-input">
                  <option value="false" selected={@edit_avatar_form["is_public"] != "true"}>非公開</option>
                  <option value="true"  selected={@edit_avatar_form["is_public"] == "true"}>公開</option>
                </select>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">VRM モデル URL</label>
              <input type="text" name="avatar[vrm_url]" value={@edit_avatar_form["vrm_url"]}
                class="form-input" placeholder="/vrm/model.vrm" />
            </div>
            <div class="form-group">
              <label class="form-label">サムネイル URL</label>
              <input type="text" name="avatar[thumbnail_url]" value={@edit_avatar_form["thumbnail_url"]}
                class="form-input" placeholder="/thumbs/avatar.jpg" />
            </div>
            <div class="modal-actions">
              <button type="button" class="btn btn-ghost" phx-click="cancel_edit_avatar">キャンセル</button>
              <button type="submit" class="btn btn-primary">保存</button>
            </div>
          </form>
        </div>
      </div>
    <% end %>
    """
  end

  # ── プライベート ─────────────────────────────────────────────

  defp blank_user_form do
    %{
      "username"              => "",
      "display_name"          => "",
      "email"                 => "",
      "is_admin"              => "false",
      "avatar_name"           => "",
      "avatar_vrm_url"        => "",
      "avatar_thumbnail_url"  => ""
    }
  end

  defp list_users("") do
    Repo.all(from u in User, order_by: [asc: u.inserted_at])
  end

  defp list_users(q) do
    term = "%#{q}%"
    Repo.all(
      from u in User,
      where: ilike(u.username, ^term) or ilike(u.email, ^term) or ilike(u.display_name, ^term),
      order_by: [asc: u.inserted_at]
    )
  end

  defp load_avatar_counts do
    Repo.all(
      from a in Avatar,
      group_by: a.user_id,
      select: {a.user_id, count(a.id)}
    )
    |> Map.new()
  end

  # 絶対URLをパス相対に変換 (異なるIP/ホスト名でも現在のサーバーから取得する)
  defp asset_path(nil), do: nil
  defp asset_path(""), do: ""
  defp asset_path(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) and path != "" -> path
      _ -> url
    end
  end

  defp load_admin(%{"admin_user_id" => id}), do: VrexServer.Accounts.get_user(id)
  defp load_admin(_), do: nil
end
