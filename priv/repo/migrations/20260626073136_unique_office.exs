defmodule FinancialTracking.Repo.Migrations.UniqueOffice do
  use Ecto.Migration

  def change do
    create unique_index(:offices, [:name])
  end
end
