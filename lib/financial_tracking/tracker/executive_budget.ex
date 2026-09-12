defmodule FinancialTracking.Tracker.ExecutiveBudget do
  use Ecto.Schema
  import Ecto.Changeset

  schema "executive_budget" do
    field :line_item, :string
    field :allocated, :decimal
    belongs_to :office, FinancialTracking.Tracker.Office
    belongs_to :parent_line_item, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(executive_budget, attrs) do
    executive_budget
    |> cast(attrs, [:line_item, :allocated, :office_id, :parent_line_item_id])
    |> validate_required([:allocated, :office_id])
    |> assoc_constraint(:office)
    |> foreign_key_constraint(:parent_line_item_id)
  end
end
