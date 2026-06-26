defmodule FinancialTracking.Tracker.Offices do
  use Ecto.Schema
  import Ecto.Changeset

  schema "offices" do
    field :name, :string
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(offices, attrs) do
    offices
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
