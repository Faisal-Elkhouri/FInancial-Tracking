defmodule FinancialTracking.TrackerFixtures do
  @moduledoc """
  Test helpers for creating entities in the Tracker domain
  (offices, projects, purchases, single purchases, executive budget line items).

  Fixtures go through the `FinancialTracking.Tracker` context so they
  exercise the same code paths as the application.
  """

  alias FinancialTracking.Tracker

  def unique_office_name, do: "office-#{System.unique_integer([:positive])}"

  def office_fixture(attrs \\ %{}) do
    {:ok, office} =
      attrs
      |> Enum.into(%{name: unique_office_name()})
      |> Tracker.create_office()

    office
  end

  def purchase_fixture(attrs \\ %{}) do
    {:ok, purchase} =
      attrs
      |> Enum.into(%{
        name: "purchase-#{System.unique_integer([:positive])}",
        amount: Decimal.new("42.50"),
        is_tax: false,
        includes_tax: true,
        purchased_at: DateTime.utc_now() |> DateTime.truncate(:second),
        slbo_project_code: 1234
      })
      |> Map.put_new_lazy(:origin_office_id, fn -> office_fixture().id end)
      |> Tracker.create_purchase()

    purchase
  end

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{title: "project-#{System.unique_integer([:positive])}"})
      |> Tracker.create_project()

    project
  end

  @doc "Assigns `office` (default: a new one) to `project` (default: a new one)."
  def project_office_fixture(project \\ nil, office \\ nil) do
    project = project || project_fixture()
    office = office || office_fixture()
    {:ok, _} = Tracker.assign_office(project, office)

    {project, office}
  end

  def single_purchase_fixture(purchase \\ nil, attrs \\ %{}) do
    purchase = purchase || purchase_fixture()

    {:ok, single} =
      Tracker.create_single_purchase(
        purchase,
        Enum.into(attrs, %{
          projects: "project-a",
          title: "single-#{System.unique_integer([:positive])}",
          cost: Decimal.new("5.00")
        })
      )

    single
  end

  def executive_budget_fixture(attrs \\ %{}) do
    {:ok, line_item} =
      attrs
      |> Enum.into(%{
        line_item: "line-item-#{System.unique_integer([:positive])}",
        allocated: Decimal.new("1000.00")
      })
      |> Map.put_new_lazy(:office_id, fn -> office_fixture().id end)
      |> Tracker.create_budget_line_item()

    line_item
  end
end
