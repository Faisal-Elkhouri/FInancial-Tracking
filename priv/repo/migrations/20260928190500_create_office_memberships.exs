defmodule FinancialTracking.Repo.Migrations.CreateOfficeMemberships do
  use Ecto.Migration

  # Grants a user access to an office. Access to an office also covers all of
  # its sub-offices; that inheritance is resolved in Accounts.office_roles/1,
  # not stored here.
  def change do
    create table(:office_memberships) do
      # A grant means nothing without its user. (Users are deactivated in
      # practice; this only fires on a hard delete.)
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Restrict, like every other reference to offices: an office can't be
      # deleted while someone still has access to it. Revoke access first.
      add :office_id, references(:offices, on_delete: :restrict), null: false

      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:office_memberships, :office_memberships_role_valid,
             check: "role IN ('viewer', 'editor')"
           )

    # One grant per (user, office); also serves "offices of a user" lookups.
    create unique_index(:office_memberships, [:user_id, :office_id])

    # Serves "members of an office" and the FK check on office delete.
    create index(:office_memberships, [:office_id])
  end
end
