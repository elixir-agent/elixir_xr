defmodule VrexServer.Accounts.UserToken do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_tokens" do
    field :token, :string
    field :context, :string
    field :expires_at, :utc_datetime

    belongs_to :user, VrexServer.Accounts.User

    timestamps(updated_at: false)
  end

  def build_token(user, context \\ "auth") do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(86_400 * 30, :second)
      |> DateTime.truncate(:second)

    %__MODULE__{
      token: token,
      context: context,
      expires_at: expires_at,
      user_id: user.id
    }
  end
end
