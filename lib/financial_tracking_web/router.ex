defmodule FinancialTrackingWeb.Router do
  use FinancialTrackingWeb, :router

  import FinancialTrackingWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FinancialTrackingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", FinancialTrackingWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:financial_tracking, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FinancialTrackingWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  # Everything in the app requires a logged-in user. There is no public page
  # apart from the log in form below.
  scope "/", FinancialTrackingWeb do
    pipe_through [:browser, :require_authenticated_user]

    # :require_password_changed keeps a user who is still on an admin-issued
    # temporary password on the settings page (which it lets through) until
    # they choose their own.
    live_session :require_authenticated_user,
      on_mount: [
        {FinancialTrackingWeb.UserAuth, :require_authenticated},
        {FinancialTrackingWeb.UserAuth, :require_password_changed}
      ] do
      live "/", HomeLive
      live "/purchases", PurchasesLive
      live "/users/settings", UserLive.Settings, :edit
    end

    # User management. Its own live_session so the admin check applies to
    # these pages only; moving between here and the app is a full page load.
    live_session :require_admin,
      on_mount: [
        {FinancialTrackingWeb.UserAuth, :require_authenticated},
        {FinancialTrackingWeb.UserAuth, :require_password_changed},
        {FinancialTrackingWeb.UserAuth, :require_admin}
      ] do
      live "/admin/users", Admin.UsersLive
      live "/admin/users/:id", Admin.UserLive
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # No sign-up or magic-link routes: accounts are created by an admin, and
  # production has no email delivery.
  scope "/", FinancialTrackingWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{FinancialTrackingWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
