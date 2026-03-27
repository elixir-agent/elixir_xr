defmodule VrexServer.Accounts do
  import Ecto.Query
  alias VrexServer.Repo
  alias VrexServer.Accounts.{User, UserToken}

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def authenticate(email, password) do
    user = get_user_by_email(email)
    if user && Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  def update_user(user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def create_token(user) do
    token = UserToken.build_token(user)
    Repo.insert!(token)
    token.token
  end

  def get_user_by_token(token) do
    now = DateTime.utc_now()
    query =
      from t in UserToken,
        where: t.token == ^token and t.expires_at > ^now,
        join: u in User, on: u.id == t.user_id,
        select: u

    Repo.one(query)
  end

  def delete_token(token) do
    Repo.delete_all(from t in UserToken, where: t.token == ^token)
  end
end
