defmodule FinancialTracking.Tracker.ProjectOffice do
  @moduledoc """
  Join row assigning an office to a project. One row per (project, office) pair.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          project_id: integer() | nil,
          office_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key false
  schema "project_offices" do
    belongs_to :project, FinancialTracking.Tracker.Project
    belongs_to :office, FinancialTracking.Tracker.Office

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(project_office, attrs) do
    project_office
    |> cast(attrs, [:project_id, :office_id])
    |> validate_required([:project_id, :office_id])
    |> assoc_constraint(:project)
    |> assoc_constraint(:office)
    |> unique_constraint(:office_id,
      name: :project_offices_project_id_office_id_index,
      message: "is already assigned to this project"
    )
  end
end
