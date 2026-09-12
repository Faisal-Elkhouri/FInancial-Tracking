defmodule FinancialTracking.Tracker.ExecutiveBudgetTest do
  use FinancialTracking.DataCase, async: true

  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker.ExecutiveBudget

  describe "changeset/2" do
    test "valid with allocated and office_id" do
      office = office_fixture()

      changeset =
        ExecutiveBudget.changeset(%ExecutiveBudget{}, %{
          line_item: "Travel",
          allocated: "5000.00",
          office_id: office.id
        })

      assert changeset.valid?
      assert changeset.changes.allocated == Decimal.new("5000.00")
    end

    test "requires allocated and office_id" do
      changeset = ExecutiveBudget.changeset(%ExecutiveBudget{}, %{})
      refute changeset.valid?

      assert %{
               allocated: ["can't be blank"],
               office_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "casts parent_line_item_id" do
      parent = executive_budget_fixture()

      changeset =
        ExecutiveBudget.changeset(%ExecutiveBudget{}, %{
          allocated: "100.00",
          office_id: parent.office_id,
          parent_line_item_id: parent.id
        })

      assert changeset.valid?
      assert changeset.changes.parent_line_item_id == parent.id
    end
  end

  describe "constraints" do
    test "office must exist" do
      assert {:error, changeset} =
               %ExecutiveBudget{}
               |> ExecutiveBudget.changeset(%{allocated: "100.00", office_id: -1})
               |> Repo.insert()

      assert %{office: ["does not exist"]} = errors_on(changeset)
    end

    test "parent_line_item_id must reference an existing line item" do
      office = office_fixture()

      assert {:error, changeset} =
               %ExecutiveBudget{}
               |> ExecutiveBudget.changeset(%{
                 allocated: "100.00",
                 office_id: office.id,
                 parent_line_item_id: -1
               })
               |> Repo.insert()

      assert %{parent_line_item_id: ["does not exist"]} = errors_on(changeset)
    end

    test "inserts a parent/child line item pair" do
      parent = executive_budget_fixture()
      child = executive_budget_fixture(%{parent_line_item_id: parent.id})

      assert Repo.preload(child, :parent_line_item).parent_line_item.id == parent.id
    end
  end
end
