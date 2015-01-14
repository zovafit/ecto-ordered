Logger.configure level: :debug
alias Ecto.Adapters.Postgres
Application.put_env(:ecto_ordered, EctoOrderedTest.Repo, url: "ecto://postgres:postgres@localhost/ecto_ordered_test")

setup_cmds = [
  ~s(psql -U postgres -c "DROP DATABASE IF EXISTS ecto_ordered_test;"),
  ~s(psql -U postgres -c "CREATE DATABASE ecto_ordered_test TEMPLATE=template0 ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';")
]

defmodule EctoOrderedTest.Repo do
  use Ecto.Repo, otp_app: :ecto_ordered,
                 adapter: Ecto.Adapters.Postgres
end

Enum.each(setup_cmds, fn(cmd) ->
  key = :ecto_setup_cmd_output
  Process.put(key, "")
  status = Mix.Shell.cmd(cmd, fn(data) ->
    current = Process.get(key)
    Process.put(key, current <> data)
  end)

  if status != 0 do
    IO.puts """
    Test setup command error'd:
    #{cmd}
    With:
    #{Process.get(key)}
    Please verify the user "postgres" exists and it has permissions
    to create databases. If not, you can create a new user with:
    createuser postgres --no-password -d
    """
    System.halt(1)
  end
end)


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

  setup do
    Logger.configure level: :error
    setup_database = [
      "DROP TABLE IF EXISTS model",
      "DROP TABLE IF EXISTS scoped_model",
      "CREATE TABLE model (id serial PRIMARY KEY, title varchar(100), position integer)",
      "CREATE TABLE scoped_model (id serial PRIMARY KEY, title varchar(100), scope integer,scoped_position integer)",
      # "ALTER TABLE model ADD CONSTRAINT position_unique UNIQUE (position)",
      # "ALTER TABLE scoped_model ADD CONSTRAINT scoped_position_unique UNIQUE (scoped_position, scope)",
    ]

    {:ok, _pid} = EctoOrderedTest.Repo.start_link

    Enum.each(setup_database, fn(sql) ->
      result = Postgres.query(EctoOrderedTest.Repo, sql, [])
      if match?({:error, _}, result) do
        IO.puts("Test database setup SQL error'd: `#{sql}`")
        IO.inspect(result)
        System.halt(1)
      end
    end)
    on_exit fn ->
      Logger.configure level: :debug
    end
  end
end

ExUnit.start
