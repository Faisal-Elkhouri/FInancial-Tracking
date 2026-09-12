defmodule FinancialTracking.Tracker do
  @moduledoc """
  The Tracker context: the public API for offices, purchases, and executive
  budget line items.

  All persistence for this domain goes through here. The web layer, Livebook
  notebooks, and scripts call these functions — they never touch `Repo` or
  build changesets directly. See docs/INFRASTRUCTURE.md §10 for the
  architecture conventions this enforces.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [change: 1, foreign_key_constraint: 3]

  alias FinancialTracking.Repo
  alias FinancialTracking.Tracker.{ExecutiveBudget, Office, Purchase}

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
    |> Repo.delete()
  end

  def change_office(%Office{} = office, attrs \\ %{}) do
    Office.changeset(office, attrs)
  end

  ## Purchases

  def list_purchases do
    Repo.all(from p in Purchase, order_by: [desc: p.purchased_at, desc: p.id])
  end

  def get_purchase!(id), do: Repo.get!(Purchase, id)

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

  def delete_purchase(%Purchase{} = purchase) do
    Repo.delete(purchase)
  end

  def change_purchase(%Purchase{} = purchase, attrs \\ %{}) do
    Purchase.changeset(purchase, attrs)
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
end
