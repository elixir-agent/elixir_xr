defmodule VrexServerWeb.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case VrexServer.Accounts.get_user_by_token(token) do
          nil ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "認証が必要です"})
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "認証トークンがありません"})
        |> halt()
    end
  end
end
