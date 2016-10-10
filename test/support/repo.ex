defmodule EctoOrderedTest.Repo do
  use Ecto.Repo, otp_app: :ecto_ordered,
    adapter: Ecto.Adapters.Postgres
end
