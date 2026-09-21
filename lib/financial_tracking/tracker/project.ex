defmodule FinancialTracking.Tracker.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias FinancialTracking.Tracker.{Office, ProjectOffice}

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          status: :planned | :active | :completed | :cancelled,
          starts_on: Date.t() | nil,
          ends_on: Date.t() | nil,
          budget: Decimal.t() | nil,
          offices: [Office.t()] | Ecto.Association.NotLoaded.t(),
          deleted: boolean(),
          deleted_on: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "projects" do
    field :title, :string
    field :description, :string

    field :status, Ecto.Enum,
      values: [:planned, :active, :completed, :cancelled],
      default: :active

    field :starts_on, :date
    field :ends_on, :date
    field :budget, :decimal
    field :deleted, :boolean, default: false
    field :deleted_on, :utc_datetime

    # Assigned through Tracker.assign_office/2 and unassign_office/2, so the
    # join rows get their own validation and error messages.
    many_to_many :offices, Office, join_through: ProjectOffice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :description, :status, :starts_on, :ends_on, :budget])
    |> validate_required([:title])
    |> validate_number(:budget, greater_than_or_equal_to: 0)
    |> validate_dates_ordered()
    |> check_constraint(:status, name: :projects_status_valid)
    |> check_constraint(:ends_on, name: :projects_dates_ordered)
  end

  defp validate_dates_ordered(changeset) do
    starts_on = get_field(changeset, :starts_on)
    ends_on = get_field(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) == :lt do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end
end
