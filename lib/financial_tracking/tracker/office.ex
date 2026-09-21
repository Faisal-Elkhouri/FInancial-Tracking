defmodule FinancialTracking.Tracker.Office do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "offices" do
    field :name, :string
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(office, attrs) do
    office
    |> cast(attrs, [:name, :parent_id])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> foreign_key_constraint(:parent_id)
  end
end
