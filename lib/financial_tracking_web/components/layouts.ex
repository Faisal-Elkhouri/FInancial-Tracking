defmodule FinancialTrackingWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FinancialTrackingWeb, :html

  alias FinancialTracking.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :full_width, :boolean,
    default: false,
    doc: """
    spans the whole screen instead of a narrow column, for data-heavy pages.
    On large screens the page is also held to the screen height so the last
    child (e.g. a `<.table>`) can scroll inside it.
    """

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={["flex flex-col", @full_width && "lg:h-dvh"]}>
      <.top_nav :if={@current_scope} current_scope={@current_scope} />

      <main class={[
        "px-4 sm:px-6 lg:px-8",
        if(@full_width, do: "flex min-h-0 flex-1 flex-col py-8", else: "py-16")
      ]}>
        <div class={
          if(@full_width,
            do: "flex min-h-0 flex-1 flex-col gap-4",
            else: "mx-auto max-w-2xl space-y-4"
          )
        }>
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # The bar across the top of every page for a logged-in user. On phones the
  # account links collapse to icons (their labels stay for screen readers).
  attr :current_scope, :map, required: true

  defp top_nav(assigns) do
    ~H"""
    <header class="shrink-0 border-b border-base-content/10">
      <nav
        aria-label="Main"
        class="flex h-12 items-center gap-1 px-2 text-sm sm:px-4 lg:px-6"
      >
        <.link
          navigate={~p"/"}
          id="nav-home"
          class={[nav_link_class(), "mr-2 font-semibold text-base-content"]}
        >
          <.icon name="hero-banknotes" class="size-5" />
          <span class="sr-only sm:not-sr-only">Financial Tracking</span>
        </.link>
        <.link navigate={~p"/purchases"} id="nav-purchases" class={nav_link_class()}>
          Purchases
        </.link>
        <.link
          :if={Scope.admin?(@current_scope)}
          navigate={~p"/admin/users"}
          id="nav-admin-users"
          class={nav_link_class()}
        >
          Users
        </.link>

        <div class="ml-auto flex min-w-0 items-center gap-1">
          <span
            id="nav-user-email"
            class="hidden truncate px-2 text-base-content/60 md:inline"
          >
            {@current_scope.user.email}
          </span>
          <.link navigate={~p"/users/settings"} id="nav-settings" class={nav_link_class()}>
            <.icon name="hero-cog-6-tooth-micro" class="size-4 sm:hidden" />
            <span class="sr-only sm:not-sr-only">Settings</span>
          </.link>
          <.link
            href={~p"/users/log-out"}
            method="delete"
            id="nav-log-out"
            class={nav_link_class()}
          >
            <.icon name="hero-arrow-right-start-on-rectangle-micro" class="size-4 sm:hidden" />
            <span class="sr-only sm:not-sr-only">Log out</span>
          </.link>
        </div>
      </nav>
    </header>
    """
  end

  defp nav_link_class do
    "inline-flex shrink-0 items-center gap-2 rounded-field px-2 py-1.5 text-base-content/75 " <>
      "transition-colors duration-150 hover:bg-base-content/6 hover:text-base-content " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
