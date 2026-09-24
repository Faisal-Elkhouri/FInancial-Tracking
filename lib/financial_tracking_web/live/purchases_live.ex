defmodule FinancialTrackingWeb.PurchasesLive do
  @moduledoc """
  Table of purchases for a single office. The office is picked from a dropdown
  and kept in the URL (`/purchases?office_id=3`), so a selection can be
  bookmarked or shared.
  """

  use FinancialTrackingWeb, :live_view

  alias FinancialTracking.Tracker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Purchases")
     |> assign(:offices, Tracker.list_offices())
     |> stream_configure(:purchases, dom_id: &"purchases-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    office_id = params["office_id"]

    case find_office(socket.assigns.offices, office_id) do
      {:ok, office} ->
        {:noreply, show_office(socket, office)}

      :error ->
        {:noreply,
         socket
         |> show_office(nil)
         |> put_flash(:error, "That office doesn't exist.")
         |> push_patch(to: ~p"/purchases")}
    end
  end

  @impl true
  def handle_event("select_office", %{"office_id" => ""}, socket) do
    {:noreply, push_patch(socket, to: ~p"/purchases")}
  end

  def handle_event("select_office", %{"office_id" => office_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/purchases?#{[office_id: office_id]}")}
  end

  # Matches against the already-loaded offices rather than querying, which
  # also means a malformed id (e.g. "abc") is just "not found".
  defp find_office(_offices, nil), do: {:ok, nil}
  defp find_office(_offices, ""), do: {:ok, nil}

  defp find_office(offices, office_id) do
    case Enum.find(offices, &(Integer.to_string(&1.id) == office_id)) do
      nil -> :error
      office -> {:ok, office}
    end
  end

  defp show_office(socket, office) do
    purchases = if office, do: Tracker.list_office_purchases(office), else: []

    socket
    |> assign(:office, office)
    |> assign(:form, to_form(%{"office_id" => office && office.id}))
    |> assign(:purchase_count, length(purchases))
    |> assign(:total, total(purchases))
    |> stream(:purchases, purchases, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Purchases
        <:subtitle :if={@office}>
          {@purchase_count} {if @purchase_count == 1, do: "purchase", else: "purchases"}, {format_amount(
            @total
          )} total
        </:subtitle>
      </.header>

      <p :if={@offices == []} id="no-offices">
        There are no offices yet. Add an office before viewing purchases.
      </p>

      <.form :if={@offices != []} for={@form} id="office-form" phx-change="select_office">
        <.input
          field={@form[:office_id]}
          type="select"
          label="Office"
          prompt="Choose an office"
          options={Enum.map(@offices, &{&1.name, &1.id})}
        />
      </.form>

      <p :if={@offices != [] && is_nil(@office)} id="no-office-selected">
        Choose an office to see its purchases.
      </p>

      <p :if={@office && @purchase_count == 0} id="no-purchases">
        {@office.name} has no purchases.
      </p>

      <div :if={@office && @purchase_count > 0} class="overflow-x-auto">
        <.table id="purchases" rows={@streams.purchases}>
          <:col :let={{_id, purchase}} label="Date">{format_date(purchase.purchased_at)}</:col>
          <:col :let={{_id, purchase}} label="Name">{purchase.name}</:col>
          <:col :let={{_id, purchase}} label="Amount">{format_amount(purchase.amount)}</:col>
          <:col :let={{_id, purchase}} label="Tax purchase">{yes_no(purchase.is_tax)}</:col>
          <:col :let={{_id, purchase}} label="Includes tax">{yes_no(purchase.includes_tax)}</:col>
          <:col :let={{_id, purchase}} label="SLBO code">{purchase.slbo_project_code}</:col>
          <:col :let={{_id, purchase}} label="Concur report">
            {purchase.concur_expense_report}
          </:col>
          <:col :let={{_id, purchase}} label="Notes">{purchase.notes}</:col>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  # Purchases without an amount count as zero.
  defp total(purchases) do
    Enum.reduce(purchases, Decimal.new(0), fn purchase, sum ->
      Decimal.add(sum, purchase.amount || 0)
    end)
  end

  defp format_amount(nil), do: "—"

  defp format_amount(amount),
    do: "$" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))

  defp format_date(nil), do: "—"
  defp format_date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"
  defp yes_no(nil), do: "—"
end
