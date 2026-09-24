defmodule FinancialTracking.TrackerTest do
  use FinancialTracking.DataCase, async: true

  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker
  alias FinancialTracking.Tracker.{ExecutiveBudget, Office, Project, Purchase, SinglePurchase}

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

    test "list_office_purchases/1 returns only that office's live purchases, newest first" do
      office = office_fixture()

      older =
        purchase_fixture(%{origin_office_id: office.id, purchased_at: ~U[2026-01-01 00:00:00Z]})

      newer =
        purchase_fixture(%{origin_office_id: office.id, purchased_at: ~U[2026-06-01 00:00:00Z]})

      deleted = purchase_fixture(%{origin_office_id: office.id})
      {:ok, _} = Tracker.soft_delete_purchase(deleted)
      _other_office = purchase_fixture()

      assert Enum.map(Tracker.list_office_purchases(office), & &1.id) == [newer.id, older.id]
    end

    test "update_purchase/2 and delete_purchase/1 round-trip" do
      purchase = purchase_fixture()

      assert {:ok, updated} = Tracker.update_purchase(purchase, %{amount: "9.99"})
      assert updated.amount == Decimal.new("9.99")

      assert {:ok, %Purchase{}} = Tracker.delete_purchase(updated)
      assert_raise Ecto.NoResultsError, fn -> Tracker.get_purchase!(purchase.id) end
    end
  end

  describe "single purchases" do
    test "create_single_purchase/2 attaches the single purchase to its purchase" do
      purchase = purchase_fixture()

      assert {:ok, %SinglePurchase{} = single} =
               Tracker.create_single_purchase(purchase, %{
                 projects: "a",
                 title: "Stapler",
                 cost: "12.50"
               })

      assert single.big_purchase_id == purchase.id
      assert single.cost == Decimal.new("12.50")
      refute single.deleted
    end

    test "create_single_purchase/2 rejects invalid attrs" do
      purchase = purchase_fixture()

      assert {:error, changeset} = Tracker.create_single_purchase(purchase, %{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Tracker.create_single_purchase(purchase, %{projects: "a", title: "x", cost: "-1"})

      assert %{cost: [_]} = errors_on(changeset)
    end

    test "a single purchase requires a purchase that exists" do
      changeset =
        SinglePurchase.changeset(%SinglePurchase{}, %{projects: "a", title: "x"})

      assert %{big_purchase_id: ["can't be blank"]} = errors_on(changeset)

      changeset =
        SinglePurchase.changeset(%SinglePurchase{}, %{
          projects: "a",
          title: "x",
          big_purchase_id: 0
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{big_purchase: ["does not exist"]} = errors_on(changeset)
    end

    test "a purchase can have many single purchases, or none" do
      purchase = purchase_fixture()
      assert Tracker.list_single_purchases(purchase) == []

      a = single_purchase_fixture(purchase)
      b = single_purchase_fixture(purchase)
      _other = single_purchase_fixture()

      assert purchase |> Tracker.list_single_purchases() |> Enum.map(& &1.id) |> Enum.sort() ==
               [a.id, b.id]
    end

    test "soft_delete_single_purchase/1 hides the row but keeps it" do
      single = single_purchase_fixture()

      assert {:ok, deleted} = Tracker.soft_delete_single_purchase(single)
      assert deleted.deleted
      assert %DateTime{} = deleted.deleted_on

      assert_raise Ecto.NoResultsError, fn -> Tracker.get_single_purchase!(single.id) end
      assert Repo.get(SinglePurchase, single.id).deleted
    end
  end

  describe "projects" do
    test "create_project/1 defaults to an active project" do
      assert {:ok, %Project{status: :active, deleted: false}} =
               Tracker.create_project(%{title: "Rollout"})
    end

    test "create_project/1 stores the basic fields" do
      attrs = %{
        title: "Rollout",
        description: "Phase one",
        status: :planned,
        starts_on: ~D[2026-10-01],
        ends_on: ~D[2026-12-31],
        budget: "1500.50"
      }

      assert {:ok, project} = Tracker.create_project(attrs)
      assert project.status == :planned
      assert project.starts_on == ~D[2026-10-01]
      assert Decimal.equal?(project.budget, Decimal.new("1500.50"))
    end

    test "create_project/1 requires a title" do
      assert {:error, changeset} = Tracker.create_project(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_project/1 rejects a negative budget, an unknown status and reversed dates" do
      assert {:error, changeset} =
               Tracker.create_project(%{
                 title: "x",
                 budget: "-1",
                 status: "bogus",
                 starts_on: ~D[2026-10-01],
                 ends_on: ~D[2026-09-01]
               })

      errors = errors_on(changeset)
      assert errors[:budget]
      assert errors[:status]
      assert errors[:ends_on]
    end

    test "update_project/2 updates the project" do
      project = project_fixture()
      assert {:ok, updated} = Tracker.update_project(project, %{status: :completed})
      assert updated.status == :completed
    end
  end

  describe "project offices" do
    test "assign_office/2 links an office to a project, and offices can be shared" do
      project = project_fixture()
      other_project = project_fixture()
      office = office_fixture()

      assert {:ok, _} = Tracker.assign_office(project, office)
      assert {:ok, _} = Tracker.assign_office(other_project, office)

      assert Enum.map(Tracker.list_project_offices(project), & &1.id) == [office.id]

      assert Enum.sort(Enum.map(Tracker.list_office_projects(office), & &1.id)) ==
               Enum.sort([project.id, other_project.id])
    end

    test "a project can have several offices" do
      project = project_fixture()
      a = office_fixture(%{name: "A office #{System.unique_integer([:positive])}"})
      b = office_fixture(%{name: "B office #{System.unique_integer([:positive])}"})
      project_office_fixture(project, b)
      project_office_fixture(project, a)

      assert Enum.map(Tracker.list_project_offices(project), & &1.id) == [a.id, b.id]
    end

    test "assign_office/2 refuses to assign the same office twice" do
      {project, office} = project_office_fixture()

      assert {:error, changeset} = Tracker.assign_office(project, office)
      assert %{office_id: ["is already assigned to this project"]} = errors_on(changeset)
    end

    test "assign_office/2 returns an error changeset for an office that doesn't exist" do
      project = project_fixture()

      assert {:error, changeset} = Tracker.assign_office(project, %Office{id: -1})
      assert %{office: ["does not exist"]} = errors_on(changeset)
    end

    test "unassign_office/2 removes the link and is a no-op if there isn't one" do
      {project, office} = project_office_fixture()

      assert :ok = Tracker.unassign_office(project, office)
      assert Tracker.list_project_offices(project) == []
      assert :ok = Tracker.unassign_office(project, office)
    end

    test "list_office_projects/1 hides soft-deleted projects" do
      {project, office} = project_office_fixture()
      {:ok, _} = Tracker.soft_delete_project(project)

      assert Tracker.list_office_projects(office) == []
    end

    test "delete_office/1 refuses while the office is assigned to a project" do
      {project, office} = project_office_fixture()

      assert {:error, changeset} = Tracker.delete_office(office)
      assert %{projects: ["office is still assigned to projects"]} = errors_on(changeset)

      :ok = Tracker.unassign_office(project, office)
      assert {:ok, _} = Tracker.delete_office(office)
    end
  end

  describe "soft delete" do
    test "soft_delete_project/1 hides the project from list and get" do
      project = project_fixture()
      keep = project_fixture()

      assert {:ok, %Project{deleted: true, deleted_on: %DateTime{}}} =
               Tracker.soft_delete_project(project)

      assert Enum.map(Tracker.list_projects(), & &1.id) == [keep.id]
      assert_raise Ecto.NoResultsError, fn -> Tracker.get_project!(project.id) end
      assert Repo.get(Project, project.id)
    end

    test "soft_delete_purchase/1 hides the purchase and cascades to its singles" do
      purchase = purchase_fixture()
      single = single_purchase_fixture(purchase)
      other = single_purchase_fixture()

      assert {:ok, %Purchase{deleted: true, deleted_on: deleted_on}} =
               Tracker.soft_delete_purchase(purchase)

      assert_raise Ecto.NoResultsError, fn -> Tracker.get_purchase!(purchase.id) end
      refute purchase.id in Enum.map(Tracker.list_purchases(), & &1.id)
      assert Tracker.list_single_purchases(purchase) == []

      cascaded = Repo.get!(SinglePurchase, single.id)
      assert cascaded.deleted
      assert cascaded.deleted_on == deleted_on

      # Unrelated single purchases are untouched.
      refute Repo.get!(SinglePurchase, other.id).deleted
    end

    test "soft_delete_purchase/1 keeps the original deleted_on of already-deleted singles" do
      purchase = purchase_fixture()
      single = single_purchase_fixture(purchase)
      {:ok, single} = Tracker.soft_delete_single_purchase(single)

      # Backdate so the assertion can't pass by both timestamps landing in the same second.
      past = DateTime.add(single.deleted_on, -3600)

      from(s in SinglePurchase, where: s.id == ^single.id)
      |> Repo.update_all(set: [deleted_on: past])

      assert {:ok, _} = Tracker.soft_delete_purchase(purchase)
      assert Repo.get!(SinglePurchase, single.id).deleted_on == past
    end

    test "soft-deleting twice is a no-op that keeps the first deleted_on" do
      {:ok, first} = Tracker.soft_delete_purchase(purchase_fixture())
      assert {:ok, again} = Tracker.soft_delete_purchase(first)
      assert again.deleted_on == first.deleted_on
    end

    test "a soft-deleted purchase still blocks deleting its office" do
      office = office_fixture()
      purchase = purchase_fixture(%{origin_office_id: office.id})
      {:ok, _} = Tracker.soft_delete_purchase(purchase)

      assert {:error, changeset} = Tracker.delete_office(office)
      assert %{purchases: ["office still has purchases"]} = errors_on(changeset)
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
