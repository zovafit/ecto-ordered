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

  test "moving an item when nothing is ranked" do
    model1 = %Model{title: "item #1"} |> Repo.insert!
    model2 = %Model{title: "item #2"} |> Repo.insert!

    model2 |> Model.changeset(%{move: :up}) |> Repo.update!

    Repo.all(Model)
    assert ranked_ids(Model) == [model2.id, model1.id]
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
      Model.changeset(%Model{}, %{position: 0}) |> Repo.insert
    end
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
