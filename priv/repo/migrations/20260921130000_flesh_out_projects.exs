defmodule FinancialTracking.Repo.Migrations.FleshOutProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # The changeset already requires a title; make the DB agree.
      modify :title, :string, null: false, from: {:string, null: true}

      add :description, :text
      add :status, :string, null: false, default: "active"
      add :starts_on, :date
      add :ends_on, :date
      add :budget, :decimal
    end

    create constraint(:projects, :projects_status_valid,
             check: "status IN ('planned', 'active', 'completed', 'cancelled')"
           )

    create constraint(:projects, :projects_dates_ordered,
             check: "starts_on IS NULL OR ends_on IS NULL OR ends_on >= starts_on"
           )

    # Which offices work on a project. Many-to-many: a project has one or more
    # offices, and an office can serve several projects. Purchases are tied to
    # an office through purchases.origin_office_id, not to this table.
    create table(:project_offices, primary_key: false) do
      # A link row means nothing without its project, so it goes with it.
      # (Projects are soft-deleted in practice; this only fires on a hard delete.)
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # Restrict, like every other reference to offices: an office can't be
      # deleted while a project is still assigned to it. Unassign it first.
      add :office_id, references(:offices, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Also serves "offices of a project" lookups (leading column).
    create unique_index(:project_offices, [:project_id, :office_id])

    # Serves "projects of an office" and the FK check on office delete.
    create index(:project_offices, [:office_id])
  end
end
