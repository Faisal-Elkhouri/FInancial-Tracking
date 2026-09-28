defmodule FinancialTracking.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FinancialTracking.Accounts` context.

  Users are created the way the app creates them: by an admin, with a
  temporary password. Unless a fixture says otherwise, the user has then
  replaced it with `valid_user_password/0`, so they can log in and aren't
  held on the settings page.
  """

  import Ecto.Query

  alias FinancialTracking.Accounts
  alias FinancialTracking.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  @doc """
  An admin, who has set `valid_user_password/0`.
  """
  def admin_fixture do
    {:ok, {admin, _temporary_password}} = Accounts.bootstrap_admin(unique_user_email())
    set_password(admin)
  end

  def admin_scope_fixture, do: Scope.for_user(admin_fixture())

  @doc """
  A regular user, created by an admin, who is still on the temporary password
  (returned alongside).
  """
  def temporary_password_user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{email: unique_user_email()})
    {:ok, {user, temporary_password}} = Accounts.create_user(admin_scope_fixture(), attrs)
    {user, temporary_password}
  end

  @doc """
  A regular user, created by an admin, who has set `valid_user_password/0`.
  They have no office access until granted some.
  """
  def user_fixture(attrs \\ %{}) do
    {user, _temporary_password} = temporary_password_user_fixture(attrs)
    set_password(user)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  @doc """
  Grants `user` `role` on `office`, acting as a fresh admin.
  """
  def office_membership_fixture(user, office, role \\ :viewer) do
    {:ok, membership} =
      Accounts.grant_office_access(admin_scope_fixture(), user, office, role)

    membership
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    FinancialTracking.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    FinancialTracking.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
