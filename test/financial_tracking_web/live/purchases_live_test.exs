defmodule FinancialTrackingWeb.PurchasesLiveTest do
  use FinancialTrackingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker

  test "asks for an office before showing any purchases", %{conn: conn} do
    office = office_fixture()
    purchase_fixture(%{origin_office_id: office.id})

    {:ok, view, _html} = live(conn, ~p"/purchases")

    assert has_element?(view, "#office-form select option[value='#{office.id}']")
    assert has_element?(view, "#no-office-selected")
    refute has_element?(view, "#purchases")
  end

  test "explains when there are no offices to choose from", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/purchases")

    assert has_element?(view, "#no-offices")
    refute has_element?(view, "#office-form")
  end

  test "selecting an office shows only that office's purchases", %{conn: conn} do
    office = office_fixture()
    other_office = office_fixture()
    purchase = purchase_fixture(%{origin_office_id: office.id})
    other_purchase = purchase_fixture(%{origin_office_id: other_office.id})

    {:ok, view, _html} = live(conn, ~p"/purchases")

    view
    |> element("#office-form")
    |> render_change(%{"office_id" => office.id})

    assert_patch(view, ~p"/purchases?#{[office_id: office.id]}")
    assert has_element?(view, "#purchases-#{purchase.id}")
    refute has_element?(view, "#purchases-#{other_purchase.id}")
  end

  test "switching offices replaces the table rows", %{conn: conn} do
    office = office_fixture()
    other_office = office_fixture()
    purchase = purchase_fixture(%{origin_office_id: office.id})
    other_purchase = purchase_fixture(%{origin_office_id: other_office.id})

    {:ok, view, _html} = live(conn, ~p"/purchases?#{[office_id: office.id]}")
    assert has_element?(view, "#purchases-#{purchase.id}")

    view
    |> element("#office-form")
    |> render_change(%{"office_id" => other_office.id})

    assert has_element?(view, "#purchases-#{other_purchase.id}")
    refute has_element?(view, "#purchases-#{purchase.id}")
  end

  test "clearing the selection hides the table", %{conn: conn} do
    office = office_fixture()
    purchase_fixture(%{origin_office_id: office.id})

    {:ok, view, _html} = live(conn, ~p"/purchases?#{[office_id: office.id]}")

    view
    |> element("#office-form")
    |> render_change(%{"office_id" => ""})

    assert_patch(view, ~p"/purchases")
    assert has_element?(view, "#no-office-selected")
    refute has_element?(view, "#purchases")
  end

  test "hides soft-deleted purchases", %{conn: conn} do
    office = office_fixture()
    kept = purchase_fixture(%{origin_office_id: office.id})
    deleted = purchase_fixture(%{origin_office_id: office.id})
    {:ok, _} = Tracker.soft_delete_purchase(deleted)

    {:ok, view, _html} = live(conn, ~p"/purchases?#{[office_id: office.id]}")

    assert has_element?(view, "#purchases-#{kept.id}")
    refute has_element?(view, "#purchases-#{deleted.id}")
  end

  test "formats amounts with thousands separators", %{conn: conn} do
    office = office_fixture()
    purchase = purchase_fixture(%{origin_office_id: office.id, amount: "1234567.5"})

    {:ok, view, _html} = live(conn, ~p"/purchases?#{[office_id: office.id]}")

    assert has_element?(view, "#purchases-#{purchase.id} td", "$1,234,567.50")
  end

  test "shows an empty state for an office with no purchases", %{conn: conn} do
    office = office_fixture()

    {:ok, view, _html} = live(conn, ~p"/purchases?#{[office_id: office.id]}")

    assert has_element?(view, "#no-purchases")
    refute has_element?(view, "#purchases")
  end

  test "sends an unknown office back to the office picker", %{conn: conn} do
    office_fixture()

    assert {:error, {:live_redirect, %{to: "/purchases", flash: flash}}} =
             live(conn, ~p"/purchases?office_id=not-an-office")

    assert flash["error"]
  end
end
