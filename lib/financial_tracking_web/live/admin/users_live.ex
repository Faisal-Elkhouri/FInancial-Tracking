defmodule FinancialTrackingWeb.Admin.UsersLive do
  @moduledoc """
  Lists every account and creates new ones. A new account gets a generated
  temporary password, shown once here for the admin to pass on.

  Admin only (see the `:require_admin` live_session in the router).
  """

  use FinancialTrackingWeb, :live_view

  import FinancialTrackingWeb.Admin.Components

  alias FinancialTracking.Accounts
  alias FinancialTracking.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:user_count, length(users))
     |> assign(:issued, nil)
     |> assign_new_user_form()
     |> stream(:users, users)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      %User{}
      |> Accounts.change_user_email(params, validate_unique: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create", %{"user" => params}, socket) do
    case Accounts.create_user(socket.assigns.current_scope, params) do
      {:ok, {user, password}} ->
        {:noreply,
         socket
         |> assign(:issued, %{email: user.email, password: password})
         |> update(:user_count, &(&1 + 1))
         |> assign_new_user_form()
         |> stream_insert(:users, %{user | office_memberships: []}, at: 0)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have access to do that.")}
    end
  end

  def handle_event("dismiss_password", _params, socket) do
    {:noreply, assign(socket, :issued, nil)}
  end

  defp assign_new_user_form(socket) do
    assign(socket, :form, to_form(Accounts.change_user_email(%User{})))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Users
        <:subtitle>
          {@user_count} {if @user_count == 1, do: "account", else: "accounts"}. Open one to manage its office access.
        </:subtitle>
      </.header>

      <section
        aria-labelledby="new-user-heading"
        class="rounded-box border border-base-content/10 p-4"
      >
        <h2 id="new-user-heading" class="text-sm font-medium">Add a user</h2>
        <p class="mt-0.5 text-sm text-base-content/60">
          They'll get a temporary password to change when they first log in.
        </p>

        <.form
          for={@form}
          id="new-user-form"
          phx-change="validate"
          phx-submit="create"
          class="mt-3 flex flex-col gap-2 sm:flex-row sm:items-start"
        >
          <div class="flex-1">
            <.input
              field={@form[:email]}
              type="email"
              placeholder="name@example.com"
              aria-label="Email"
              autocomplete="off"
              spellcheck="false"
              required
            />
          </div>
          <.button variant="primary" id="new-user-submit" phx-disable-with="Creating...">
            Create account
          </.button>
        </.form>
      </section>

      <.temporary_password
        :if={@issued}
        email={@issued.email}
        password={@issued.password}
        on_dismiss={JS.push("dismiss_password")}
      />

      <.table id="users" rows={@streams.users} caption="Users">
        <:col :let={{_id, user}} label="Email" icon="hero-envelope-micro">
          <.link
            navigate={~p"/admin/users/#{user}"}
            class="font-medium underline-offset-2 hover:underline"
          >
            {user.email}
          </.link>
        </:col>
        <:col :let={{_id, user}} label="Offices" align="right" icon="hero-hashtag-micro">
          {if user.admin, do: "All", else: length(user.office_memberships)}
        </:col>
        <:col :let={{_id, user}} label="Status" icon="hero-check-circle-micro">
          <span class="flex flex-wrap gap-1">
            <.status_badge :if={user.admin} kind={:admin} />
            <.status_badge :if={user.deactivated_at} kind={:deactivated} />
            <.status_badge
              :if={!user.deactivated_at && user.must_change_password}
              kind={:temporary_password}
            />
            <.status_badge
              :if={!user.deactivated_at && !user.must_change_password}
              kind={:active}
            />
          </span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end
end
