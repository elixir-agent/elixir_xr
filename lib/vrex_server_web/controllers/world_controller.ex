defmodule VrexServerWeb.WorldController do
  use VrexServerWeb, :controller
  alias VrexServer.{Worlds, Scripting}

  def index(conn, _params) do
    worlds = Worlds.list_public_worlds()
    json(conn, %{worlds: Enum.map(worlds, &format_world/1)})
  end

  def my_worlds(conn, _params) do
    worlds = Worlds.list_worlds_by_user(conn.assigns.current_user.id)
    json(conn, %{worlds: Enum.map(worlds, &format_world/1)})
  end

  def show(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)
    items = Worlds.list_items(world.id)
    json(conn, %{world: format_world(world), items: Enum.map(items, &format_item/1)})
  end

  def create(conn, params) do
    attrs = Map.put(params, "created_by", conn.assigns.current_user.id)

    case Worlds.create_world(attrs) do
      {:ok, world} ->
        conn
        |> put_status(:created)
        |> json(%{world: format_world(world)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    world = Worlds.get_world!(id)

    if world.created_by == conn.assigns.current_user.id || conn.assigns.current_user.is_admin do
      # スクリプトの構文チェック
      if script = params["script"] do
        case Scripting.validate_script(script) do
          {:ok, _} -> :ok
          {:error, msg} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "スクリプト構文エラー: #{msg}"})
            |> halt()
        end
      end

      case Worlds.update_world(world, params) do
        {:ok, updated} ->
          json(conn, %{world: format_world(updated)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "権限がありません"})
    end
  end

  def delete(conn, %{"id" => id}) do
    world = Worlds.get_world!(id)

    if world.created_by == conn.assigns.current_user.id || conn.assigns.current_user.is_admin do
      Worlds.delete_world(world)
      send_resp(conn, :no_content, "")
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "権限がありません"})
    end
  end

  # Items

  def create_item(conn, %{"world_id" => world_id} = params) do
    world = Worlds.get_world!(world_id)

    if world.created_by == conn.assigns.current_user.id || conn.assigns.current_user.is_admin do
      case Worlds.create_item(params) do
        {:ok, item} ->
          conn
          |> put_status(:created)
          |> json(%{item: format_item(item)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "権限がありません"})
    end
  end

  def update_item(conn, %{"id" => id} = params) do
    item = Worlds.get_item!(id)
    world = Worlds.get_world!(item.world_id)

    if world.created_by == conn.assigns.current_user.id || conn.assigns.current_user.is_admin do
      case Worlds.update_item(item, params) do
        {:ok, updated} -> json(conn, %{item: format_item(updated)})
        {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "権限がありません"})
    end
  end

  defp format_world(world) do
    %{
      id: world.id,
      name: world.name,
      description: world.description,
      asset_bundle_url: world.asset_bundle_url,
      thumbnail_url: world.thumbnail_url,
      capacity: world.capacity,
      is_public: world.is_public,
      script_enabled: world.script_enabled,
      properties: world.properties,
      media: world.media || %{},
      created_by: world.created_by,
      inserted_at: world.inserted_at
    }
  end

  defp format_item(item) do
    %{
      id: item.id,
      name: item.name,
      asset_url: item.asset_url,
      asset_format: item.asset_format || "glb",
      collider_enabled: item.collider_enabled,
      thumbnail_url: item.thumbnail_url,
      position: item.position,
      rotation: item.rotation,
      scale: item.scale,
      script_enabled: item.script_enabled,
      properties: item.properties,
      media: item.media || %{},
      world_id: item.world_id
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
