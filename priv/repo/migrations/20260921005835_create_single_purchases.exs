defmodule FinancialTracking.Repo.Migrations.CreateSinglePurchases do
  use Ecto.Migration

  def change do
    create table(:single_purchases) do
      add :projects, :string
      add :title, :string
      add :cost, :decimal
      add :link, :string
      add :purchased_at, :utc_datetime
      add :notes, :text

      # A single purchase always belongs to exactly one purchase; a purchase
      # may have any number of them (or none). Financial records must never
      # be silently orphaned (see RestrictFinancialFks): deleting a purchase
      # that single purchases still point at should fail loudly.
      add :big_purchase_id, references(:purchases, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    # Postgres doesn't index the referencing side of an FK. This index serves
    # both `purchase.single_purchases` lookups (a preload is one
    # `WHERE big_purchase_id = ANY(...)` query) and the FK check when a
    # purchase is deleted.
    create index(:single_purchases, [:big_purchase_id])
  end
end
