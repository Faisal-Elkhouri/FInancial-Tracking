defmodule FinancialTrackingWeb.Admin.UserLiveTest do
  use FinancialTrackingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import FinancialTracking.AccountsFixtures
  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Accounts
  alias FinancialTracking.Accounts.Scope

  describe "as a member" do
    setup :register_and_log_in_user

    test "is sent home, even for their own account", %{conn: conn, user: user} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users/#{user}")
    end
  end

  describe "as an admin" do
    setup :register_and_log_in_admin

    setup do
      %{user: user_fixture()}
    end

    test "grants access to an office and shows how far it reaches", %{conn: conn, user: user} do
      office = office_fixture()
      office_fixture(%{parent_id: office.id})
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      assert has_element?(view, "#office-access-empty")

      view
      |> form("#grant-form", grant: %{office_id: office.id, role: "editor"})
      |> render_submit()

      assert has_element?(view, "#office-access-#{office.id}", "Can edit")
      assert has_element?(view, "#office-access-#{office.id}", "Includes 1 sub-office")
      assert Accounts.can?(Scope.for_user(user), :edit, office)
    end

    test "granting an office again changes the role in place", %{conn: conn, user: user} do
      office = office_fixture()
      office_membership_fixture(user, office, :editor)
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view
      |> form("#grant-form", grant: %{office_id: office.id, role: "viewer"})
      |> render_submit()

      assert has_element?(view, "#office-access-#{office.id}", "Can view")
      refute Accounts.can?(Scope.for_user(user), :edit, office)
    end

    test "revokes access", %{conn: conn, user: user} do
      office = office_fixture()
      office_membership_fixture(user, office)
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view |> element("#revoke-#{office.id}") |> render_click()

      refute has_element?(view, "#office-access-#{office.id}")
      refute Accounts.can?(Scope.for_user(user), :view, office)
    end

    test "resets the password and shows the new temporary one", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view |> element("#reset-password") |> render_click()

      assert has_element?(view, "#temp-password")
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "deactivates and reactivates", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view |> element("#deactivate") |> render_click()
      assert has_element?(view, "#reactivate")
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())

      view |> element("#reactivate") |> render_click()
      assert has_element?(view, "#deactivate")
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "makes a user an admin and back", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view |> element("#make-admin") |> render_click()
      assert Accounts.office_roles(Scope.for_user(user)) == :all

      view |> element("#remove-admin") |> render_click()
      assert Accounts.office_roles(Scope.for_user(user)) == %{}
    end

    test "changes the user's email", %{conn: conn, user: user} do
      email = unique_user_email()
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      view
      |> form("#email-form", user: %{email: email})
      |> render_submit()

      assert Accounts.get_user_by_email(email).id == user.id
    end

    test "can't demote or deactivate their own account", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{admin}")

      assert has_element?(view, "#remove-admin[disabled]")
      assert has_element?(view, "#deactivate[disabled]")
    end

    test "unknown users are not found", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/admin/users/0") end
    end
  end
end
