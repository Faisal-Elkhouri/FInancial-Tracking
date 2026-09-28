defmodule FinancialTracking.Accounts do
  @moduledoc """
  The Accounts context: users, their sessions, and what they may access.

  There is no self-service sign-up. An admin creates each account with a
  generated temporary password, which the user must change at first login.
  The very first admin comes from `bootstrap_admin/1` (see
  `FinancialTracking.Release.create_admin/1` and `priv/repo/seeds.exs`).

  ## Permissions

  Admins can see and change everything and manage users. Everyone else
  gets access per office through `OfficeMembership` rows, as a `:viewer` or
  an `:editor`. Access to an office covers all of its sub-offices. See
  `office_roles/1`.

  Admin-only functions take the acting user's scope first. Reads return
  nothing for non-admins (as if the records didn't exist), and writes return
  `{:error, :unauthorized}`. Both check the database, not the scope, so an
  admin who is demoted loses access immediately.
  """

  import Ecto.Query, warn: false
  alias FinancialTracking.Repo

  alias FinancialTracking.Accounts.{OfficeMembership, Scope, User, UserToken}
  alias FinancialTracking.Tracker.Office

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets an active user by email and password.

  Deactivated users are treated like wrong passwords, so the login form
  doesn't reveal which accounts exist.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    if User.valid_password?(user, password) and is_nil(user.deactivated_at), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Permissions

  @doc """
  Returns what the scope's user may access: `:all` for an admin, otherwise a
  map of `%{office_id => :viewer | :editor}`.

  A grant on an office extends to all of its sub-offices. Where grants
  overlap, the stronger role wins, so a grant on a sub-office can add access
  but never take it away. A deactivated user gets an empty map.
  """
  def office_roles(%Scope{user: %User{id: user_id}}) do
    case Repo.one(
           from u in User, where: u.id == ^user_id and is_nil(u.deactivated_at), select: u.admin
         ) do
      true -> :all
      false -> inherited_office_roles(user_id)
      nil -> %{}
    end
  end

  def office_roles(_scope), do: %{}

  defp inherited_office_roles(user_id) do
    case Repo.all(
           from m in OfficeMembership, where: m.user_id == ^user_id, select: {m.office_id, m.role}
         ) do
      [] ->
        %{}

      grants ->
        children =
          Repo.all(from o in Office, where: not is_nil(o.parent_id), select: {o.parent_id, o.id})
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

        Enum.reduce(grants, %{}, fn {office_id, role}, roles ->
          grant_subtree(roles, children, office_id, role)
        end)
    end
  end

  # Only descends when the office's role actually improves. That keeps each
  # office's subtree from being walked more than once per role, and also
  # stops the walk if the office hierarchy ever contains a cycle.
  defp grant_subtree(roles, children, office_id, role) do
    current = Map.get(roles, office_id)

    if current && role_rank(current) >= role_rank(role) do
      roles
    else
      children
      |> Map.get(office_id, [])
      |> Enum.reduce(Map.put(roles, office_id, role), &grant_subtree(&2, children, &1, role))
    end
  end

  defp role_rank(:viewer), do: 1
  defp role_rank(:editor), do: 2

  @doc """
  Returns the ids of the offices the scope can see, or `:all` for an admin.
  """
  def visible_office_ids(scope) do
    case office_roles(scope) do
      :all -> :all
      roles -> Map.keys(roles)
    end
  end

  @doc """
  Whether the scope may `:view` or `:edit` the given office's records.
  """
  def can?(scope, action, %Office{id: office_id}) when action in [:view, :edit] do
    case office_roles(scope) do
      :all -> true
      roles -> allows?(Map.get(roles, office_id), action)
    end
  end

  defp allows?(nil, _action), do: false
  defp allows?(_role, :view), do: true
  defp allows?(role, :edit), do: role == :editor

  ## User administration

  @doc """
  Lists all users with their office grants preloaded. Returns `[]` unless the
  scope belongs to an admin.
  """
  def list_users(scope) do
    if admin?(scope) do
      Repo.all(from u in User, order_by: u.email, preload: [office_memberships: :office])
    else
      []
    end
  end

  @doc """
  Gets a user with their office grants preloaded.

  Raises `Ecto.NoResultsError` if the user doesn't exist or the scope doesn't
  belong to an admin.
  """
  def get_user!(scope, id) do
    unless admin?(scope), do: raise(Ecto.NoResultsError, queryable: User)

    memberships =
      from m in OfficeMembership,
        join: o in assoc(m, :office),
        order_by: o.name,
        preload: [office: o]

    User
    |> Repo.get!(id)
    |> Repo.preload(office_memberships: memberships)
  end

  @doc """
  Creates an account with a generated temporary password, to be handed to
  the new user out of band. They must change it when they first log in.

  Returns `{:ok, {user, temporary_password}}`.
  """
  def create_user(scope, attrs) do
    with :ok <- authorize_admin(scope) do
      insert_user_with_temporary_password(attrs, admin: false)
    end
  end

  @doc """
  Creates an admin without checking who is asking. Only for trusted callers
  that have no user to act as: the release shell, seeds, and tests.

  Returns `{:ok, {user, temporary_password}}`.
  """
  def bootstrap_admin(email) do
    insert_user_with_temporary_password(%{email: email}, admin: true)
  end

  defp insert_user_with_temporary_password(attrs, admin: admin) do
    password = generate_temporary_password()

    changeset =
      %User{}
      |> User.email_changeset(attrs)
      |> User.password_changeset(%{password: password})
      # The admin vouches for the address; there's no email to confirm with.
      |> User.confirm_changeset()
      |> Ecto.Changeset.put_change(:must_change_password, true)
      |> Ecto.Changeset.put_change(:admin, admin)

    with {:ok, user} <- Repo.insert(changeset) do
      {:ok, {user, password}}
    end
  end

  # 12 random bytes encode to 16 URL-safe characters, above the 12-character
  # minimum in User.password_changeset/3.
  defp generate_temporary_password do
    12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing a user's email.

  See `FinancialTracking.Accounts.User.email_changeset/3` for a list of supported options.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Changes a user's email. Admin only; users can't change their own, as there
  is no way to confirm the new address.
  """
  def update_user_email(scope, %User{} = user, attrs) do
    with :ok <- authorize_admin(scope) do
      user
      |> User.email_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Replaces a user's password with a new temporary one and logs them out
  everywhere. They must change it when they next log in.

  Returns `{:ok, {user, temporary_password, expired_tokens}}`. Pass the
  tokens to `FinancialTrackingWeb.UserAuth.disconnect_sessions/1`.
  """
  def reset_user_password(scope, %User{} = user) do
    with :ok <- authorize_admin(scope) do
      password = generate_temporary_password()

      result =
        user
        |> User.password_changeset(%{password: password})
        |> Ecto.Changeset.put_change(:must_change_password, true)
        |> update_user_and_delete_all_tokens()

      with {:ok, {user, tokens}} <- result, do: {:ok, {user, password, tokens}}
    end
  end

  @doc """
  Grants or removes admin rights. An admin can't remove their own, so the app
  can't be left without one by accident.
  """
  def set_admin(scope, %User{} = user, admin) when is_boolean(admin) do
    with :ok <- authorize_admin(scope),
         :ok <- not_self(scope, user, admin == false) do
      user
      |> Ecto.Changeset.change(admin: admin)
      |> Repo.update()
    end
  end

  @doc """
  Deactivates a user: they can no longer log in, and all their sessions end.
  An admin can't deactivate themselves.

  Returns `{:ok, {user, expired_tokens}}`. Pass the tokens to
  `FinancialTrackingWeb.UserAuth.disconnect_sessions/1`.
  """
  def deactivate_user(scope, %User{} = user) do
    with :ok <- authorize_admin(scope),
         :ok <- not_self(scope, user, true) do
      user
      |> Ecto.Changeset.change(deactivated_at: DateTime.utc_now(:second))
      |> update_user_and_delete_all_tokens()
    end
  end

  @doc """
  Lets a deactivated user log in again, with the password they had before.
  """
  def reactivate_user(scope, %User{} = user) do
    with :ok <- authorize_admin(scope) do
      user
      |> Ecto.Changeset.change(deactivated_at: nil)
      |> Repo.update()
    end
  end

  ## Office access

  @doc """
  Gives a user `role` on an office and, through it, all of its sub-offices.
  If the user already has a grant on that office, its role is replaced.
  """
  def grant_office_access(scope, %User{} = user, %Office{} = office, role) do
    with :ok <- authorize_admin(scope) do
      %OfficeMembership{user_id: user.id, office_id: office.id}
      |> OfficeMembership.changeset(%{role: role})
      |> Repo.insert(
        on_conflict: {:replace, [:role, :updated_at]},
        conflict_target: [:user_id, :office_id],
        returning: true
      )
    end
  end

  @doc """
  Removes a user's grant on an office. Access they have through a grant on a
  parent office is unaffected.
  """
  def revoke_office_access(scope, %User{} = user, %Office{} = office) do
    with :ok <- authorize_admin(scope) do
      Repo.delete_all(
        from m in OfficeMembership, where: m.user_id == ^user.id and m.office_id == ^office.id
      )

      :ok
    end
  end

  # Checks the database rather than the scope, which may have been built
  # before the user was demoted or deactivated.
  defp admin?(%Scope{user: %User{id: id}}) do
    Repo.exists?(from u in User, where: u.id == ^id and u.admin and is_nil(u.deactivated_at))
  end

  defp admin?(_scope), do: false

  defp authorize_admin(scope) do
    if admin?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp not_self(%Scope{user: %User{id: id}}, %User{id: id}, true = _locks_out?),
    do: {:error, :own_account}

  defp not_self(_scope, _user, _locks_out?), do: :ok

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `FinancialTracking.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password, which also satisfies a pending
  "must change password" from a temporary one.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Ecto.Changeset.put_change(:must_change_password, false)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
