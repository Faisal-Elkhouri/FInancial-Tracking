defmodule FinancialTracking.Repo do
  use Ecto.Repo,
    otp_app: :financial_tracking,
    adapter: Ecto.Adapters.Postgres
end
