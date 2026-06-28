defmodule FinancialTracking.Repo.Migrations.AlterExecBudget do
  use Ecto.Migration

  def change do
    alter table(:executive_budget) do
      add :line_item, :string

      # was :integer in create_executive_budget; `from:` keeps it reversible
      modify :allocated, :decimal, from: :integer

      # belongs_to :parent_line_item, __MODULE__ → self-referencing FK
      add :parent_line_item_id,
          references(:executive_budget, on_delete: :nilify_all)
    end

    create index(:executive_budget, [:parent_line_item_id])
  end
end
