defmodule VrexServerWeb.AdminAuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :admin_user_id) do
      nil ->
        conn
        |> put_flash(:error, "管理者ログインが必要です")
        |> redirect(to: "/admin/login")
        |> halt()

      user_id ->
        case VrexServer.Accounts.get_user(user_id) do
          nil ->
            conn
            |> clear_session()
            |> redirect(to: "/admin/login")
            |> halt()

          user when not user.is_admin ->
            conn
            |> put_flash(:error, "管理者権限がありません")
            |> redirect(to: "/admin/login")
            |> halt()

          user ->
            assign(conn, :current_admin, user)
        end
    end
  end
end
