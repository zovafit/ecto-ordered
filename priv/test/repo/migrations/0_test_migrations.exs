defmodule EctoOrderedTest.Migrations do
  use Ecto.Migration

  def change do
    create table(:model) do
      add :title, :string
      add :rank, :integer
    end

    create table(:scoped_model) do
      add :title, :string
      add :scope, :integer
      add :scope2, :integer
      add :scoped_rank, :integer
    end
  end
end
