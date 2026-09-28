defmodule FinancialTracking.Accounts.OfficeMembership do
  @moduledoc """
  Grants a user access to an office, and through it to all of the office's
  sub-offices. One row per (user, office) pair.

  A `:viewer` can see the office's records; an `:editor` can also change them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type role :: :viewer | :editor

  @type t :: %__MODULE__{
          id: integer() | nil,
          role: role() | nil,
          user_id: integer() | nil,
          user: FinancialTracking.Accounts.User.t() | Ecto.Association.NotLoaded.t() | nil,
          office_id: integer() | nil,
          office: FinancialTracking.Tracker.Office.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @roles [:viewer, :editor]

  schema "office_memberships" do
    field :role, Ecto.Enum, values: @roles
    belongs_to :user, FinancialTracking.Accounts.User
    belongs_to :office, FinancialTracking.Tracker.Office

    timestamps(type: :utc_datetime)
  end

  @doc "The roles a membership can grant, weakest first."
  def roles, do: @roles

  @doc """
  `user_id` and `office_id` are set by `Accounts.grant_office_access/4`, not
  cast, so a form can't grant access to someone else.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> check_constraint(:role, name: :office_memberships_role_valid)
    |> assoc_constraint(:user)
    |> assoc_constraint(:office)
  end
end
