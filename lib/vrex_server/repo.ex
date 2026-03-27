defmodule VrexServer.Repo do
  use Ecto.Repo,
    otp_app: :vrex_server,
    adapter: Ecto.Adapters.Postgres
end
