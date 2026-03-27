defmodule VrexServerWeb.Admin.WorldsLive do
  use VrexServerWeb, :live_view
  import Ecto.Query
  alias VrexServer.{Repo, Worlds, Worlds.World, Scripting}

  @impl true
  def mount(_params, session, socket) do
    admin = load_admin(session)

    {:ok,
     socket
     |> assign(:page_title, "ワールド管理 · Vrex Admin")
     |> assign(:active_nav, :worlds)
     |> assign(:current_admin, admin)
     |> assign(:worlds, list_worlds())
     |> assign(:editing, nil)        # nil | :new | world_id
     |> assign(:editing_world_record, nil)
     |> assign(:script_status, nil)
     |> assign(:edit_form, %{})
     |> assign(:world_error, nil)}
  end

  @impl true
  def handle_event("new_world", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, :new)
     |> assign(:editing_world_record, nil)
     |> assign(:edit_form, %{
          "name"               => "",
          "description"        => "",
          "capacity"           => 16,
          "is_public"          => true,
          "script_enabled"     => false,
          "script"             => "",
          "bgm_url"            => "",
          "bgm_volume"         => 0.8,
          "bgm_loop"           => true,
          "skybox_url"         => "",
          "loading_image_url"  => "",
          "ambient_url"        => "",
          "ambient_volume"     => 0.3,
          "floor_texture_url"  => "",
          "floor_tile_scale"   => 1.0
        })
     |> assign(:script_status, nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    world = Worlds.get_world!(id)
    {:noreply,
     socket
     |> assign(:editing, world.id)
     |> assign(:editing_world_record, world)
     |> assign(:edit_form, %{
          "name"              => world.name,
          "description"       => world.description || "",
          "capacity"          => world.capacity,
          "is_public"         => world.is_public,
          "script_enabled"    => world.script_enabled,
          "script"            => world.script || "",
          "bgm_url"            => get_in(world.media, ["bgm", "url"]) || "",
          "bgm_volume"         => get_in(world.media, ["bgm", "volume"]) || 0.8,
          "bgm_loop"           => get_in(world.media, ["bgm", "loop"]) != false,
          "skybox_url"         => get_in(world.media, ["skybox", "url"]) || "",
          "loading_image_url"  => get_in(world.media, ["loading_image", "url"]) || "",
          "ambient_url"        => get_in(world.media, ["ambient", "url"]) || "",
          "ambient_volume"     => get_in(world.media, ["ambient", "volume"]) || 0.3,
          "floor_texture_url"  => get_in(world.media, ["floor", "url"]) || "",
          "floor_tile_scale"   => get_in(world.media, ["floor", "tile_scale"]) || 1.0
        })
     |> assign(:script_status, nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, editing_world_record: nil, script_status: nil, world_error: nil)}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_script", %{"script" => script}, socket) do
    status =
      case Scripting.validate_script(script) do
        {:ok, _}      -> :ok
        {:error, msg} -> {:error, msg}
      end
    {:noreply, assign(socket, script_status: status)}
  end

  def handle_event("save_world", %{"world" => params}, socket) do
    script_valid =
      if params["script"] != "" do
        Scripting.validate_script(params["script"])
      else
        {:ok, nil}
      end

    case script_valid do
      {:error, msg} ->
        {:noreply,
         socket
         |> assign(:script_status, {:error, msg})
         |> put_flash(:error, "スクリプトに構文エラーがあります")}

      _ ->
        if socket.assigns.editing == :new do
          do_create(socket, params)
        else
          world = Worlds.get_world!(socket.assigns.editing)
          do_save(socket, world, params)
        end
    end
  end

  def handle_event("toggle_public", %{"id" => id}, socket) do
    world = Worlds.get_world!(id)
    {:ok, _} = Worlds.update_world(world, %{is_public: !world.is_public})
    {:noreply,
     socket
     |> put_flash(:info, "公開設定を変更しました")
     |> assign(:worlds, list_worlds())}
  end

  def handle_event("toggle_script", %{"id" => id}, socket) do
    world = Worlds.get_world!(id)
    {:ok, _} = Worlds.update_world(world, %{script_enabled: !world.script_enabled})
    {:noreply,
     socket
     |> put_flash(:info, "スクリプト設定を変更しました")
     |> assign(:worlds, list_worlds())}
  end

  def handle_event("delete_world", %{"id" => id}, socket) do
    world = Worlds.get_world!(id)
    Worlds.delete_world(world)
    {:noreply,
     socket
     |> put_flash(:info, "ワールド「#{world.name}」を削除しました")
     |> assign(:worlds, list_worlds())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:24px;">
      <h2 style="font-size:1.4rem; font-weight:700;">ワールド管理</h2>
      <div style="display:flex; align-items:center; gap:12px;">
        <span style="color:#888; font-size:.875rem;">{length(@worlds)} ワールド</span>
        <button class="btn btn-primary" phx-click="new_world">＋ ワールド追加</button>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">ワールド一覧</span>
      </div>
      <div class="card-body">
        <table>
          <thead>
            <tr>
              <th>ワールド名</th>
              <th>作成者</th>
              <th>容量</th>
              <th>公開</th>
              <th>スクリプト</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <%= for world <- @worlds do %>
              <tr>
                <td>
                  <div style="font-weight:600;">{world.name}</div>
                  <%= if world.description do %>
                    <div style="color:#888; font-size:.78rem;">{String.slice(world.description, 0, 40)}</div>
                  <% end %>
                </td>
                <td style="color:#888;">{world.creator && world.creator.username || "—"}</td>
                <td>{world.capacity} 人</td>
                <td>
                  <button
                    class={"badge #{if world.is_public, do: "badge-green", else: "badge-gray"}"}
                    phx-click="toggle_public"
                    phx-value-id={world.id}
                    style="cursor:pointer; border:none;"
                  >
                    {if world.is_public, do: "公開", else: "非公開"}
                  </button>
                </td>
                <td>
                  <button
                    class={"badge #{if world.script_enabled, do: "badge-purple", else: "badge-gray"}"}
                    phx-click="toggle_script"
                    phx-value-id={world.id}
                    style="cursor:pointer; border:none;"
                  >
                    {if world.script_enabled, do: "有効", else: "無効"}
                  </button>
                </td>
                <td>
                  <div style="display:flex; gap:6px;">
                    <button
                      class="btn btn-primary"
                      phx-click="edit"
                      phx-value-id={world.id}
                      style="font-size:.75rem; padding:5px 10px;"
                    >
                      👁 編集
                    </button>
                    <button
                      class="btn btn-danger"
                      phx-click="delete_world"
                      phx-value-id={world.id}
                      style="font-size:.75rem; padding:5px 10px;"
                      data-confirm={"「#{world.name}」を削除しますか？"}
                    >
                      削除
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 追加／編集モーダル (プレビュー統合) -->
    <%= if @editing do %>
      <% modal_w = if @editing == :new, do: "680", else: "1020" %>
      <div class="modal-backdrop" phx-window-keydown="cancel_edit" phx-key="Escape">
        <div class="modal" style={"max-width:#{modal_w}px; max-height:90vh; overflow-y:auto;"} phx-click-away="cancel_edit">
          <div class="modal-title">
            {if @editing == :new, do: "＋ ワールド追加", else: "✏ ワールド編集"}
          </div>
          <%= if @world_error do %>
            <div style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.3); border-radius:6px; padding:10px 14px; margin-bottom:16px; color:#f87171; font-size:.82rem;">
              ⚠ {@world_error}
            </div>
          <% end %>

          <div style={"#{if @editing != :new, do: "display:grid; grid-template-columns:240px 1fr; gap:24px; "}align-items:start;"}>

            <!-- 左: プレビュー (編集時のみ) -->
            <%= if @editing != :new do %>
              <div style="position:sticky; top:0; display:flex; flex-direction:column; gap:10px;">

                <!-- サムネイル -->
                <div>
                  <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">Thumbnail</div>
                  <%= if @editing_world_record && @editing_world_record.thumbnail_url && @editing_world_record.thumbnail_url != "" do %>
                    <img src={asset_path(@editing_world_record.thumbnail_url)} style="width:100%; border-radius:8px; border:1px solid var(--border); object-fit:cover; aspect-ratio:1;" />
                  <% else %>
                    <div style="width:100%; aspect-ratio:1; border-radius:8px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:.78rem;">画像なし</div>
                  <% end %>
                </div>

                <!-- スカイボックス -->
                <div>
                  <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">Skybox</div>
                  <%= if (@edit_form["skybox_url"] || "") != "" do %>
                    <img src={asset_path(@edit_form["skybox_url"])} style="width:100%; border-radius:8px; border:1px solid var(--border); object-fit:cover; aspect-ratio:2/1;" />
                  <% else %>
                    <div style="width:100%; aspect-ratio:2/1; border-radius:8px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:.78rem;">未設定</div>
                  <% end %>
                </div>

                <!-- ローディング画像 -->
                <%= if (@edit_form["loading_image_url"] || "") != "" do %>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">Loading Screen</div>
                    <img src={asset_path(@edit_form["loading_image_url"])} style="width:100%; border-radius:8px; border:1px solid var(--border); object-fit:cover; aspect-ratio:16/9;" />
                  </div>
                <% end %>

                <!-- 床テクスチャ -->
                <%= if (@edit_form["floor_texture_url"] || "") != "" do %>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">Floor Texture</div>
                    <div style="display:flex; align-items:center; gap:8px;">
                      <img src={asset_path(@edit_form["floor_texture_url"])} style="width:60px; height:60px; object-fit:cover; border-radius:6px; border:1px solid var(--border); image-rendering:pixelated; flex-shrink:0;" />
                      <div style="color:var(--muted); font-size:.7rem;">拡大率: {@edit_form["floor_tile_scale"]}</div>
                    </div>
                  </div>
                <% end %>

                <!-- BGM -->
                <%= if (@edit_form["bgm_url"] || "") != "" do %>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">BGM</div>
                    <audio controls style="width:100%; height:28px; filter:invert(1) hue-rotate(90deg);">
                      <source src={asset_path(@edit_form["bgm_url"])} type="audio/mpeg" />
                    </audio>
                    <div style="color:var(--muted); font-size:.68rem; margin-top:2px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">{Path.basename(@edit_form["bgm_url"])}</div>
                  </div>
                <% end %>

                <!-- 環境音 -->
                <%= if (@edit_form["ambient_url"] || "") != "" do %>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px;">Ambient</div>
                    <audio controls style="width:100%; height:28px; filter:invert(1) hue-rotate(90deg);">
                      <source src={asset_path(@edit_form["ambient_url"])} type="audio/mpeg" />
                    </audio>
                    <div style="color:var(--muted); font-size:.68rem; margin-top:2px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">{Path.basename(@edit_form["ambient_url"])}</div>
                  </div>
                <% end %>

                <!-- メタ情報 -->
                <div style="display:flex; gap:6px; flex-wrap:wrap; margin-top:4px;">
                  <%= if @editing_world_record do %>
                    <span class={"badge #{if @editing_world_record.is_public, do: "badge-green", else: "badge-gray"}"}>{if @editing_world_record.is_public, do: "公開", else: "非公開"}</span>
                    <span class="badge badge-purple">{@editing_world_record.capacity} 人</span>
                    <%= if @editing_world_record.script_enabled do %>
                      <span class="badge badge-yellow">Script ON</span>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- 右: フォーム -->
            <form phx-submit="save_world">
              <div class="form-group">
                <label class="form-label">ワールド名 <span style="color:#ef4444;">*</span></label>
                <input type="text" name="world[name]" value={@edit_form["name"]} class="form-input" required />
              </div>
              <div class="form-group">
                <label class="form-label">説明</label>
                <input type="text" name="world[description]" value={@edit_form["description"]} class="form-input" />
              </div>
              <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;" class="form-group">
                <div>
                  <label class="form-label">最大人数</label>
                  <input type="number" name="world[capacity]" value={@edit_form["capacity"]} class="form-input" min="1" max="100" />
                </div>
                <div>
                  <label class="form-label">公開設定</label>
                  <select name="world[is_public]" class="form-input">
                    <option value="true"  selected={@edit_form["is_public"] == true}>公開</option>
                    <option value="false" selected={@edit_form["is_public"] == false}>非公開</option>
                  </select>
                </div>
              </div>

              <!-- メディア設定 -->
              <div style="border:1px solid #333; border-radius:8px; padding:16px; margin-bottom:12px;">
                <div style="font-weight:600; font-size:.85rem; color:#a78bfa; margin-bottom:12px;">🎵 メディア設定</div>

                <div class="form-group">
                  <label class="form-label">BGM URL <span style="color:#666; font-size:.75rem;">(mp3 / ogg)</span></label>
                  <input type="url" name="world[bgm_url]" value={@edit_form["bgm_url"]} class="form-input" placeholder="https://example.com/music/bgm.mp3" />
                </div>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;" class="form-group">
                  <div>
                    <label class="form-label">BGM 音量 <span style="color:#666; font-size:.75rem;">(0.0〜1.0)</span></label>
                    <input type="number" name="world[bgm_volume]" value={@edit_form["bgm_volume"]} class="form-input" min="0" max="1" step="0.1" />
                  </div>
                  <div>
                    <label class="form-label">BGM ループ</label>
                    <select name="world[bgm_loop]" class="form-input">
                      <option value="true"  selected={@edit_form["bgm_loop"] == true}>有効</option>
                      <option value="false" selected={@edit_form["bgm_loop"] == false}>無効</option>
                    </select>
                  </div>
                </div>

                <div class="form-group">
                  <label class="form-label">スカイボックス URL <span style="color:#666; font-size:.75rem;">(360°パノラマ jpg/png)</span></label>
                  <input type="url" name="world[skybox_url]" value={@edit_form["skybox_url"]} class="form-input" placeholder="https://example.com/sky/sunset.jpg" />
                </div>

                <div class="form-group">
                  <label class="form-label">ローディング画像 URL</label>
                  <input type="url" name="world[loading_image_url]" value={@edit_form["loading_image_url"]} class="form-input" placeholder="https://example.com/loading.jpg" />
                </div>

                <div class="form-group">
                  <label class="form-label">環境音 URL <span style="color:#666; font-size:.75rem;">(ループ再生)</span></label>
                  <div style="display:grid; grid-template-columns:1fr auto; gap:8px;">
                    <input type="url" name="world[ambient_url]" value={@edit_form["ambient_url"]} class="form-input" placeholder="https://example.com/ambient/wind.mp3" />
                    <input type="number" name="world[ambient_volume]" value={@edit_form["ambient_volume"]} class="form-input" min="0" max="1" step="0.1" style="width:80px;" placeholder="0.3" />
                  </div>
                </div>

                <div class="form-group" style="margin-bottom:0;">
                  <label class="form-label">床テクスチャ URL <span style="color:#666; font-size:.75rem;">(jpg/png)</span></label>
                  <div style="display:grid; grid-template-columns:1fr auto; gap:8px; align-items:center;">
                    <input type="text" name="world[floor_texture_url]" value={@edit_form["floor_texture_url"]} class="form-input" placeholder="/sky/floor.jpg" />
                    <div style="display:flex; flex-direction:column; gap:2px;">
                      <label style="font-size:.68rem; color:var(--muted); white-space:nowrap;">拡大率</label>
                      <input type="number" name="world[floor_tile_scale]" value={@edit_form["floor_tile_scale"]} class="form-input" min="0.1" max="10" step="0.1" style="width:80px;" placeholder="1.0" />
                    </div>
                  </div>
                </div>
              </div>

              <!-- Elixir スクリプトエディタ -->
              <div class="form-group">
                <label class="form-label" style="display:flex; align-items:center; justify-content:space-between;">
                  <span>Elixir スクリプト</span>
                  <button
                    type="button"
                    class="btn btn-ghost"
                    phx-click="validate_script"
                    phx-value-script={@edit_form["script"] || ""}
                    style="font-size:.72rem; padding:3px 8px;"
                  >
                    構文チェック
                  </button>
                </label>
                <textarea
                  name="world[script]"
                  class="script-editor"
                  placeholder={"defmodule MyWorld do\n  use VrexServer.Scripting.WorldScript\n\n  def on_player_join(ctx) do\n    broadcast(ctx.room_id, \"welcome\", %{message: \"ようこそ！\"})\n  end\nend"}
                  phx-change="noop"
                >{@edit_form["script"]}</textarea>
                <%= case @script_status do %>
                  <% :ok -> %>
                    <div class="script-ok">✓ 構文OK</div>
                  <% {:error, msg} -> %>
                    <div class="script-err">✗ エラー: {msg}</div>
                  <% nil -> %> <% end %>
              </div>

              <div class="form-group">
                <label class="form-label">スクリプト実行</label>
                <select name="world[script_enabled]" class="form-input">
                  <option value="true"  selected={@edit_form["script_enabled"] == true}>有効</option>
                  <option value="false" selected={@edit_form["script_enabled"] == false}>無効</option>
                </select>
              </div>

              <div class="modal-actions">
                <button type="button" class="btn btn-ghost" phx-click="cancel_edit">キャンセル</button>
                <button type="submit" class="btn btn-primary">
                  {if @editing == :new, do: "作成", else: "保存"}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp do_create(socket, params) do
    media = build_world_media(params)

    attrs = %{
      name:           params["name"],
      description:    params["description"],
      capacity:       String.to_integer(to_string(params["capacity"] || "16")),
      is_public:      params["is_public"] == "true",
      script:         params["script"],
      script_enabled: params["script_enabled"] == "true",
      media:          media,
      created_by:     socket.assigns.current_admin && socket.assigns.current_admin.id
    }

    case Worlds.create_world(attrs) do
      {:ok, world} ->
        {:noreply,
         socket
         |> put_flash(:info, "ワールド「#{world.name}」を作成しました")
         |> assign(:editing, nil)
         |> assign(:editing_world_record, nil)
         |> assign(:script_status, nil)
         |> assign(:world_error, nil)
         |> assign(:worlds, list_worlds())}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :world_error, msgs)}
    end
  end

  defp do_save(socket, world, params) do
    media = build_world_media(params)

    attrs = %{
      name:           params["name"],
      description:    params["description"],
      capacity:       String.to_integer(to_string(params["capacity"] || "16")),
      is_public:      params["is_public"] == "true",
      script:         params["script"],
      script_enabled: params["script_enabled"] == "true",
      media:          media
    }

    case Worlds.update_world(world, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "ワールドを保存しました")
         |> assign(:editing, nil)
         |> assign(:editing_world_record, nil)
         |> assign(:script_status, nil)
         |> assign(:world_error, nil)
         |> assign(:worlds, list_worlds())}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :world_error, msgs)}
    end
  end

  defp build_world_media(params) do
    media = %{}

    media =
      if params["bgm_url"] != "" do
        Map.put(media, "bgm", %{
          "url"    => params["bgm_url"],
          "volume" => parse_float(params["bgm_volume"], 0.8),
          "loop"   => params["bgm_loop"] == "true"
        })
      else
        media
      end

    media =
      if params["skybox_url"] != "" do
        Map.put(media, "skybox", %{"url" => params["skybox_url"], "type" => "panorama"})
      else
        media
      end

    media =
      if params["loading_image_url"] != "" do
        Map.put(media, "loading_image", %{"url" => params["loading_image_url"]})
      else
        media
      end

    media =
      if params["ambient_url"] != "" do
        Map.put(media, "ambient", %{
          "url"    => params["ambient_url"],
          "volume" => parse_float(params["ambient_volume"], 0.3)
        })
      else
        media
      end

    if (params["floor_texture_url"] || "") != "" do
      Map.put(media, "floor", %{
        "url"        => params["floor_texture_url"],
        "tile_scale" => parse_float(params["floor_tile_scale"], 1.0)
      })
    else
      media
    end
  end

  defp parse_float(val, default) do
    case Float.parse(to_string(val)) do
      {f, _} -> f
      :error  -> default
    end
  end

  defp list_worlds do
    Repo.all(
      from w in World,
      order_by: [asc: w.inserted_at],
      preload: [:creator]
    )
  end

  # 絶対URLをパス相対に変換 (異なるIP/ホスト名でも常に現在のサーバーから取得する)
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
