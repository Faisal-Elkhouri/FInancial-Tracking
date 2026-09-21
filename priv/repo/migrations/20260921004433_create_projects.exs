defmodule FinancialTracking.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :title, :string

      timestamps(type: :utc_datetime)
    end
  end
end
