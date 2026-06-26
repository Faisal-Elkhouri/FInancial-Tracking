defmodule FinancialTracking.Repo.Migrations.FkOfficeEb do
  use Ecto.Migration

  def change do
    alter table(:executive_budget) do
      add :office_id, references(:offices, on_delete: :nilify_all)
    end

    create index(:executive_budget, [:office_id])
  end
end
