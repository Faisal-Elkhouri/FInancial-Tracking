defmodule FinancialTracking.Utilites do

  @doc """
  Returns all the children of an office recursively
  """
  def get_office_with_children(id) do
    case FinancialTracking.Repo.get(Office, id) do
      nil -> {:error, :not_found}
      office -> {:ok, FinancialTracking.Repo.preload(office, :children)}
    end
  end

end
