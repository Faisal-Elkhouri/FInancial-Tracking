# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     FinancialTracking.Repo.insert!(%FinancialTracking.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias FinancialTracking.Accounts

# A dev admin to log in with. Accounts are otherwise created by an admin, so
# a fresh database needs one to start from. In production, use
# FinancialTracking.Release.create_admin/1 instead.
dev_admin_email = "admin@example.com"

if Accounts.get_user_by_email(dev_admin_email) do
  IO.puts("Dev admin #{dev_admin_email} already exists.")
else
  {:ok, {_user, password}} = Accounts.bootstrap_admin(dev_admin_email)
  IO.puts("Created dev admin #{dev_admin_email} with temporary password: #{password}")
end
