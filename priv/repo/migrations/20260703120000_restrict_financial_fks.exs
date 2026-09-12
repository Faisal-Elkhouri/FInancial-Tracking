defmodule FinancialTracking.Repo.Migrations.RestrictFinancialFks do
  use Ecto.Migration

  # Financial records must never be silently orphaned: deleting an office
  # that purchases or budget line items still point at should fail loudly
  # (reassign or delete the dependents first), not null out the reference.
  #
  # This also fixes an inconsistency on executive_budget.office_id: the
  # changeset requires it, but :nilify_all could set it to NULL at the DB
  # level — the database could hold rows the app considers invalid.
  #
  # Deliberately NOT changed: executive_budget.parent_line_item_id stays
  # :nilify_all — deleting a parent line item promotes its children to
  # top-level, which is the intended behavior.
  def change do
    alter table(:purchases) do
      modify :origin_office_id, references(:offices, on_delete: :restrict),
        from: references(:offices, on_delete: :nilify_all)
    end

    alter table(:executive_budget) do
      modify :office_id, references(:offices, on_delete: :restrict),
        from: references(:offices, on_delete: :nilify_all)
    end
  end
end
