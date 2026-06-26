defmodule FinancialTracking.Repo.Migrations.CreateOffices do
  use Ecto.Migration

  def change do
    create table(:offices) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
