defmodule FinancialTrackingWeb.HomeLive do
  use FinancialTrackingWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Home")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="home"></div>
    </Layouts.app>
    """
  end
end
