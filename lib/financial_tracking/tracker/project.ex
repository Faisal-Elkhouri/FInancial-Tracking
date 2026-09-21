defmodule FinancialTracking.Tracker.Project do
  use Ecto.Schema
  import Ecto.Changeset


  schema "projects" do
    field :title, :string


    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end
