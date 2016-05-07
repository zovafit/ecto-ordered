Logger.configure level: :error
Application.put_env(:ecto_ordered, EctoOrderedTest.Repo, pool: Ecto.Adapters.SQL.Sandbox,
                    database: "ecto_ordered_test",
                    url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost/ecto_ordered_test")

Code.require_file "test_migrations.exs", __DIR__
defmodule EctoOrderedTest.Repo do
  use Ecto.Repo, otp_app: :ecto_ordered,
                 adapter: Ecto.Adapters.Postgres
end

defmodule EctoOrdered.TestCase do
  use ExUnit.CaseTemplate

  defmacro debug(do: block) do
    quote do
      Logger.configure level: :debug
      unquote(block)
      Logger.configure level: :error
    end
  end

  using do
    quote do
      import EctoOrdered.TestCase, only: :macros
    end
  end

end

EctoOrderedTest.Repo.start_link
_ = Ecto.Migrator.up(EctoOrderedTest.Repo, 0, EctoOrderedTest.Migrations)
Ecto.Adapters.SQL.Sandbox.mode(EctoOrderedTest.Repo, :manual)

ExUnit.configure(exclude: [skip: true])
ExUnit.start()
