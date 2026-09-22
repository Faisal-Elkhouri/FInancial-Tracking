defmodule FinancialTrackingWeb.HomeLiveTest do
  use FinancialTrackingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the blank home page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home")
  end
end
