defmodule FinancialTrackingWeb.Admin.Components do
  @moduledoc """
  Pieces shared by the user management pages.
  """

  use FinancialTrackingWeb, :html

  @doc """
  Shows a temporary password once, right after an admin issues it, with a
  button to copy it. It is never stored in plain text, so this is the only
  chance to see it.
  """
  attr :email, :string, required: true
  attr :password, :string, required: true
  attr :on_dismiss, :any, required: true, doc: "the `phx-click` for the dismiss button"

  def temporary_password(assigns) do
    ~H"""
    <div
      id="temp-password"
      role="status"
      class="space-y-3 rounded-box border border-success/40 bg-success/8 p-4"
    >
      <div class="flex items-start gap-3">
        <.icon name="hero-key" class="mt-0.5 size-5 shrink-0 text-success" />
        <div class="min-w-0 flex-1 text-sm">
          <p class="font-medium">Temporary password for {@email}</p>
          <p class="text-base-content/70">
            Send it to them privately. It won't be shown again, and they'll choose their own
            when they log in.
          </p>
        </div>
        <button
          type="button"
          id="temp-password-dismiss"
          phx-click={@on_dismiss}
          class="-m-1 rounded-field p-1 text-base-content/60 transition-colors hover:bg-base-content/8 hover:text-base-content"
        >
          <.icon name="hero-x-mark" class="size-4" />
          <span class="sr-only">Dismiss</span>
        </button>
      </div>

      <div class="flex items-center gap-2">
        <code
          id="temp-password-value"
          class="min-w-0 flex-1 truncate select-all rounded-field border border-base-content/15 bg-base-100 px-3 py-2 font-mono text-sm"
        >
          {@password}
        </code>
        <button
          type="button"
          id="temp-password-copy"
          phx-click={JS.dispatch("phx:copy", detail: %{text: @password})}
          class="group inline-flex shrink-0 items-center gap-1.5 rounded-field border border-base-content/15 bg-base-100 px-3 py-2 text-sm transition-colors hover:bg-base-200 active:scale-[0.98]"
        >
          <.icon name="hero-clipboard-document-micro" class="size-4 group-data-copied:hidden" />
          <.icon name="hero-check-micro" class="hidden size-4 text-success group-data-copied:inline" />
          <span class="group-data-copied:hidden">Copy</span>
          <span class="hidden group-data-copied:inline">Copied</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  A small pill describing a user's state.
  """
  attr :kind, :atom, values: [:admin, :active, :deactivated, :temporary_password]
  attr :rest, :global

  def status_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap",
        badge_class(@kind)
      ]}
      {@rest}
    >
      {badge_label(@kind)}
    </span>
    """
  end

  defp badge_class(:admin), do: "bg-primary/12 text-primary"
  defp badge_class(:active), do: "bg-success/12 text-success"
  defp badge_class(:deactivated), do: "bg-base-content/8 text-base-content/60"
  defp badge_class(:temporary_password), do: "bg-warning/15 text-warning"

  defp badge_label(:admin), do: "Admin"
  defp badge_label(:active), do: "Active"
  defp badge_label(:deactivated), do: "Deactivated"
  defp badge_label(:temporary_password), do: "Temporary password"
end
