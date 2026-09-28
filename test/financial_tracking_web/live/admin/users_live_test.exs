defmodule FinancialTrackingWeb.Admin.UsersLiveTest do
  use FinancialTrackingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import FinancialTracking.AccountsFixtures

  alias FinancialTracking.Accounts

  describe "as a member" do
    setup :register_and_log_in_user

    test "is sent home", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => _}}}} =
               live(conn, ~p"/admin/users")
    end
  end

  test "sends anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/users")
  end

  describe "as an admin" do
    setup :register_and_log_in_admin

    test "lists every user", %{conn: conn, admin: admin} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(view, "#users-#{admin.id}")
      assert has_element?(view, "#users-#{user.id} a[href='/admin/users/#{user.id}']")
    end

    test "creates a user and shows their temporary password once", %{conn: conn} do
      email = unique_user_email()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> form("#new-user-form", user: %{email: email})
      |> render_submit()

      user = Accounts.get_user_by_email(email)
      assert user.must_change_password
      assert has_element?(view, "#users-#{user.id}")

      password =
        view
        |> element("#temp-password-value")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()
        |> String.trim()

      assert Accounts.get_user_by_email_and_password(email, password)

      view |> element("#temp-password-dismiss") |> render_click()
      refute has_element?(view, "#temp-password")
    end

    test "shows validation errors instead of creating a user", %{conn: conn} do
      %{email: taken} = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> form("#new-user-form", user: %{email: taken})
      |> render_submit()

      refute has_element?(view, "#temp-password")
      assert has_element?(view, "#new-user-form", "has already been taken")
    end
  end
end
