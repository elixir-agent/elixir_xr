defmodule VrexServerWeb.AvatarController do
  use VrexServerWeb, :controller
  alias VrexServer.{Avatars, Accounts}

  def index(conn, _params) do
    avatars = Avatars.list_public_avatars()
    json(conn, %{avatars: Enum.map(avatars, &format_avatar/1)})
  end

  def my_avatars(conn, _params) do
    avatars = Avatars.list_avatars_by_user(conn.assigns.current_user.id)
    json(conn, %{avatars: Enum.map(avatars, &format_avatar/1)})
  end

  def show(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)
    json(conn, %{avatar: format_avatar(avatar)})
  end

  def create(conn, params) do
    attrs = Map.put(params, "user_id", conn.assigns.current_user.id)

    case Avatars.create_avatar(attrs) do
      {:ok, avatar} ->
        conn
        |> put_status(:created)
        |> json(%{avatar: format_avatar(avatar)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    avatar = Avatars.get_avatar!(id)

    if avatar.user_id == conn.assigns.current_user.id do
      case Avatars.update_avatar(avatar, params) do
        {:ok, updated} ->
          json(conn, %{avatar: format_avatar(updated)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "権限がありません"})
    end
  end

  def set_active(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)
    user = conn.assigns.current_user

    if avatar.user_id == user.id do
      {:ok, updated_user} = Accounts.update_user(user, %{avatar_id: avatar.id})
      json(conn, %{user: format_user(updated_user)})
    else
      conn |> put_status(:forbidden) |> json(%{error: "権限がありません"})
    end
  end

  defp format_avatar(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      vrm_url: avatar.vrm_url,
      thumbnail_url: avatar.thumbnail_url,
      is_public: avatar.is_public,
      customization: avatar.customization,
      user_id: avatar.user_id
    }
  end

  defp format_user(user) do
    %{id: user.id, username: user.username, avatar_id: user.avatar_id}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
