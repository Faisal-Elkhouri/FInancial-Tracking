defmodule FinancialTracking.Tracker do
  @moduledoc """
  The Tracker context: the public API for offices, projects, purchases, single
  purchases, and executive budget line items.

  All persistence for this domain goes through here. The web layer, Livebook
  notebooks, and scripts call these functions — they never touch `Repo` or
  build changesets directly. See docs/INFRASTRUCTURE.md §10 for the
  architecture conventions this enforces.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [change: 1, change: 2, foreign_key_constraint: 3]

  alias Ecto.Multi
  alias FinancialTracking.Repo

  alias FinancialTracking.Tracker.{
    ExecutiveBudget,
    Office,
    Project,
    ProjectOffice,
    Purchase,
    SinglePurchase
  }

  ## Offices

  def list_offices do
    Repo.all(from o in Office, order_by: o.name)
  end

  def get_office!(id), do: Repo.get!(Office, id)

  @doc """
  Returns an office with its direct children preloaded.

  TODO: only preloads one level; use a recursive CTE (`with_cte` +
  `recursive_ctes: true`) to load full subtrees.
  """
  def get_office_with_children(id) do
    case Repo.get(Office, id) do
      nil -> {:error, :not_found}
      office -> {:ok, Repo.preload(office, :children)}
    end
  end

  def create_office(attrs \\ %{}) do
    %Office{}
    |> Office.changeset(attrs)
    |> Repo.insert()
  end

  def update_office(%Office{} = office, attrs) do
    office
    |> Office.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an office, returning an error changeset if anything still
  references it. Financial records must never be orphaned, so all FKs
  pointing at offices are `on_delete: :restrict` — reassign or delete the
  dependents first.
  """
  def delete_office(%Office{} = office) do
    office
    |> change()
    |> foreign_key_constraint(:children,
      name: "offices_parent_id_fkey",
      message: "office still has sub-offices"
    )
    |> foreign_key_constraint(:purchases,
      name: "purchases_origin_office_id_fkey",
      message: "office still has purchases"
    )
    |> foreign_key_constraint(:budget_line_items,
      name: "executive_budget_office_id_fkey",
      message: "office still has budget line items"
    )
    |> foreign_key_constraint(:projects,
      name: "project_offices_office_id_fkey",
      message: "office is still assigned to projects"
    )
    |> Repo.delete()
  end

  def change_office(%Office{} = office, attrs \\ %{}) do
    Office.changeset(office, attrs)
  end

  ## Projects
  #
  # Projects, purchases and single purchases are soft-deleted: `soft_delete_*`
  # sets `deleted` and `deleted_on`, and the list/get functions below hide
  # deleted rows. Soft-deleting an already-deleted record is a no-op, so
  # `deleted_on` always holds the original deletion time.

  def list_projects do
    Repo.all(from p in Project, where: not p.deleted, order_by: p.title)
  end

  def get_project!(id) do
    Repo.one!(from p in Project, where: p.id == ^id and not p.deleted)
  end

  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  def soft_delete_project(%Project{deleted: true} = project), do: {:ok, project}

  def soft_delete_project(%Project{} = project) do
    project
    |> change(deleted: true, deleted_on: now())
    |> Repo.update()
  end

  ## Project offices
  #
  # A project has any number of offices and an office can serve any number of
  # projects. Purchases are tied to an office (`origin_office_id`), not to a
  # project, so a project's purchases are reached through its offices.

  @doc """
  Assigns an office to a project. Returns an error changeset if the office is
  already assigned to it.
  """
  def assign_office(%Project{id: project_id}, %Office{id: office_id}) do
    %ProjectOffice{}
    |> ProjectOffice.changeset(%{project_id: project_id, office_id: office_id})
    |> Repo.insert()
  end

  @doc """
  Removes an office from a project. Unassigning an office that isn't assigned
  is a no-op.
  """
  def unassign_office(%Project{id: project_id}, %Office{id: office_id}) do
    Repo.delete_all(
      from po in ProjectOffice, where: po.project_id == ^project_id and po.office_id == ^office_id
    )

    :ok
  end

  def list_project_offices(%Project{id: project_id}) do
    Repo.all(
      from o in Office,
        join: po in ProjectOffice,
        on: po.office_id == o.id,
        where: po.project_id == ^project_id,
        order_by: o.name
    )
  end

  def list_office_projects(%Office{id: office_id}) do
    Repo.all(
      from p in Project,
        join: po in ProjectOffice,
        on: po.project_id == p.id,
        where: po.office_id == ^office_id and not p.deleted,
        order_by: p.title
    )
  end

  ## Purchases

  def list_purchases do
    Repo.all(
      from p in Purchase,
        where: not p.deleted,
        order_by: [desc: p.purchased_at, desc: p.id]
    )
  end

  @doc """
  Returns the purchases made by `office` itself, newest first. Purchases of its
  sub-offices are not included.
  """
  def list_office_purchases(%Office{id: office_id}) do
    Repo.all(
      from p in Purchase,
        where: p.origin_office_id == ^office_id and not p.deleted,
        order_by: [desc: p.purchased_at, desc: p.id]
    )
  end

  def get_purchase!(id) do
    Repo.one!(from p in Purchase, where: p.id == ^id and not p.deleted)
  end

  def create_purchase(attrs \\ %{}) do
    %Purchase{}
    |> Purchase.changeset(attrs)
    |> Repo.insert()
  end

  def update_purchase(%Purchase{} = purchase, attrs) do
    purchase
    |> Purchase.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a purchase, returning an error changeset if single purchases still
  belong to it (the FK is `on_delete: :restrict`) — delete or reassign them
  first.
  """
  def delete_purchase(%Purchase{} = purchase) do
    purchase
    |> change()
    |> foreign_key_constraint(:single_purchases,
      name: "single_purchases_big_purchase_id_fkey",
      message: "purchase still has single purchases"
    )
    |> Repo.delete()
  end

  @doc """
  Soft-deletes a purchase and, in the same transaction, every single purchase
  still attached to it (with the same `deleted_on`). Single purchases that
  were already deleted keep their original `deleted_on`.
  """
  def soft_delete_purchase(%Purchase{deleted: true} = purchase), do: {:ok, purchase}

  def soft_delete_purchase(%Purchase{} = purchase) do
    now = now()

    singles =
      from s in SinglePurchase, where: s.big_purchase_id == ^purchase.id and not s.deleted

    Multi.new()
    |> Multi.update(:purchase, change(purchase, deleted: true, deleted_on: now))
    |> Multi.update_all(:single_purchases, singles,
      set: [deleted: true, deleted_on: now, updated_at: now]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{purchase: purchase}} -> {:ok, purchase}
      {:error, :purchase, changeset, _changes} -> {:error, changeset}
    end
  end

  def change_purchase(%Purchase{} = purchase, attrs \\ %{}) do
    Purchase.changeset(purchase, attrs)
  end

  ## Single purchases

  def list_single_purchases(%Purchase{id: purchase_id}) do
    Repo.all(
      from s in SinglePurchase,
        where: s.big_purchase_id == ^purchase_id and not s.deleted,
        order_by: [desc: s.purchased_at, desc: s.id]
    )
  end

  def get_single_purchase!(id) do
    Repo.one!(from s in SinglePurchase, where: s.id == ^id and not s.deleted)
  end

  def create_single_purchase(%Purchase{} = purchase, attrs \\ %{}) do
    %SinglePurchase{big_purchase_id: purchase.id}
    |> SinglePurchase.changeset(attrs)
    |> Repo.insert()
  end

  def soft_delete_single_purchase(%SinglePurchase{deleted: true} = single), do: {:ok, single}

  def soft_delete_single_purchase(%SinglePurchase{} = single) do
    single
    |> change(deleted: true, deleted_on: now())
    |> Repo.update()
  end

  ## Executive budget line items

  def list_budget_line_items do
    Repo.all(from eb in ExecutiveBudget, order_by: eb.line_item)
  end

  def get_budget_line_item!(id), do: Repo.get!(ExecutiveBudget, id)

  def create_budget_line_item(attrs \\ %{}) do
    %ExecutiveBudget{}
    |> ExecutiveBudget.changeset(attrs)
    |> Repo.insert()
  end

  def update_budget_line_item(%ExecutiveBudget{} = line_item, attrs) do
    line_item
    |> ExecutiveBudget.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a budget line item. Children of the deleted item survive with
  `parent_line_item_id` set to nil (`on_delete: :nilify_all`) — they become
  top-level line items rather than disappearing.
  """
  def delete_budget_line_item(%ExecutiveBudget{} = line_item) do
    Repo.delete(line_item)
  end

  def change_budget_line_item(%ExecutiveBudget{} = line_item, attrs \\ %{}) do
    ExecutiveBudget.changeset(line_item, attrs)
  end

  # :utc_datetime columns reject microseconds.
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
