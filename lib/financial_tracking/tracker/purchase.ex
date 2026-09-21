defmodule FinancialTracking.Tracker.Purchase do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          amount: Decimal.t() | nil,
          origin_office_id: integer() | nil,
          origin_office:
            FinancialTracking.Tracker.Office.t() | Ecto.Association.NotLoaded.t() | nil,
          is_tax: boolean() | nil,
          includes_tax: boolean() | nil,
          purchased_at: DateTime.t() | nil,
          slbo_project_code: integer() | nil,
          concur_expense_report: String.t() | nil,
          notes: String.t() | nil,
          event: integer() | nil,
          deleted: boolean(),
          deleted_on: DateTime.t() | nil,
          single_purchases:
            [FinancialTracking.Tracker.SinglePurchase.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "purchases" do
    field :name, :string
    field :amount, :decimal
    belongs_to :origin_office, FinancialTracking.Tracker.Office
    field :is_tax, :boolean
    field :includes_tax, :boolean
    field :purchased_at, :utc_datetime
    field :slbo_project_code, :integer
    field :concur_expense_report, :string
    field :notes, :string
    # Event can be a not-event. Figure out how to do this later
    field :event, :integer
    field :deleted, :boolean, default: false
    field :deleted_on, :utc_datetime

    # Zero or more. The FK is on_delete: :restrict at the DB level, so no
    # :on_delete option here — a purchase with singles can't be deleted.
    has_many :single_purchases, FinancialTracking.Tracker.SinglePurchase,
      foreign_key: :big_purchase_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [
      :name,
      :amount,
      :origin_office_id,
      :is_tax,
      :includes_tax,
      :purchased_at,
      :slbo_project_code
    ])
    |> validate_required([:name])
    |> foreign_key_constraint(:origin_office_id)
  end
end
