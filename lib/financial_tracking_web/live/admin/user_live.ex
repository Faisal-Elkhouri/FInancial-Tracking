defmodule FinancialTrackingWeb.Admin.UserLive do
  @moduledoc """
  Manages one account: its email, admin rights, password reset, deactivation,
  and which offices it can access.

  Access granted on an office also covers all of its sub-offices, so each
  grant shows how many sub-offices it reaches.

  Admin only (see the `:require_admin` live_session in the router).
  """

  use FinancialTrackingWeb, :live_view

  import FinancialTrackingWeb.Admin.Components

  alias FinancialTracking.Accounts
  alias FinancialTracking.Accounts.OfficeMembership
  alias FinancialTracking.Tracker
  alias FinancialTrackingWeb.UserAuth

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(scope, id)
    offices = Tracker.list_offices(scope)

    {:ok,
     socket
     |> assign(:page_title, user.email)
     |> assign(:user, user)
     |> assign(:self?, user.id == scope.user.id)
     |> assign(:offices, offices)
     |> assign(:sub_office_counts, sub_office_counts(offices))
     |> assign(:issued, nil)
     |> assign(:email_form, to_form(Accounts.change_user_email(user)))
     |> assign(:grant_form, to_form(%{"office_id" => nil, "role" => "viewer"}, as: :grant))
     |> stream_configure(:memberships, dom_id: &"office-access-#{&1.office_id}")
     |> stream(:memberships, user.office_memberships)}
  end

  ## Account

  @impl true
  def handle_event("validate_email", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_email(params, validate_unique: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, :email_form, form)}
  end

  def handle_event("update_email", %{"user" => params}, socket) do
    case Accounts.update_user_email(socket.assigns.current_scope, socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:page_title, user.email)
         |> assign(:email_form, to_form(Accounts.change_user_email(user)))
         |> put_flash(:info, "Email changed to #{user.email}.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("set_admin", %{"admin" => admin}, socket) do
    admin = admin == "true"

    case Accounts.set_admin(socket.assigns.current_scope, socket.assigns.user, admin) do
      {:ok, user} ->
        message = if admin, do: "is now an admin.", else: "is no longer an admin."

        {:noreply,
         socket
         |> assign(:user, user)
         |> put_flash(:info, "#{user.email} #{message}")}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("reset_password", _params, socket) do
    case Accounts.reset_user_password(socket.assigns.current_scope, socket.assigns.user) do
      {:ok, {user, password, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:issued, %{email: user.email, password: password})}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("dismiss_password", _params, socket) do
    {:noreply, assign(socket, :issued, nil)}
  end

  def handle_event("deactivate", _params, socket) do
    case Accounts.deactivate_user(socket.assigns.current_scope, socket.assigns.user) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> assign(:user, user)
         |> put_flash(:info, "#{user.email} has been deactivated and logged out.")}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("reactivate", _params, socket) do
    case Accounts.reactivate_user(socket.assigns.current_scope, socket.assigns.user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> put_flash(:info, "#{user.email} can log in again.")}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  ## Office access

  def handle_event("grant", %{"grant" => %{"office_id" => office_id, "role" => role}}, socket) do
    %{current_scope: scope, user: user} = socket.assigns

    with {:ok, office} <- find_office(socket.assigns.offices, office_id),
         {:ok, membership} <- Accounts.grant_office_access(scope, user, office, role) do
      {:noreply,
       socket
       |> assign(:grant_form, to_form(%{"office_id" => nil, "role" => role}, as: :grant))
       |> stream_insert(:memberships, %{membership | office: office})}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Choose an office to grant access to.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Choose whether they can view or edit.")}

      {:error, reason} ->
        {:noreply, put_error(socket, reason)}
    end
  end

  def handle_event("revoke", %{"office-id" => office_id}, socket) do
    %{current_scope: scope, user: user} = socket.assigns

    with {:ok, office} <- find_office(socket.assigns.offices, office_id),
         :ok <- Accounts.revoke_office_access(scope, user, office) do
      {:noreply, stream_delete_by_dom_id(socket, :memberships, "office-access-#{office.id}")}
    else
      :error -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_error(socket, reason)}
    end
  end

  defp find_office(offices, office_id) do
    case Enum.find(offices, &(Integer.to_string(&1.id) == office_id)) do
      nil -> :error
      office -> {:ok, office}
    end
  end

  defp put_error(socket, :own_account),
    do: put_flash(socket, :error, "You can't do that to your own account.")

  defp put_error(socket, :unauthorized),
    do: put_flash(socket, :error, "You don't have access to do that.")

  # How many offices sit below each office, at any depth. `seen` guards
  # against a cycle in the office hierarchy.
  defp sub_office_counts(offices) do
    children = Enum.group_by(offices, & &1.parent_id, & &1.id)

    Map.new(offices, fn office ->
      {office.id, office.id |> descendants(children, MapSet.new([office.id])) |> MapSet.size()}
    end)
  end

  defp descendants(office_id, children, seen) do
    children
    |> Map.get(office_id, [])
    |> Enum.reject(&MapSet.member?(seen, &1))
    |> Enum.reduce(MapSet.new(), fn child, acc ->
      acc
      |> MapSet.put(child)
      |> MapSet.union(descendants(child, children, MapSet.put(seen, child)))
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/admin/users"}
        id="back-to-users"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 transition-colors hover:text-base-content"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> All users
      </.link>

      <.header>
        <span class="break-all">{@user.email}</span>
        <:subtitle>
          <span id="user-status" class="mt-1 flex flex-wrap gap-1">
            <.status_badge :if={@user.admin} kind={:admin} />
            <.status_badge :if={@user.deactivated_at} kind={:deactivated} />
            <.status_badge
              :if={!@user.deactivated_at && @user.must_change_password}
              kind={:temporary_password}
            />
            <.status_badge
              :if={!@user.deactivated_at && !@user.must_change_password}
              kind={:active}
            />
          </span>
        </:subtitle>
      </.header>

      <.temporary_password
        :if={@issued}
        email={@issued.email}
        password={@issued.password}
        on_dismiss={JS.push("dismiss_password")}
      />

      <.section id="account-section" title="Account">
        <.form
          for={@email_form}
          id="email-form"
          phx-change="validate_email"
          phx-submit="update_email"
          class="flex flex-col gap-2 sm:flex-row sm:items-start"
        >
          <div class="flex-1">
            <.input
              field={@email_form[:email]}
              type="email"
              aria-label="Email"
              autocomplete="off"
              spellcheck="false"
              required
            />
          </div>
          <.button id="email-submit" phx-disable-with="Saving...">Change email</.button>
        </.form>

        <p :if={@self?} class="text-sm text-base-content/60">
          This is your account, so you can't remove your own admin rights or deactivate it.
        </p>

        <div class="flex flex-wrap gap-2">
          <.button
            :if={!@user.admin}
            id="make-admin"
            phx-click="set_admin"
            phx-value-admin="true"
            data-confirm={"Give #{@user.email} full access to every office and to user management?"}
          >
            <.icon name="hero-shield-check-micro" class="size-4" /> Make admin
          </.button>
          <.button
            :if={@user.admin}
            id="remove-admin"
            phx-click="set_admin"
            phx-value-admin="false"
            disabled={@self?}
          >
            <.icon name="hero-shield-exclamation-micro" class="size-4" /> Remove admin
          </.button>
          <.button
            id="reset-password"
            phx-click="reset_password"
            data-confirm={"Replace #{@user.email}'s password with a new temporary one and log them out everywhere?"}
          >
            <.icon name="hero-key-micro" class="size-4" /> Reset password
          </.button>
          <.button
            :if={!@user.deactivated_at}
            id="deactivate"
            phx-click="deactivate"
            disabled={@self?}
            class="btn btn-soft btn-error"
            data-confirm={"Deactivate #{@user.email}? They'll be logged out and unable to log in."}
          >
            <.icon name="hero-no-symbol-micro" class="size-4" /> Deactivate
          </.button>
          <.button :if={@user.deactivated_at} id="reactivate" phx-click="reactivate">
            <.icon name="hero-arrow-uturn-left-micro" class="size-4" /> Reactivate
          </.button>
        </div>
      </.section>

      <.section id="access-section" title="Office access">
        <:description>
          <%= if @user.admin do %>
            Admins can see and edit every office. The grants below take effect if admin rights are removed.
          <% else %>
            Access to an office includes all of its sub-offices. Viewers can see records; editors can also change them.
          <% end %>
        </:description>

        <ul
          id="office-access"
          phx-update="stream"
          class="divide-y divide-base-content/10 rounded-box border border-base-content/10"
        >
          <li
            id="office-access-empty"
            class="hidden px-3 py-6 text-center text-sm text-base-content/60 only:block"
          >
            No office access yet.
          </li>
          <li
            :for={{dom_id, membership} <- @streams.memberships}
            id={dom_id}
            class="flex items-center gap-3 px-3 py-2 transition-colors hover:bg-base-content/3"
          >
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium">{membership.office.name}</p>
              <p class="text-xs text-base-content/60">
                {sub_office_label(Map.get(@sub_office_counts, membership.office_id, 0))}
              </p>
            </div>
            <span class={[
              "rounded-full px-2 py-0.5 text-xs font-medium",
              if(membership.role == :editor,
                do: "bg-info/12 text-info",
                else: "bg-base-content/8 text-base-content/70"
              )
            ]}>
              {role_label(membership.role)}
            </span>
            <button
              type="button"
              id={"revoke-#{membership.office_id}"}
              phx-click="revoke"
              phx-value-office-id={membership.office_id}
              data-confirm={"Remove access to #{membership.office.name}?"}
              class="rounded-field p-1.5 text-base-content/50 transition-colors hover:bg-error/10 hover:text-error"
            >
              <.icon name="hero-trash-micro" class="size-4" />
              <span class="sr-only">Remove access to {membership.office.name}</span>
            </button>
          </li>
        </ul>

        <p :if={@offices == []} id="no-offices" class="text-sm text-base-content/60">
          There are no offices to grant access to yet.
        </p>

        <.form
          :if={@offices != []}
          for={@grant_form}
          id="grant-form"
          phx-submit="grant"
          class="grid gap-2 sm:grid-cols-[1fr_9rem_auto] sm:items-start"
        >
          <.input
            field={@grant_form[:office_id]}
            type="select"
            aria-label="Office"
            prompt="Choose an office"
            options={Enum.map(@offices, &{&1.name, &1.id})}
          />
          <.input
            field={@grant_form[:role]}
            type="select"
            aria-label="Role"
            options={Enum.map(OfficeMembership.roles(), &{role_label(&1), &1})}
          />
          <.button variant="primary" id="grant-submit" phx-disable-with="Granting...">
            Grant access
          </.button>
        </.form>
      </.section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :description
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-heading"}
      class="space-y-3 rounded-box border border-base-content/10 p-4"
    >
      <div>
        <h2 id={"#{@id}-heading"} class="text-sm font-medium">{@title}</h2>
        <p :if={@description != []} class="mt-0.5 text-sm text-base-content/60">
          {render_slot(@description)}
        </p>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp role_label(:viewer), do: "Can view"
  defp role_label(:editor), do: "Can edit"

  defp sub_office_label(0), do: "This office only"
  defp sub_office_label(1), do: "Includes 1 sub-office"
  defp sub_office_label(count), do: "Includes #{count} sub-offices"
end
