defmodule FinancialTracking.Tracker.ExecutiveBudget do
  use Ecto.Schema
  import Ecto.Changeset

  schema "executive_budget" do
    field :line_item, :string
    field :allocated, :decimal
    belongs_to :office, FinancialTracking.Tracker.Offices
    belongs_to :parent_line_item, __MODULE__

    timestamps(type: :utc_datetime)
  end


  @doc false
  def changeset(executive_budget, attrs) do
    executive_budget
    |> cast(attrs, [:line_item, :allocated, :office_id, :parent_line_item])
    |> validate_required([:allocated, :office_id])
    |> assoc_constraint(:office)
  end
end
