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
      field :move,         :any, virtual: true
    end

    def changeset(model, params) do
      model
      |> cast(params, [:position, :title, :move])
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

  test "moving an item up" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{move: :up}) |> Repo.update!

    assert ranked_ids(Model) == [model2.id, model1.id, model3.id]
  end

  test "moving an item down using the :down position symbol" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{move: :down}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model3.id, model2.id]
  end

  test "moving an item :up when its already first" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!

    model1 |> Model.changeset(%{move: :up}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model2.id, model3.id]
    assert Repo.get(Model, model1.id).rank == model1.rank
  end

  test "moving an item :down when it's already last" do
    model1 = Model.changeset(%Model{title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3"}, %{}) |> Repo.insert!

    model3 |> Model.changeset(%{move: :down}) |> Repo.update!

    assert ranked_ids(Model) == [model1.id, model2.id, model3.id]
    assert Repo.get(Model, model3.id).rank == model3.rank
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

  test "collision handling at max" do
    for _ <- 1..100 do
      Model.changeset(%Model{}, %{}) |> Repo.insert!
    end

    ranks = (from m in Model, order_by: m.rank, select: m.rank) |> Repo.all

    assert ranks == Enum.uniq(ranks)
  end

  test "collision handling at min" do
    for _ <- 1..100 do
        Model.changeset(%Model{}, %{position: 0}) |> Repo.insert
    end

    ranks = (from m in Model, order_by: m.rank, select: m.rank) |> Repo.all

    assert ranks == Enum.uniq(ranks)
  end
  test "collision handling in the middle" do
    for _ <- 1..25 do
      Model.changeset(%Model{}, %{position: 0}) |> Repo.insert!
    end
    for _ <- 1..25 do
      Model.changeset(%Model{}, %{position: 1000}) |> Repo.insert!
    end
    ranks = (from m in Model, order_by: m.rank, select: m.rank) |> Repo.all

    assert ranks == Enum.uniq(ranks)
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
      field :scoped_position,  :integer, virtual: true
      field :scoped_rank,      :integer
    end

    def changeset(model, params) do
      model
      |> cast(params, [:scope, :scoped_position, :title])
      |> set_order(:scoped_position, :scoped_rank, :scope)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EctoOrderedTest.Repo)
    :ok
  end

  def ranked_ids(model, scope) do
    (from m in model, where: m.scope == ^scope, select: m.id, order_by: m.scoped_rank) |> Repo.all
  end

  # Insertion

  test "scoped: inserting item with no position" do
    for s <- 1..10, i <- 1..10 do
      model = Model.changeset(%Model{scope: s, title: "no position, going to be ##{i}"}, %{})
      |> Repo.insert!
      assert model.scoped_rank != nil
    end
    for s <- 1..10 do
      models = (from m in Model,
              select: [m.id, m.scoped_rank],
              order_by: [asc: :id], where: m.scope == ^s) |>
        Repo.all
      assert models == Enum.sort_by(models, &Enum.at(&1, 1))
    end
  end

  test "scoped: inserting item with a correct appending position" do
    Model.changeset(%Model{scope: 10, title: "item with no position, going to be #1"}, %{})
    |> Repo.insert
    Model.changeset(%Model{scope: 11, title: "item #2"}, %{}) |> Repo.insert

    model = Model.changeset(%Model{scope: 10, title: "item #2", scoped_position: 2}, %{})
    |> Repo.insert!

    assert (from m in Model, where: m.scope == 10, select: m.id, offset: 1) |> Repo.one == model.id
  end

  test "scoped: inserting item with an inserting position" do
    model1 = Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
    |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
    |> Repo.insert!

    model = Model.changeset(%Model{scope: 1,  title: "item #2", scoped_position: 1}, %{})
    |> Repo.insert!

    assert ranked_ids(Model, 1) == [model1.id, model.id, model2.id, model3.id]
  end

  test "scoped: inserting item with an inserting position at #1" do
    model1 = Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
    |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
    |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
    |> Repo.insert!
    model  = Model.changeset(%Model{scope: 1, title: "item #1", scoped_position: 0}, %{})
    |> Repo.insert!

    assert ranked_ids(Model, 1) == [model.id, model1.id, model2.id, model3.id]
  end

  ## Moving

  test "scoped: updating item with the same position" do
    model = Model.changeset(%Model{scope: 1, title: "no position"}, %{}) |> Repo.insert!

    model1 = Model.changeset(model, %{title: "item with a position", scope: 1})
    |> Repo.update!
    assert model.scoped_rank == model1.scoped_rank
  end

  test "scoped: replacing an item below" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{scoped_position: 3}) |> Repo.update

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model4.id, model2.id, model5.id]
  end

  test "scoped: replacing an item above" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!

    model4 |> Model.changeset(%{scoped_position: 1}) |> Repo.update

    assert ranked_ids(Model, 1) == [model1.id, model4.id, model2.id, model3.id, model5.id]
  end

  test "scoped: updating item with a tail position" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!

    model2 |> Model.changeset(%{scoped_position: 4}) |> Repo.update

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model2.id]
  end

  test "scoped: moving between scopes" do
    scope1_model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!
    scope1_model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!
    scope1_model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!

    scope2_model1 = Model.changeset(%Model{scope: 2, title: "item #1"}, %{}) |> Repo.insert!
    scope2_model2 = Model.changeset(%Model{scope: 2, title: "item #2"}, %{}) |> Repo.insert!
    scope2_model3 = Model.changeset(%Model{scope: 2, title: "item #3"}, %{}) |> Repo.insert!

    scope1_model2 |> Model.changeset(%{scoped_position: 4, scope: 2}) |> Repo.update

    assert Repo.get(Model, scope1_model1.id).scope == 1
    assert Repo.get(Model, scope1_model3.id).scope == 1
    assert ranked_ids(Model, 1) == [scope1_model1.id, scope1_model3.id]

    assert ranked_ids(Model, 2) == [scope2_model1.id, scope2_model2.id, scope2_model3.id, scope1_model2.id]
  end

  ## Deletion

  test "scoped: deleting an item" do
    model1 = Model.changeset(%Model{title: "item #1", scope: 1}, %{}) |> Repo.insert!
    model2 = Model.changeset(%Model{title: "item #2", scope: 1}, %{}) |> Repo.insert!
    model3 = Model.changeset(%Model{title: "item #3", scope: 1}, %{}) |> Repo.insert!
    model4 = Model.changeset(%Model{title: "item #4", scope: 1}, %{}) |> Repo.insert!
    model5 = Model.changeset(%Model{title: "item #5", scope: 1}, %{}) |> Repo.insert!

    model2 |> Repo.delete

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model4.id, model5.id]
  end
end
