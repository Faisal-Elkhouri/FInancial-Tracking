defmodule FinancialTracking.Repo.Migrations.CreateExecutiveBudget do
  use Ecto.Migration

  def change do
    create table(:executive_budget) do
      add :allocated, :integer

      timestamps(type: :utc_datetime)
    end
  end
end
