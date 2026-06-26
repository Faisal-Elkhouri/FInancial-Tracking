defmodule FinancialTracking.Tracker.ExecutiveBudget do
  use Ecto.Schema
  import Ecto.Changeset

  schema "executive_budget" do
    field :allocated, :integer

    belongs_to :office, FinancialTracking.Tracker.Offices

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(executive_budget, attrs) do
    executive_budget
    |> cast(attrs, [:allocated, :office_id])
    |> validate_required([:allocated, :office_id])
    |> assoc_constraint(:office)
  end
end
