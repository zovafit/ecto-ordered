defmodule EctoOrderedTest.Migrations do
  use Ecto.Migration

  def change do
    create table(:model) do
      add :title, :string
      add :position, :integer
    end

    create table(:scoped_model) do
      add :title, :string
      add :scope, :integer
      add :scoped_position, :integer
    end
  end
end
