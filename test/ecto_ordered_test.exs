defmodule EctoOrderedTest do
  use EctoOrdered.TestCase
  alias EctoOrderedTest.Repo
  import Ecto.Query

  defmodule Model do
    use Ecto.Schema
    import Ecto.Changeset
    import EctoOrdered

    schema "model" do
      field :title,            :string
      field :rank,         :integer
      field :position,     :integer, virtual: true
    end

    def changeset(model, params) do
      model
      |> cast(params, [:position, :title])
      |> set_order(:position, :rank)
    end

  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EctoOrderedTest.Repo)
  end


  def ranked_ids(model) do
    (from m in model, select: m.id, order_by: m.rank) |> Repo.all
  end


  # No scope

  ## Inserting

  test "an item inserted with no position is given a rank" do
    for i <- 1..10 do
      model = %Model{}
      |> Model.changeset(%{title: "item with no position, going to be ##{i}"})
      |> Repo.insert!
      assert model.rank != nil
    end

    models = (from m in Model, select: m.rank, order_by: [asc: :id]) |> Repo.all
    assert models == Enum.sort(models)
  end

  test "inserting item with a correct appending position" do
    %Model{} |> Model.changeset(%{title: "no position, going to be #1"}) |> Repo.insert
    %Model{} |> Model.changeset(%{title: "item #2", position: 2}) |> Repo.insert!
    models = (from m in Model, select: m.rank, order_by: [asc: :id]) |> Repo.all
    assert models == Enum.sort(models)
  end

  test "inserting item with a gapped position" do
    %Model{title: "item with no position, going to be #1"}
    |> Model.changeset(%{})
    |> Repo.insert
    model = %Model{title: "item #10", position: 10}
    |> Model.changeset(%{})
    |> Repo.insert!
    assert (from m in Model, select: m.title, order_by: m.rank, offset: 1, limit: 1)
    |> Repo.one == model.title
  end

  test "inserting item with an inserting position" do
    model1 = Model.changeset(%Model{}, %{title: "item with no position, going to be #1"})
    |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item with no position, going to be #2"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item with no position, going to be #3"}, %{})
    |> Repo.insert!
    model = Model.changeset(%Model{title: "item #2", position: 1}, %{})
    |> Repo.insert!

    assert ranked_ids(Model) == [model1.id, model.id, model2.id, model3.id]
  end

  test "inserting item with an inserting position at index 0" do
    model1 = Model.changeset(%Model{title: "item with no position, going to be index 0"}, %{})
    |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item with no position, going to be index 1"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item with no position, going to be index 2"}, %{})
    |> Repo.insert!
    model = Model.changeset(%Model{title: "new item index 0", position: 0}, %{})
    |> Repo.insert!

    assert ranked_ids(Model) == [model.id, model1.id, model2.id, model3.id]
  end

  ## Moving

  test "updating item with the same position" do
    model = Model.changeset(%Model{title: "item with no position"}, %{})
    |> Repo.insert!
    model1 = Model.changeset(%Model{model | title: "item with a position"}, %{})
    |> Repo.update!
    assert model.rank == model1.rank
  end

  test "replacing an item below" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{title: "item #5"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{position: 2}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model3.id, model2.id, model4.id, model5.id]
  end

  test "replacing an item above" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{title: "item #5"}, %{}) |> Repo.insert!

    model4 |> Model.changeset(%{position: 1}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model4.id, model2.id, model3.id, model5.id]
  end

  test "updating item with a tail position" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{position: 4}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model3.id, model2.id]
  end

  ## Deletion

  test "deleting an item" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{title: "item #5"}, %{}) |> Repo.insert!

    model2 |> Repo.delete

    assert ranked_ids(Model) == [model1.id, model3.id, model4.id, model5.id]
  end

end


defmodule EctoOrderedTest.Scoped do
  use EctoOrdered.TestCase
  alias EctoOrderedTest.Repo
  import Ecto.Query

  defmodule Model do
    use Ecto.Schema
    import Ecto.Changeset
    import EctoOrdered

    schema "scoped_model" do
      field :title,            :string
      field :scope,            :integer
      field :scoped_position,  :integer
    end

    def changeset(model, params) do
      model
      |> cast(params, [:scope, :scoped_position, :title])
      |> set_order(:scoped_position, :scope)
    end

    def delete(model) do
      model
      |> cast(%{}, [])
      |> Map.put(:action, :delete)
      |> set_order(:scoped_position, :scope)
    end

  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EctoOrderedTest.Repo)
  end
  # Insertion

  test "scoped: inserting item with no position" do
    for s <- 1..10, i <- 1..10 do
      model = Model.changeset(%Model{scope: s, title: "no position, going to be ##{i}"}, %{})
      |> Repo.insert!
      IO.puts "??????"
      assert model.scoped_position == i
    end
    for s <- 1..10 do
      assert (from m in Model,
              select: m.scoped_position,
              order_by: [asc: :id], where: m.scope == ^s) |>
        Repo.all ==  Enum.into(1..10, [])
    end

  end

  test "scoped: inserting item with a correct appending position" do
    Model.changeset(%Model{scope: 10, title: "item with no position, going to be #1"}, %{})
    |> Repo.insert
    Model.changeset(%Model{scope: 11, title: "item #2"}, %{}) |> Repo.insert

    model = Model.changeset(%Model{scope: 10, title: "item #2", scoped_position: 2}, %{})
    |> Repo.insert!

    assert model.scoped_position == 2
  end

  test "scoped: inserting item with a gapped position" do
    Model.changeset(%Model{scope: 1, title: "item with no position, going to be #1"}, %{})
    |> Repo.insert!
    assert_raise EctoOrdered.InvalidMove, "too large", fn ->
      Model.changeset(%Model{scope: 1, title: "item #10", scoped_position: 10}, %{})
      |> Repo.insert
    end
  end

  test "scoped: inserting item with an inserting position" do
    model1 = Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
    |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
    |> Repo.insert!

    model = Model.changeset(%Model{scope: 1,  title: "item #2", scoped_position: 2}, %{})
    |> Repo.insert!

    assert model.scoped_position == 2
    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model2.id).scoped_position == 3
    assert Repo.get(Model, model3.id).scoped_position == 4
  end

  test "scoped: inserting item with an inserting position at #1" do
    model1 = Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
    |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
    |> Repo.insert!
    model  = Model.changeset(%Model{scope: 1, title: "item #1", scoped_position: 1}, %{})
    |> Repo.insert!

    assert model.scoped_position == 1
    assert Repo.get(Model, model1.id).scoped_position == 2
    assert Repo.get(Model, model2.id).scoped_position == 3
    assert Repo.get(Model, model3.id).scoped_position == 4
  end

  ## Moving

  test "scoped: updating item with the same position" do
    model = Model.changeset(%Model{scope: 1, title: "no position"}, %{}) |> Repo.insert!

    model1 = Model.changeset(model, %{title: "item with a position", scope: 1})
    |> Repo.update!
    assert model.scoped_position == model1.scoped_position
  end

  test "scoped: replacing an item below" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{scoped_position: 4}) |> Repo.update

    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model3.id).scoped_position == 2
    assert Repo.get(Model, model4.id).scoped_position == 3
    assert Repo.get(Model, model2.id).scoped_position == 4
    assert Repo.get(Model, model5.id).scoped_position == 5
  end

  test "scoped: replacing an item above" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!

    model4 |> Model.changeset(%{scoped_position: 2}) |> Repo.update

    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model4.id).scoped_position == 2
    assert Repo.get(Model, model2.id).scoped_position == 3
    assert Repo.get(Model, model3.id).scoped_position == 4
    assert Repo.get(Model, model5.id).scoped_position == 5
  end

  test "scoped: updating item with a tail position" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{scoped_position: 4}) |> Repo.update

    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model3.id).scoped_position == 2
    assert Repo.get(Model, model2.id).scoped_position == 3
  end

  test "scoped: moving between scopes" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!

    xmodel1 = Model.changeset(%Model{scope: 2, title: "item #1"}, %{}) |> Repo.insert!
    xmodel2 = Model.changeset(%Model{scope: 2, title: "item #2"}, %{}) |> Repo.insert!
    xmodel3 = Model.changeset(%Model{scope: 2, title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{scoped_position: 4, scope: 2}) |> Repo.update

    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model1.id).scope == 1
    assert Repo.get(Model, model3.id).scoped_position == 2
    assert Repo.get(Model, model3.id).scope == 1

    assert Repo.get(Model, xmodel1.id).scoped_position == 1
    assert Repo.get(Model, xmodel2.id).scoped_position == 2
    assert Repo.get(Model, xmodel3.id).scoped_position == 3
    assert Repo.get(Model, model2.id).scoped_position == 4
    assert Repo.get(Model, model2.id).scope == 2
  end

  ## Deletion

  test "scoped: deleting an item" do
    model1 = Model.changeset(%Model{title: "item #1", scope: 1}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2", scope: 1}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3", scope: 1}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{title: "item #4", scope: 1}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{title: "item #5", scope: 1}, %{}) |> Repo.insert!

    model2 |> Model.delete |> Repo.delete

    assert Repo.get(Model, model1.id).scoped_position == 1
    assert Repo.get(Model, model3.id).scoped_position == 2
    assert Repo.get(Model, model4.id).scoped_position == 3
    assert Repo.get(Model, model5.id).scoped_position == 4
  end
end
