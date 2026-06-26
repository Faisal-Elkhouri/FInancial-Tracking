defmodule FinancialTracking.Utilites do
  @moduledoc """
  Miscellaneous functions
  """
  @app :financial_tracking

  @doc """
  Returns all the children of an office recursively
  """
  def get_office_with_children(id) do
    case Repo.get(Office, id) do
      nil -> {:error, :not_found}
      office -> {:ok, Repo.preload(office, :children)}
    end
  end

end
