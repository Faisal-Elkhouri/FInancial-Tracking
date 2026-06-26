defmodule FinancialTracking.Tracker.Purchases do
  use Ecto.Schema
  import Ecto.Changeset

  schema "purchases" do
    field :name, :string
    field :amount, :decimal
    belongs_to :origin_office, FinancialTracking.Tracker.Offices
    field :is_tax, :boolean
    field :includes_tax, :boolean
    field :purchased_at, :utc_datetime
    field :slbo_project_code, :integer
    field :concur_expense_report, :string
    field :notes, :string
    field :event, :integer #Event can be a not-event. Figure out how to do this later


    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(purchases, attrs) do
    purchases
    |> cast(attrs, [:name, :amount, :origin_office_id, :is_tax, :includes_tax,
    :purchased_at, :slbo_project_code])
    |> validate_required([:name])
    |> foreign_key_constraint(:origin_office_id)
  end
end
