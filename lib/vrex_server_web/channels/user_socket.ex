defmodule VrexServerWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", VrexServerWeb.RoomChannel
  channel "world:*", VrexServerWeb.WorldChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case VrexServer.Accounts.get_user_by_token(token) do
      nil -> :error
      user -> {:ok, assign(socket, :current_user, user)}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
