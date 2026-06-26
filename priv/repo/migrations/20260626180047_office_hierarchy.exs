defmodule FinancialTracking.Repo.Migrations.OfficeHierarchy do
  use Ecto.Migration

  def change do
    alter table(:offices) do
      # Self-reference: an office's parent is another office (references offices.id).
      add :parent_id, references(:offices, on_delete: :restrict)
    end

    create index(:offices, [:parent_id])
  end
end
