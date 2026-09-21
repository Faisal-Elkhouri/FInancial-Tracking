defmodule FinancialTracking.Repo.Migrations.AddSoftDelete do
  use Ecto.Migration

  # Soft delete for projects, purchases and single purchases: rows are marked
  # rather than removed, so financial history is never lost. `deleted_on`
  # records when; it stays NULL while `deleted` is false.
  def change do
    for table <- [:projects, :purchases, :single_purchases] do
      alter table(table) do
        add :deleted, :boolean, null: false, default: false
        add :deleted_on, :utc_datetime
      end
    end
  end
end
