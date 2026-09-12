defmodule FinancialTracking.TrackerTest do
  use FinancialTracking.DataCase, async: true

  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker
  alias FinancialTracking.Tracker.{ExecutiveBudget, Office, Purchase}

  describe "offices" do
    test "create_office/1 with valid attrs" do
      assert {:ok, %Office{} = office} = Tracker.create_office(%{name: "Finance"})
      assert office.name == "Finance"
    end

    test "create_office/1 with invalid attrs returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tracker.create_office(%{})
    end

    test "list_offices/0 returns offices sorted by name" do
      b = office_fixture(%{name: "B office #{System.unique_integer([:positive])}"})
      a = office_fixture(%{name: "A office #{System.unique_integer([:positive])}"})

      assert Enum.map(Tracker.list_offices(), & &1.id) == [a.id, b.id]
    end

    test "get_office!/1 returns the office" do
      office = office_fixture()
      assert Tracker.get_office!(office.id).id == office.id
    end

    test "update_office/2 updates the name" do
      office = office_fixture()
      assert {:ok, updated} = Tracker.update_office(office, %{name: "Renamed"})
      assert updated.name == "Renamed"
    end

    test "delete_office/1 deletes an office nothing references" do
      office = office_fixture()
      assert {:ok, %Office{}} = Tracker.delete_office(office)
      assert_raise Ecto.NoResultsError, fn -> Tracker.get_office!(office.id) end
    end

    test "delete_office/1 refuses when sub-offices exist" do
      parent = office_fixture()
      _child = office_fixture(%{parent_id: parent.id})

      assert {:error, changeset} = Tracker.delete_office(parent)
      assert %{children: ["office still has sub-offices"]} = errors_on(changeset)
    end

    test "delete_office/1 refuses when purchases reference the office" do
      office = office_fixture()
      _purchase = purchase_fixture(%{origin_office_id: office.id})

      assert {:error, changeset} = Tracker.delete_office(office)
      assert %{purchases: ["office still has purchases"]} = errors_on(changeset)
    end

    test "delete_office/1 refuses when budget line items reference the office" do
      office = office_fixture()
      _line_item = executive_budget_fixture(%{office_id: office.id})

      assert {:error, changeset} = Tracker.delete_office(office)
      assert %{budget_line_items: ["office still has budget line items"]} = errors_on(changeset)
    end
  end

  describe "get_office_with_children/1" do
    test "returns {:error, :not_found} for a missing office" do
      assert Tracker.get_office_with_children(-1) == {:error, :not_found}
    end

    test "returns the office with an empty children list" do
      office = office_fixture()

      assert {:ok, found} = Tracker.get_office_with_children(office.id)
      assert found.id == office.id
      assert found.children == []
    end

    test "returns the office with its direct children" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})

      assert {:ok, found} = Tracker.get_office_with_children(parent.id)
      assert [%{id: child_id}] = found.children
      assert child_id == child.id
    end

    test "does not (yet) recurse into grandchildren" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})
      _grandchild = office_fixture(%{parent_id: child.id})

      assert {:ok, found} = Tracker.get_office_with_children(parent.id)
      [loaded_child] = found.children

      # Pins current single-level behavior; grandchildren stay unloaded.
      refute Ecto.assoc_loaded?(loaded_child.children)
    end
  end

  describe "purchases" do
    test "create_purchase/1 with valid attrs" do
      office = office_fixture()

      assert {:ok, %Purchase{} = purchase} =
               Tracker.create_purchase(%{
                 name: "Team lunch",
                 amount: "125.75",
                 origin_office_id: office.id
               })

      assert purchase.amount == Decimal.new("125.75")
    end

    test "create_purchase/1 with invalid attrs returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tracker.create_purchase(%{})
    end

    test "list_purchases/0 returns newest purchases first" do
      older = purchase_fixture(%{purchased_at: ~U[2026-01-01 00:00:00Z]})
      newer = purchase_fixture(%{purchased_at: ~U[2026-06-01 00:00:00Z]})

      assert Enum.map(Tracker.list_purchases(), & &1.id) == [newer.id, older.id]
    end

    test "update_purchase/2 and delete_purchase/1 round-trip" do
      purchase = purchase_fixture()

      assert {:ok, updated} = Tracker.update_purchase(purchase, %{amount: "9.99"})
      assert updated.amount == Decimal.new("9.99")

      assert {:ok, %Purchase{}} = Tracker.delete_purchase(updated)
      assert_raise Ecto.NoResultsError, fn -> Tracker.get_purchase!(purchase.id) end
    end
  end

  describe "executive budget line items" do
    test "create_budget_line_item/1 with valid attrs" do
      office = office_fixture()

      assert {:ok, %ExecutiveBudget{} = line_item} =
               Tracker.create_budget_line_item(%{
                 line_item: "Travel",
                 allocated: "5000.00",
                 office_id: office.id
               })

      assert line_item.allocated == Decimal.new("5000.00")
    end

    test "create_budget_line_item/1 with invalid attrs returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tracker.create_budget_line_item(%{})
    end

    test "deleting a parent line item promotes its children to top level" do
      parent = executive_budget_fixture()
      child = executive_budget_fixture(%{parent_line_item_id: parent.id})

      assert {:ok, %ExecutiveBudget{}} = Tracker.delete_budget_line_item(parent)
      assert Tracker.get_budget_line_item!(child.id).parent_line_item_id == nil
    end
  end
end
