defmodule VrexServerWeb.WorldChannel do
  use Phoenix.Channel
  alias VrexServer.Worlds

  @impl true
  def join("world:" <> world_id, _params, socket) do
    case Worlds.get_world(world_id) do
      nil ->
        {:error, %{reason: "world_not_found"}}

      world ->
        items = Worlds.list_items(world.id)
        socket = assign(socket, :world_id, world_id)
        {:ok, %{world: format_world(world), items: Enum.map(items, &format_item/1)}, socket}
    end
  end

  # Admin: update item transform
  @impl true
  def handle_in("update_item", %{"item_id" => item_id} = payload, socket) do
    user = socket.assigns.current_user

    if user.is_admin do
      item = Worlds.get_item!(item_id)
      attrs = Map.take(payload, ["position", "rotation", "scale", "properties"])
      {:ok, updated} = Worlds.update_item(item, attrs)

      broadcast!(socket, "item_updated", format_item(updated))
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
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
      media: world.media || %{}
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
      properties: item.properties,
      media: item.media || %{},
      script_enabled: item.script_enabled,
      world_id: item.world_id
    }
  end
end
