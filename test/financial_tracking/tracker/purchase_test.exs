defmodule FinancialTracking.Tracker.PurchaseTest do
  use FinancialTracking.DataCase, async: true

  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker.Purchase

  describe "changeset/2" do
    test "valid with all cast fields" do
      office = office_fixture()

      changeset =
        Purchase.changeset(%Purchase{}, %{
          name: "Team lunch",
          amount: "125.75",
          origin_office_id: office.id,
          is_tax: false,
          includes_tax: true,
          purchased_at: ~U[2026-07-01 12:00:00Z],
          slbo_project_code: 4321
        })

      assert changeset.valid?
      assert changeset.changes.amount == Decimal.new("125.75")
    end

    test "requires name" do
      changeset = Purchase.changeset(%Purchase{}, %{amount: "10.00"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts amount from string to decimal" do
      changeset = Purchase.changeset(%Purchase{}, %{name: "Pens", amount: "9.99"})
      assert changeset.changes.amount == Decimal.new("9.99")
    end

    test "rejects a non-numeric amount" do
      changeset = Purchase.changeset(%Purchase{}, %{name: "Pens", amount: "not-money"})
      refute changeset.valid?
      assert %{amount: ["is invalid"]} = errors_on(changeset)
    end

    # Pins current behavior: these columns exist in the schema but are not in
    # the changeset's cast list, so they are silently ignored. If they should
    # be settable, add them to cast/3 in Purchase and update this test.
    test "notes, concur_expense_report, and event are not cast" do
      changeset =
        Purchase.changeset(%Purchase{}, %{
          name: "Conference",
          notes: "ignored",
          concur_expense_report: "ignored",
          event: 7
        })

      refute Map.has_key?(changeset.changes, :notes)
      refute Map.has_key?(changeset.changes, :concur_expense_report)
      refute Map.has_key?(changeset.changes, :event)
    end
  end

  describe "constraints" do
    test "origin_office_id must reference an existing office" do
      assert {:error, changeset} =
               %Purchase{}
               |> Purchase.changeset(%{name: "Ghost purchase", origin_office_id: -1})
               |> Repo.insert()

      assert %{origin_office_id: ["does not exist"]} = errors_on(changeset)
    end

    test "inserts and preloads its origin office" do
      office = office_fixture()
      purchase = purchase_fixture(%{origin_office_id: office.id})

      assert Repo.preload(purchase, :origin_office).origin_office.id == office.id
    end
  end
end
