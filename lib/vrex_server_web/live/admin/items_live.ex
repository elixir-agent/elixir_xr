defmodule VrexServerWeb.Admin.ItemsLive do
  use VrexServerWeb, :live_view
  import Ecto.Query
  alias VrexServer.{Repo, Worlds, Worlds.Item, Worlds.World, Scripting}

  @impl true
  def mount(_params, session, socket) do
    admin = load_admin(session)

    {:ok,
     socket
     |> assign(:page_title, "アイテム管理 · Vrex Admin")
     |> assign(:active_nav, :items)
     |> assign(:current_admin, admin)
     |> assign(:worlds, list_worlds())
     |> assign(:filter_world_id, "")
     |> assign(:items, list_items(""))
     |> assign(:editing, nil)
     |> assign(:edit_form, %{})
     |> assign(:item_error, nil)
     |> assign(:script_status, nil)}
  end

  @impl true
  def handle_event("filter_world", %{"world_id" => wid}, socket) do
    {:noreply,
     socket
     |> assign(:filter_world_id, wid)
     |> assign(:items, list_items(wid))}
  end

  def handle_event("new_item", _params, socket) do
    default_world_id =
      case socket.assigns.filter_world_id do
        "" -> socket.assigns.worlds |> List.first() |> then(& &1 && &1.id) || ""
        id -> id
      end

    {:noreply,
     socket
     |> assign(:editing, :new)
     |> assign(:script_status, nil)
     |> assign(:item_error, nil)
     |> assign(:edit_form, %{
          "name"             => "",
          "world_id"         => default_world_id,
          "asset_url"        => "",
          "asset_format"     => "glb",
          "thumbnail_url"    => "",
          "collider_enabled" => true,
          "script_enabled"   => false,
          "script"           => "",
          "pos_x" => "0.0", "pos_y" => "0.0", "pos_z" => "0.0",
          "rot_x" => "0.0", "rot_y" => "0.0", "rot_z" => "0.0", "rot_w" => "1.0",
          "scl_x" => "1.0", "scl_y" => "1.0", "scl_z" => "1.0"
        })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    item = Worlds.get_item!(id)
    {:noreply,
     socket
     |> assign(:editing, item.id)
     |> assign(:script_status, nil)
     |> assign(:item_error, nil)
     |> assign(:edit_form, %{
          "name"             => item.name,
          "world_id"         => item.world_id,
          "asset_url"        => item.asset_url || "",
          "asset_format"     => item.asset_format || "glb",
          "thumbnail_url"    => item.thumbnail_url || "",
          "collider_enabled" => item.collider_enabled,
          "script_enabled"   => item.script_enabled,
          "script"           => item.script || "",
          "pos_x" => to_string(get_in(item.position, ["x"]) || 0.0),
          "pos_y" => to_string(get_in(item.position, ["y"]) || 0.0),
          "pos_z" => to_string(get_in(item.position, ["z"]) || 0.0),
          "rot_x" => to_string(get_in(item.rotation, ["x"]) || 0.0),
          "rot_y" => to_string(get_in(item.rotation, ["y"]) || 0.0),
          "rot_z" => to_string(get_in(item.rotation, ["z"]) || 0.0),
          "rot_w" => to_string(get_in(item.rotation, ["w"]) || 1.0),
          "scl_x" => to_string(get_in(item.scale, ["x"]) || 1.0),
          "scl_y" => to_string(get_in(item.scale, ["y"]) || 1.0),
          "scl_z" => to_string(get_in(item.scale, ["z"]) || 1.0)
        })}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, script_status: nil, item_error: nil)}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("validate_script", %{"script" => script}, socket) do
    status =
      case Scripting.validate_script(script) do
        {:ok, _}      -> :ok
        {:error, msg} -> {:error, msg}
      end
    {:noreply, assign(socket, script_status: status)}
  end

  def handle_event("save_item", %{"item" => params}, socket) do
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
          item = Worlds.get_item!(socket.assigns.editing)
          do_save(socket, item, params)
        end
    end
  end

  def handle_event("toggle_collider", %{"id" => id}, socket) do
    item = Worlds.get_item!(id)
    {:ok, _} = Worlds.update_item(item, %{collider_enabled: !item.collider_enabled})
    {:noreply,
     socket
     |> put_flash(:info, "コライダー設定を変更しました")
     |> assign(:items, list_items(socket.assigns.filter_world_id))}
  end

  def handle_event("toggle_script", %{"id" => id}, socket) do
    item = Worlds.get_item!(id)
    {:ok, _} = Worlds.update_item(item, %{script_enabled: !item.script_enabled})
    {:noreply,
     socket
     |> put_flash(:info, "スクリプト設定を変更しました")
     |> assign(:items, list_items(socket.assigns.filter_world_id))}
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Worlds.get_item!(id)
    Worlds.delete_item(item)
    {:noreply,
     socket
     |> put_flash(:info, "アイテム「#{item.name}」を削除しました")
     |> assign(:items, list_items(socket.assigns.filter_world_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:24px;">
      <h2 style="font-size:1.4rem; font-weight:700;">アイテム管理</h2>
      <div style="display:flex; align-items:center; gap:12px;">
        <select
          style="background:var(--bg); border:1px solid var(--border); border-radius:6px; color:var(--text); padding:6px 10px; font-size:.85rem;"
          phx-change="filter_world"
          name="world_id"
        >
          <option value="">全ワールド</option>
          <%= for w <- @worlds do %>
            <option value={w.id} selected={@filter_world_id == w.id}>{w.name}</option>
          <% end %>
        </select>
        <span style="color:#888; font-size:.875rem;">{length(@items)} アイテム</span>
        <button class="btn btn-primary" phx-click="new_item">＋ アイテム追加</button>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">アイテム一覧</span>
      </div>
      <div class="card-body">
        <table>
          <thead>
            <tr>
              <th>アイテム名</th>
              <th>ワールド</th>
              <th>アセット</th>
              <th>コライダー</th>
              <th>スクリプト</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <%= for item <- @items do %>
              <tr>
                <td>
                  <div style="display:flex; align-items:center; gap:10px;">
                    <%= if item.thumbnail_url && item.thumbnail_url != "" do %>
                      <img src={asset_path(item.thumbnail_url)} style="width:36px; height:36px; object-fit:cover; border-radius:6px; border:1px solid var(--border);" />
                    <% else %>
                      <div style="width:36px; height:36px; border-radius:6px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted);">📦</div>
                    <% end %>
                    <div>
                      <div style="font-weight:600;">{item.name}</div>
                      <div style="color:#888; font-size:.75rem;">
                        x={Float.round(get_in(item.position, ["x"]) || 0.0, 1)}
                        y={Float.round(get_in(item.position, ["y"]) || 0.0, 1)}
                        z={Float.round(get_in(item.position, ["z"]) || 0.0, 1)}
                      </div>
                    </div>
                  </div>
                </td>
                <td style="color:#888; font-size:.82rem;">
                  {item.world && item.world.name || "—"}
                </td>
                <td>
                  <%= if item.asset_url && item.asset_url != "" do %>
                    <span class="badge badge-purple">{item.asset_format || "glb"}</span>
                    <div style="color:#888; font-size:.72rem; margin-top:2px; max-width:160px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
                      {Path.basename(item.asset_url || "")}
                    </div>
                  <% else %>
                    <span class="badge badge-gray">未設定</span>
                  <% end %>
                </td>
                <td>
                  <button
                    class={"badge #{if item.collider_enabled, do: "badge-green", else: "badge-gray"}"}
                    phx-click="toggle_collider"
                    phx-value-id={item.id}
                    style="cursor:pointer; border:none;"
                  >
                    {if item.collider_enabled, do: "有効", else: "無効"}
                  </button>
                </td>
                <td>
                  <button
                    class={"badge #{if item.script_enabled, do: "badge-purple", else: "badge-gray"}"}
                    phx-click="toggle_script"
                    phx-value-id={item.id}
                    style="cursor:pointer; border:none;"
                  >
                    {if item.script_enabled, do: "有効", else: "無効"}
                  </button>
                </td>
                <td>
                  <div style="display:flex; gap:6px;">
                    <button
                      class="btn btn-primary"
                      phx-click="edit"
                      phx-value-id={item.id}
                      style="font-size:.75rem; padding:5px 10px;"
                    >
                      👁 編集
                    </button>
                    <button
                      class="btn btn-danger"
                      phx-click="delete_item"
                      phx-value-id={item.id}
                      style="font-size:.75rem; padding:5px 10px;"
                      data-confirm={"「#{item.name}」を削除しますか？"}
                    >
                      削除
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if Enum.empty?(@items) do %>
              <tr>
                <td colspan="6" style="color:#888; text-align:center; padding:32px;">アイテムがありません</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 追加／編集モーダル (プレビュー統合) -->
    <%= if @editing do %>
      <% modal_w = if @editing == :new, do: "680", else: "960" %>
      <div class="modal-backdrop" phx-window-keydown="cancel_edit" phx-key="Escape">
        <div class="modal" style={"max-width:#{modal_w}px; max-height:90vh; overflow-y:auto;"} phx-click-away="cancel_edit">
          <div class="modal-title">
            {if @editing == :new, do: "＋ アイテム追加", else: "✏ アイテム編集"}
          </div>

          <%= if @item_error do %>
            <div style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.3); border-radius:6px; padding:10px 14px; margin-bottom:16px; color:#f87171; font-size:.82rem;">
              ⚠ {@item_error}
            </div>
          <% end %>

          <div style={"#{if @editing != :new, do: "display:grid; grid-template-columns:260px 1fr; gap:24px; "}align-items:start;"}>

            <!-- 左: 3D プレビュー (編集時のみ) -->
            <%= if @editing != :new do %>
              <div style="position:sticky; top:0;">
                <div style="color:var(--muted); font-size:.75rem; margin-bottom:6px; text-transform:uppercase; letter-spacing:.05em;">3D Preview</div>
                <%= if (@edit_form["asset_url"] || "") != "" && (@edit_form["asset_format"] || "glb") == "glb" do %>
                  <div id={"mv-edit-#{@editing}"} phx-update="ignore" phx-hook="ModelViewer">
                    <model-viewer
                      src={asset_path(@edit_form["asset_url"])}
                      auto-rotate
                      camera-controls
                      shadow-intensity="1"
                      style="width:100%; height:220px; border-radius:8px; border:1px solid var(--border); background:#010a01; display:block;"
                      loading="eager"
                    ></model-viewer>
                  </div>
                  <div style="color:var(--muted); font-size:.68rem; margin-top:4px; word-break:break-all;">{@edit_form["asset_url"]}</div>
                <% else %>
                  <div style="width:100%; height:220px; border-radius:8px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:2rem;">📦</div>
                <% end %>
                <% world_name = Enum.find_value(@worlds, "—", fn w -> w.id == @edit_form["world_id"] && w.name end) %>
                <div style="margin-top:12px; display:flex; flex-direction:column; gap:8px;">
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:2px;">ワールド</div>
                    <div style="font-size:.85rem; font-weight:600;">{world_name}</div>
                  </div>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:2px;">Position</div>
                    <div style="font-family:monospace; font-size:.78rem; color:#888;">
                      x={@edit_form["pos_x"]} y={@edit_form["pos_y"]} z={@edit_form["pos_z"]}
                    </div>
                  </div>
                  <div>
                    <div style="color:var(--muted); font-size:.7rem; text-transform:uppercase; letter-spacing:.05em; margin-bottom:2px;">Scale</div>
                    <div style="font-family:monospace; font-size:.78rem; color:#888;">
                      x={@edit_form["scl_x"]} y={@edit_form["scl_y"]} z={@edit_form["scl_z"]}
                    </div>
                  </div>
                  <div style="display:flex; gap:6px; flex-wrap:wrap; margin-top:4px;">
                    <span class={"badge #{if @edit_form["collider_enabled"] == true, do: "badge-green", else: "badge-gray"}"}>
                      {if @edit_form["collider_enabled"] == true, do: "Collider ON", else: "Collider OFF"}
                    </span>
                    <%= if @edit_form["script_enabled"] == true do %>
                      <span class="badge badge-yellow">Script ON</span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- 右: フォーム -->
            <form phx-submit="save_item">
              <div style="display:grid; grid-template-columns:2fr 1fr; gap:12px;" class="form-group">
                <div>
                  <label class="form-label">アイテム名 <span style="color:#ef4444;">*</span></label>
                  <input type="text" name="item[name]" value={@edit_form["name"]} class="form-input" required />
                </div>
                <div>
                  <label class="form-label">ワールド <span style="color:#ef4444;">*</span></label>
                  <select name="item[world_id]" class="form-input">
                    <%= for w <- @worlds do %>
                      <option value={w.id} selected={@edit_form["world_id"] == w.id}>{w.name}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div style="display:grid; grid-template-columns:2fr 1fr; gap:12px;" class="form-group">
                <div>
                  <label class="form-label">アセット URL <span style="color:#666; font-size:.75rem;">(GLB / FBX)</span></label>
                  <input type="text" name="item[asset_url]" value={@edit_form["asset_url"]} class="form-input" placeholder="http://192.168.1.10:4000/glb/item.glb" />
                </div>
                <div>
                  <label class="form-label">フォーマット</label>
                  <select name="item[asset_format]" class="form-input">
                    <%= for fmt <- ["glb", "fbx", "obj"] do %>
                      <option value={fmt} selected={@edit_form["asset_format"] == fmt}>{fmt}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div class="form-group">
                <label class="form-label">サムネイル URL</label>
                <div style="display:grid; grid-template-columns:1fr auto; gap:8px; align-items:center;">
                  <input type="text" name="item[thumbnail_url]" value={@edit_form["thumbnail_url"]} class="form-input" placeholder="http://192.168.1.10:4000/thumbs/item.jpg" />
                  <%= if (@edit_form["thumbnail_url"] || "") != "" do %>
                    <img src={asset_path(@edit_form["thumbnail_url"])} style="width:60px; height:60px; object-fit:cover; border-radius:6px; border:1px solid var(--border); flex-shrink:0;" />
                  <% else %>
                    <div style="width:60px; height:60px; border-radius:6px; border:1px solid var(--border); background:var(--bg); display:flex; align-items:center; justify-content:center; color:var(--muted); flex-shrink:0;">📦</div>
                  <% end %>
                </div>
              </div>

              <!-- Transform -->
              <div style="border:1px solid #333; border-radius:8px; padding:16px; margin-bottom:12px;">
                <div style="font-weight:600; font-size:.85rem; color:#06b6d4; margin-bottom:12px;">📐 Transform</div>

                <div style="margin-bottom:10px;">
                  <label class="form-label">Position (x / y / z)</label>
                  <div style="display:grid; grid-template-columns:1fr 1fr 1fr; gap:8px;">
                    <input type="number" name="item[pos_x]" value={@edit_form["pos_x"]} class="form-input" step="0.1" placeholder="X" />
                    <input type="number" name="item[pos_y]" value={@edit_form["pos_y"]} class="form-input" step="0.1" placeholder="Y" />
                    <input type="number" name="item[pos_z]" value={@edit_form["pos_z"]} class="form-input" step="0.1" placeholder="Z" />
                  </div>
                </div>

                <div style="margin-bottom:10px;">
                  <label class="form-label">Rotation (x / y / z / w  クォータニオン)</label>
                  <div style="display:grid; grid-template-columns:1fr 1fr 1fr 1fr; gap:8px;">
                    <input type="number" name="item[rot_x]" value={@edit_form["rot_x"]} class="form-input" step="0.01" placeholder="X" />
                    <input type="number" name="item[rot_y]" value={@edit_form["rot_y"]} class="form-input" step="0.01" placeholder="Y" />
                    <input type="number" name="item[rot_z]" value={@edit_form["rot_z"]} class="form-input" step="0.01" placeholder="Z" />
                    <input type="number" name="item[rot_w]" value={@edit_form["rot_w"]} class="form-input" step="0.01" placeholder="W" />
                  </div>
                </div>

                <div>
                  <label class="form-label">Scale (x / y / z)</label>
                  <div style="display:grid; grid-template-columns:1fr 1fr 1fr; gap:8px;">
                    <input type="number" name="item[scl_x]" value={@edit_form["scl_x"]} class="form-input" step="0.1" placeholder="X" />
                    <input type="number" name="item[scl_y]" value={@edit_form["scl_y"]} class="form-input" step="0.1" placeholder="Y" />
                    <input type="number" name="item[scl_z]" value={@edit_form["scl_z"]} class="form-input" step="0.1" placeholder="Z" />
                  </div>
                </div>
              </div>

              <!-- コライダー -->
              <div class="form-group">
                <label class="form-label">コライダー</label>
                <select name="item[collider_enabled]" class="form-input">
                  <option value="true"  selected={@edit_form["collider_enabled"] == true}>有効</option>
                  <option value="false" selected={@edit_form["collider_enabled"] == false}>無効</option>
                </select>
              </div>

              <!-- Elixir スクリプト -->
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
                  name="item[script]"
                  class="script-editor"
                  style="min-height:160px;"
                  placeholder={"defmodule MyCrate do\n  use VrexServer.Scripting.ItemScript\n\n  def on_interact(_ctx) do\n    %{sound: \"open\", animation: \"open\"}\n  end\nend"}
                  phx-change="noop"
                >{@edit_form["script"]}</textarea>
                <%= case @script_status do %>
                  <% :ok -> %>       <div class="script-ok">✓ 構文OK</div>
                  <% {:error, m} -> %> <div class="script-err">✗ エラー: {m}</div>
                  <% nil -> %>       <% end %>
              </div>

              <div class="form-group">
                <label class="form-label">スクリプト実行</label>
                <select name="item[script_enabled]" class="form-input">
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

  # ── private ──────────────────────────────────────────────────────────

  defp do_create(socket, params) do
    attrs = build_attrs(params)

    case Worlds.create_item(attrs) do
      {:ok, item} ->
        {:noreply,
         socket
         |> put_flash(:info, "アイテム「#{item.name}」を作成しました")
         |> assign(:editing, nil)
         |> assign(:item_error, nil)
         |> assign(:items, list_items(socket.assigns.filter_world_id))}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :item_error, msgs)}
    end
  end

  defp do_save(socket, item, params) do
    attrs = build_attrs(params)

    case Worlds.update_item(item, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "アイテムを保存しました")
         |> assign(:editing, nil)
         |> assign(:item_error, nil)
         |> assign(:items, list_items(socket.assigns.filter_world_id))}

      {:error, changeset} ->
        msgs = Enum.map_join(changeset.errors, " / ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :item_error, msgs)}
    end
  end

  defp build_attrs(params) do
    %{
      name:             params["name"],
      world_id:         params["world_id"],
      asset_url:        params["asset_url"],
      asset_format:     params["asset_format"] || "glb",
      thumbnail_url:    params["thumbnail_url"],
      collider_enabled: params["collider_enabled"] == "true",
      script:           params["script"],
      script_enabled:   params["script_enabled"] == "true",
      position: %{
        "x" => parse_float(params["pos_x"], 0.0),
        "y" => parse_float(params["pos_y"], 0.0),
        "z" => parse_float(params["pos_z"], 0.0)
      },
      rotation: %{
        "x" => parse_float(params["rot_x"], 0.0),
        "y" => parse_float(params["rot_y"], 0.0),
        "z" => parse_float(params["rot_z"], 0.0),
        "w" => parse_float(params["rot_w"], 1.0)
      },
      scale: %{
        "x" => parse_float(params["scl_x"], 1.0),
        "y" => parse_float(params["scl_y"], 1.0),
        "z" => parse_float(params["scl_z"], 1.0)
      }
    }
  end

  defp parse_float(val, default) do
    case Float.parse(to_string(val)) do
      {f, _} -> f
      :error  -> default
    end
  end

  defp list_items("") do
    Repo.all(
      from i in Item,
      join: w in assoc(i, :world),
      order_by: [asc: w.name, asc: i.inserted_at],
      preload: [:world]
    )
  end

  defp list_items(world_id) do
    Repo.all(
      from i in Item,
      where: i.world_id == ^world_id,
      order_by: [asc: i.inserted_at],
      preload: [:world]
    )
  end

  defp list_worlds do
    Repo.all(from w in World, order_by: [asc: w.inserted_at])
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
