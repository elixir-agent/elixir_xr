defmodule VrexServerWeb.PageController do
  use VrexServerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
