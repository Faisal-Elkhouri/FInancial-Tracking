defmodule FinancialTracking.Tracker.OfficeTest do
  use FinancialTracking.DataCase, async: true

  import FinancialTracking.TrackerFixtures

  alias FinancialTracking.Tracker.Office

  describe "changeset/2" do
    test "valid with a name" do
      changeset = Office.changeset(%Office{}, %{name: "Finance"})
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Office.changeset(%Office{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts parent_id" do
      parent = office_fixture()
      changeset = Office.changeset(%Office{}, %{name: "Sub", parent_id: parent.id})
      assert changeset.valid?
      assert changeset.changes.parent_id == parent.id
    end
  end

  describe "constraints" do
    test "name must be unique" do
      office = office_fixture()

      assert {:error, changeset} =
               %Office{}
               |> Office.changeset(%{name: office.name})
               |> Repo.insert()

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "parent_id must reference an existing office" do
      assert {:error, changeset} =
               %Office{}
               |> Office.changeset(%{name: unique_office_name(), parent_id: -1})
               |> Repo.insert()

      assert %{parent_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "hierarchy" do
    test "children preload returns the offices pointing at the parent" do
      parent = office_fixture()
      child_a = office_fixture(%{parent_id: parent.id})
      child_b = office_fixture(%{parent_id: parent.id})
      _unrelated = office_fixture()

      children = Repo.preload(parent, :children).children
      assert Enum.sort(Enum.map(children, & &1.id)) == Enum.sort([child_a.id, child_b.id])
    end

    test "parent preload returns the parent office" do
      parent = office_fixture()
      child = office_fixture(%{parent_id: parent.id})

      assert Repo.preload(child, :parent).parent.id == parent.id
    end
  end
end
