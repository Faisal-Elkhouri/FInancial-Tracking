defmodule FinancialTrackingWeb.PageController do
  use FinancialTrackingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
