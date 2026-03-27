defmodule VrexServerWeb.AuthController do
  use VrexServerWeb, :controller
  alias VrexServer.Accounts

  def register(conn, params) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        token = Accounts.create_token(user)
        conn
        |> put_status(:created)
        |> json(%{token: token, user: format_user(user)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate(email, password) do
      {:ok, user} ->
        token = Accounts.create_token(user)
        json(conn, %{token: token, user: format_user(user)})

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "メールアドレスまたはパスワードが正しくありません"})
    end
  end

  def logout(conn, _params) do
    token = get_token(conn)
    if token, do: Accounts.delete_token(token)
    json(conn, %{ok: true})
  end

  def me(conn, _params) do
    json(conn, %{user: format_user(conn.assigns.current_user)})
  end

  defp format_user(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      display_name: user.display_name,
      avatar_id: user.avatar_id,
      is_admin: user.is_admin
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp get_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
