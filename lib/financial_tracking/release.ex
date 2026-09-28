defmodule FinancialTracking.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :financial_tracking

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates an admin account and prints its temporary password. This is how the
  first admin is made, since accounts are otherwise created by an admin.

  With the prod Compose stack, run it in the one-shot `migrate` container
  (it has the database secrets and exits when done):

      docker compose -f compose.prod.yaml run --rm migrate \\
        /app/bin/financial_tracking eval 'FinancialTracking.Release.create_admin("you@example.com")'

  The password is printed once and must be changed at first log in. Only the
  Repo is started, not the web server, like `migrate/0`.
  """
  def create_admin(email) when is_binary(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(FinancialTracking.Repo, fn _repo ->
        FinancialTracking.Accounts.bootstrap_admin(email)
      end)

    case result do
      {:ok, {user, password}} ->
        IO.puts("Created admin #{user.email} with temporary password: #{password}")

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        IO.puts(:stderr, "Could not create admin #{email}: #{inspect(errors)}")
        System.halt(1)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
