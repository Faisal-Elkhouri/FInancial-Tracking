defmodule FinancialTracking.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `FinancialTracking.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Office access is deliberately *not* cached here: `Accounts.office_roles/1`
  reads it fresh on each call, so revoking access takes effect on the user's
  next action rather than their next login.
  """

  alias FinancialTracking.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Whether the scope's user was an admin when the scope was built.

  Good enough for deciding what to *show*. The Accounts admin functions
  re-check against the database before acting.
  """
  def admin?(%__MODULE__{user: %User{admin: admin}}), do: admin
  def admin?(_scope), do: false
end
