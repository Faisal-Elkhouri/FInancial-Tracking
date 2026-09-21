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

      # Financial records must never be silently orphaned (see
      # RestrictFinancialFks): deleting a purchase that single purchases
      # still point at should fail loudly.
      add :big_purchase_id, references(:purchases, on_delete: :restrict)

      timestamps(type: :utc_datetime)
    end

    create index(:single_purchases, [:big_purchase_id])
  end
end
