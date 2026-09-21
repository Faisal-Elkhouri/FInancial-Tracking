defmodule FinancialTracking.Tracker.SinglePurchase do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          projects: String.t() | nil,
          title: String.t() | nil,
          big_purchase_id: integer() | nil,
          big_purchase: FinancialTracking.Tracker.Purchase.t() | Ecto.Association.NotLoaded.t() | nil,
          cost: Decimal.t() | nil,
          link: String.t() | nil,
          purchased_at: DateTime.t() | nil,
          notes: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "single_purchases" do
    field :projects, :string
    field :title, :string
    belongs_to :big_purchase, FinancialTracking.Tracker.Purchase
    field :cost, :decimal
    field :link, :string
    field :purchased_at, :utc_datetime
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(single_purchase, attrs) do
    single_purchase
    |> cast(attrs, [
      :projects,
      :title,
      :big_purchase_id,
      :cost,
      :link,
      :purchased_at,
      :notes
    ])
    |> validate_required([:projects, :title])
    |> validate_number(:cost, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:big_purchase_id)
  end
end
