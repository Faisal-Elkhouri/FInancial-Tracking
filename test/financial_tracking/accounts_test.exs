defmodule FinancialTracking.AccountsTest do
  use FinancialTracking.DataCase

  alias FinancialTracking.Accounts

  import FinancialTracking.AccountsFixtures
  import FinancialTracking.TrackerFixtures
  alias FinancialTracking.Accounts.{Scope, User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "does not return a deactivated user" do
      user = user_fixture()
      {:ok, _} = Accounts.deactivate_user(admin_scope_fixture(), user)

      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "replacing a temporary password clears must_change_password" do
      {user, _temporary_password} = temporary_password_user_fixture()
      assert user.must_change_password

      {:ok, {user, _}} = Accounts.update_user_password(user, %{password: "new valid password"})

      refute user.must_change_password
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end

    test "does not return a deactivated user", %{user: user, token: token} do
      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [deactivated_at: DateTime.utc_now(:second)]
      )

      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "office_roles/1" do
    test "is :all for an admin" do
      assert Accounts.office_roles(admin_scope_fixture()) == :all
    end

    test "is empty for a user with no grants" do
      office_fixture()
      assert Accounts.office_roles(user_scope_fixture()) == %{}
    end

    test "is empty without a user" do
      assert Accounts.office_roles(nil) == %{}
    end

    test "a grant on an office covers all of its sub-offices, at any depth" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})
      grandchild = office_fixture(%{parent_id: child.id})
      unrelated = office_fixture()
      user = user_fixture()
      office_membership_fixture(user, parent, :viewer)

      roles = Accounts.office_roles(Scope.for_user(user))

      assert roles == %{parent.id => :viewer, child.id => :viewer, grandchild.id => :viewer}
      refute Map.has_key?(roles, unrelated.id)
    end

    test "a grant on a sub-office doesn't reach its parent" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})
      user = user_fixture()
      office_membership_fixture(user, child, :editor)

      assert Accounts.office_roles(Scope.for_user(user)) == %{child.id => :editor}
    end

    test "the stronger role wins where grants overlap" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})
      grandchild = office_fixture(%{parent_id: child.id})
      user = user_fixture()

      # Editor on the parent, viewer on the child: the child stays editor.
      office_membership_fixture(user, parent, :editor)
      office_membership_fixture(user, child, :viewer)

      # Viewer on another tree, editor further down it: only that subtree is upgraded.
      other = office_fixture()
      other_child = office_fixture(%{parent_id: other.id})
      office_membership_fixture(user, other, :viewer)
      office_membership_fixture(user, other_child, :editor)

      assert Accounts.office_roles(Scope.for_user(user)) == %{
               parent.id => :editor,
               child.id => :editor,
               grandchild.id => :editor,
               other.id => :viewer,
               other_child.id => :editor
             }
    end

    test "terminates if the office hierarchy has a cycle" do
      a = office_fixture()
      b = office_fixture(%{parent_id: a.id})
      {:ok, a} = FinancialTracking.Tracker.update_office(a, %{parent_id: b.id})
      user = user_fixture()
      office_membership_fixture(user, a, :viewer)

      assert Accounts.office_roles(Scope.for_user(user)) == %{a.id => :viewer, b.id => :viewer}
    end

    test "reads grants fresh, so a revoked grant stops working without a new scope" do
      office = office_fixture()
      user = user_fixture()
      scope = Scope.for_user(user)
      office_membership_fixture(user, office)
      assert Accounts.can?(scope, :view, office)

      :ok = Accounts.revoke_office_access(admin_scope_fixture(), user, office)

      refute Accounts.can?(scope, :view, office)
    end

    test "is empty for a deactivated user, even an admin" do
      admin = admin_fixture()
      scope = Scope.for_user(admin)
      {:ok, _} = Accounts.deactivate_user(admin_scope_fixture(), admin)

      assert Accounts.office_roles(scope) == %{}
    end
  end

  describe "can?/3 and visible_office_ids/1" do
    test "viewers can view but not edit; editors can do both" do
      viewed = office_fixture()
      edited = office_fixture()
      hidden = office_fixture()
      user = user_fixture()
      office_membership_fixture(user, viewed, :viewer)
      office_membership_fixture(user, edited, :editor)
      scope = Scope.for_user(user)

      assert Accounts.can?(scope, :view, viewed)
      refute Accounts.can?(scope, :edit, viewed)
      assert Accounts.can?(scope, :view, edited)
      assert Accounts.can?(scope, :edit, edited)
      refute Accounts.can?(scope, :view, hidden)
      refute Accounts.can?(scope, :edit, hidden)

      assert Enum.sort(Accounts.visible_office_ids(scope)) == Enum.sort([viewed.id, edited.id])
    end

    test "admins can do anything" do
      office = office_fixture()
      scope = admin_scope_fixture()

      assert Accounts.can?(scope, :edit, office)
      assert Accounts.visible_office_ids(scope) == :all
    end
  end

  describe "create_user/2" do
    test "creates a confirmed user on a temporary password" do
      email = unique_user_email()

      assert {:ok, {user, password}} =
               Accounts.create_user(admin_scope_fixture(), %{"email" => email})

      assert user.email == email
      assert user.confirmed_at
      assert user.must_change_password
      refute user.admin
      assert String.length(password) >= 12
      assert Accounts.get_user_by_email_and_password(email, password)
    end

    test "validates the email" do
      scope = admin_scope_fixture()

      assert {:error, changeset} = Accounts.create_user(scope, %{email: "not valid"})
      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)

      %{email: taken} = user_fixture()
      assert {:error, changeset} = Accounts.create_user(scope, %{email: String.upcase(taken)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "ignores attempts to set admin through the attrs" do
      {:ok, {user, _}} =
        Accounts.create_user(admin_scope_fixture(), %{
          email: unique_user_email(),
          admin: true,
          must_change_password: false
        })

      refute user.admin
      assert user.must_change_password
    end

    test "is refused for non-admins" do
      assert Accounts.create_user(user_scope_fixture(), %{email: unique_user_email()}) ==
               {:error, :unauthorized}

      assert Accounts.create_user(nil, %{email: unique_user_email()}) == {:error, :unauthorized}
    end

    test "is refused for an admin who has since been demoted" do
      admin = admin_fixture()
      stale_scope = Scope.for_user(admin)
      {:ok, _} = Accounts.set_admin(admin_scope_fixture(), admin, false)

      assert Accounts.create_user(stale_scope, %{email: unique_user_email()}) ==
               {:error, :unauthorized}
    end
  end

  describe "bootstrap_admin/1" do
    test "creates an admin on a temporary password" do
      assert {:ok, {user, password}} = Accounts.bootstrap_admin(unique_user_email())
      assert user.admin
      assert user.must_change_password
      assert Accounts.get_user_by_email_and_password(user.email, password)
    end
  end

  describe "list_users/1 and get_user!/2" do
    test "admins see every user with their grants" do
      office = office_fixture()
      user = user_fixture()
      office_membership_fixture(user, office, :editor)
      scope = admin_scope_fixture()

      assert listed = Enum.find(Accounts.list_users(scope), &(&1.id == user.id))
      assert [%{role: :editor, office: %{id: office_id}}] = listed.office_memberships
      assert office_id == office.id

      fetched = Accounts.get_user!(scope, user.id)
      assert [%{office: %{name: name}}] = fetched.office_memberships
      assert name == office.name
    end

    test "non-admins see no one" do
      user = user_fixture()
      scope = user_scope_fixture()

      assert Accounts.list_users(scope) == []
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(scope, user.id) end
    end
  end

  describe "update_user_email/3" do
    test "changes the email" do
      user = user_fixture()
      email = unique_user_email()

      assert {:ok, %{email: ^email}} =
               Accounts.update_user_email(admin_scope_fixture(), user, %{email: email})
    end

    test "is refused for non-admins, including for their own account" do
      user = user_fixture()

      assert Accounts.update_user_email(Scope.for_user(user), user, %{email: unique_user_email()}) ==
               {:error, :unauthorized}
    end
  end

  describe "reset_user_password/2" do
    test "issues a new temporary password and ends the user's sessions" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, {user, password, [%{token: ^token}]}} =
               Accounts.reset_user_password(admin_scope_fixture(), user)

      assert user.must_change_password
      refute Accounts.get_user_by_session_token(token)
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert Accounts.get_user_by_email_and_password(user.email, password)
    end

    test "is refused for non-admins" do
      user = user_fixture()
      assert Accounts.reset_user_password(user_scope_fixture(), user) == {:error, :unauthorized}
    end
  end

  describe "set_admin/3" do
    test "grants and removes admin rights" do
      user = user_fixture()
      scope = admin_scope_fixture()

      assert {:ok, %{admin: true} = user} = Accounts.set_admin(scope, user, true)
      assert {:ok, %{admin: false}} = Accounts.set_admin(scope, user, false)
    end

    test "an admin can't remove their own admin rights" do
      admin = admin_fixture()

      assert Accounts.set_admin(Scope.for_user(admin), admin, false) == {:error, :own_account}
      assert Repo.get!(User, admin.id).admin
    end

    test "is refused for non-admins, including promoting themselves" do
      user = user_fixture()
      assert Accounts.set_admin(Scope.for_user(user), user, true) == {:error, :unauthorized}
    end
  end

  describe "deactivate_user/2 and reactivate_user/2" do
    test "deactivating ends sessions and blocks log in until reactivated" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      scope = admin_scope_fixture()

      assert {:ok, {user, [%{token: ^token}]}} = Accounts.deactivate_user(scope, user)
      assert user.deactivated_at
      refute Accounts.get_user_by_session_token(token)
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())

      assert {:ok, user} = Accounts.reactivate_user(scope, user)
      refute user.deactivated_at
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "an admin can't deactivate themselves" do
      admin = admin_fixture()

      assert Accounts.deactivate_user(Scope.for_user(admin), admin) == {:error, :own_account}
      refute Repo.get!(User, admin.id).deactivated_at
    end

    test "is refused for non-admins" do
      user = user_fixture()
      scope = user_scope_fixture()

      assert Accounts.deactivate_user(scope, user) == {:error, :unauthorized}
      assert Accounts.reactivate_user(scope, user) == {:error, :unauthorized}
    end
  end

  describe "grant_office_access/4 and revoke_office_access/3" do
    test "granting again replaces the role instead of adding a second grant" do
      office = office_fixture()
      user = user_fixture()
      scope = admin_scope_fixture()

      assert {:ok, %{role: :viewer}} = Accounts.grant_office_access(scope, user, office, :viewer)
      assert {:ok, %{role: :editor}} = Accounts.grant_office_access(scope, user, office, "editor")

      assert [%{role: :editor}] = Accounts.get_user!(scope, user.id).office_memberships
    end

    test "rejects unknown roles" do
      assert {:error, changeset} =
               Accounts.grant_office_access(
                 admin_scope_fixture(),
                 user_fixture(),
                 office_fixture(),
                 "owner"
               )

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "revoking removes only that grant" do
      kept = office_fixture()
      revoked = office_fixture()
      user = user_fixture()
      office_membership_fixture(user, kept)
      office_membership_fixture(user, revoked)

      assert :ok = Accounts.revoke_office_access(admin_scope_fixture(), user, revoked)

      assert Accounts.office_roles(Scope.for_user(user)) == %{kept.id => :viewer}
    end

    test "is refused for non-admins, including granting themselves access" do
      office = office_fixture()
      user = user_fixture()
      scope = Scope.for_user(user)

      assert Accounts.grant_office_access(scope, user, office, :editor) == {:error, :unauthorized}
      assert Accounts.revoke_office_access(scope, user, office) == {:error, :unauthorized}
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
