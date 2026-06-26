defmodule FinancialTracking.Repo.Migrations.Purchases do
  use Ecto.Migration

  def change do
    create table(:purchases) do
      add :name, :string, null: false
      add :amount, :decimal
      add :is_tax, :boolean
      add :includes_tax, :boolean
      add :purchased_at, :utc_datetime
      add :slbo_project_code, :integer
      add :concur_expense_report, :string
      add :notes, :text
      add :event, :integer

      # FK column — matches belongs_to :origin_office (→ origin_office_id)
      add :origin_office_id, references(:offices, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:purchases, [:origin_office_id])
  end
end
