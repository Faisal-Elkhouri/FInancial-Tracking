defmodule FinancialTrackingWeb.HomeLiveTest do
  use FinancialTrackingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "sends anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "renders the blank home page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#home")
    end

    test "shows the navigation, without the admin link for a member", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#nav-purchases")
      assert has_element?(view, "#nav-log-out")
      refute has_element?(view, "#nav-admin-users")
    end
  end

  describe "as an admin" do
    setup :register_and_log_in_admin

    test "shows the admin link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#nav-admin-users")
    end
  end
end
