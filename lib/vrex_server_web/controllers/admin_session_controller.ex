defmodule VrexServerWeb.AdminSessionController do
  use VrexServerWeb, :controller
  alias VrexServer.Accounts

  def new(conn, _params) do
    render(conn, :new, error: nil)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate(email, password) do
      {:ok, user} when user.is_admin ->
        conn
        |> put_session(:admin_user_id, user.id)
        |> put_flash(:info, "ようこそ、#{user.display_name || user.username} さん")
        |> redirect(to: "/admin")

      {:ok, _user} ->
        render(conn, :new, error: "管理者権限がありません")

      {:error, :invalid_credentials} ->
        render(conn, :new, error: "メールアドレスまたはパスワードが正しくありません")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/admin/login")
  end
end
