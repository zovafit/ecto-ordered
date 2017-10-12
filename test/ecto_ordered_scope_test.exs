defmodule EctoOrderedTest.Scoped do
  use EctoOrdered.TestCase
  alias EctoOrderedTest.Repo
  import Ecto.Query

  defmodule Model do
    use Ecto.Schema
    import Ecto.Changeset
    import EctoOrdered

    schema "scoped_model" do
      field(:title, :string)
      field(:scope, :integer)
      field(:scope2, :integer)
      field(:scoped_position, :integer, virtual: true)
      field(:scoped_rank, :integer)
    end

    def changeset(model, params) do
      model
      |> cast(params, [:scope, :scoped_position, :title])
      |> set_order(:scoped_position, :scoped_rank, :scope)
    end

    def changeset_multiscope(model, params) do
      model
      |> cast(params, [:scope, :scoped_position, :title])
      |> set_order(:scoped_position, :scoped_rank, [:scope, :scope2])
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EctoOrderedTest.Repo)
    :ok
  end

  def ranked_ids(model, [scope, scope2]) do
    scope_fields = [scope: scope, scope2: scope2]

    dynamic =
      Enum.reduce(scope_fields, true, fn scope_field, dynamic ->
        {name, value} = scope_field

        case value do
          nil -> dynamic([d], is_nil(field(d, ^name)) and ^dynamic)
          _ -> dynamic([d], field(d, ^name) == ^value and ^dynamic)
        end
      end)

    from(m in model, where: ^dynamic, select: m.id, order_by: m.scoped_rank) |> Repo.all()
  end

  def ranked_ids(model, scope) do
    case scope do
      nil ->
        from(m in model, where: is_nil(m.scope), select: m.id, order_by: m.scoped_rank)
        |> Repo.all()

      _ ->
        from(m in model, where: m.scope == ^scope, select: m.id, order_by: m.scoped_rank)
        |> Repo.all()
    end
  end

  # Insertion

  test "scoped: inserting item with no position" do
    for s <- 1..10,
        i <- 1..10 do
      model =
        Model.changeset(%Model{scope: s, title: "no position, going to be ##{i}"}, %{})
        |> Repo.insert!()

      assert model.scoped_rank != nil
    end

    for s <- 1..10 do
      models =
        from(
          m in Model,
          select: [m.id, m.scoped_rank],
          order_by: [asc: :id],
          where: m.scope == ^s
        )
        |> Repo.all()

      assert models == Enum.sort_by(models, &Enum.at(&1, 1))
    end
  end

  test "multi scoped: inserting item with no position" do
    for s <- 1..10,
        i <- 1..10 do
      model =
        Model.changeset_multiscope(
          %Model{scope: s, scope2: s, title: "no position, going to be ##{i}"},
          %{}
        )
        |> Repo.insert!()

      assert model.scoped_rank != nil
    end

    for s <- 1..10 do
      scope = [scope: s, scope2: s]

      models =
        from(m in Model, select: [m.id, m.scoped_rank], order_by: [asc: :id], where: ^scope)
        |> Repo.all()

      assert models == Enum.sort_by(models, &Enum.at(&1, 1))
    end
  end

  test "scoped: inserting item with a correct appending position with nil" do
    Model.changeset(%Model{scope: 10, title: "item with no position, going to be #1"}, %{})
    |> Repo.insert()

    Model.changeset(%Model{scope: 11, title: "item #2"}, %{}) |> Repo.insert()

    model =
      Model.changeset(%Model{scope: 10, title: "item #2", scoped_position: 2}, %{})
      |> Repo.insert!()

    assert from(m in Model, where: m.scope == 10, select: m.id, offset: 1) |> Repo.one() ==
             model.id
  end

  test "scoped: inserting item with a correct appending position" do
    Model.changeset(%Model{scope: 10, title: "item with no position, going to be #1"}, %{})
    |> Repo.insert()

    Model.changeset(%Model{scope: 11, title: "item #2"}, %{}) |> Repo.insert()

    model =
      Model.changeset(%Model{scope: 10, title: "item #2", scoped_position: 2}, %{})
      |> Repo.insert!()

    assert from(m in Model, where: m.scope == 10, select: m.id, offset: 1) |> Repo.one() ==
             model.id
  end

  test "multi scoped: inserting item with a correct appending position" do
    Model.changeset_multiscope(
      %Model{scope: 10, scope2: 100, title: "item with no position, going to be #1"},
      %{}
    )
    |> Repo.insert()

    Model.changeset_multiscope(%Model{scope: 11, scope2: 100, title: "item #2"}, %{})
    |> Repo.insert()

    model =
      Model.changeset_multiscope(
        %Model{scope: 10, scope2: 100, title: "item #2", scoped_position: 2},
        %{}
      )
      |> Repo.insert!()

    scope = [scope: 10, scope2: 100]

    assert from(m in Model, where: ^scope, select: m.id, offset: 1) |> Repo.one() == model.id
  end

  test "scoped: inserting item with an inserting position" do
    model1 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
      |> Repo.insert!()

    model2 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
      |> Repo.insert!()

    model3 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
      |> Repo.insert!()

    model =
      Model.changeset(%Model{scope: 1, title: "item #2", scoped_position: 1}, %{})
      |> Repo.insert!()

    assert ranked_ids(Model, 1) == [model1.id, model.id, model2.id, model3.id]
  end

  test "multi scoped: inserting item with an inserting position" do
    model1 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #1"},
        %{}
      )
      |> Repo.insert!()

    model2 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #2"},
        %{}
      )
      |> Repo.insert!()

    model3 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #3"},
        %{}
      )
      |> Repo.insert!()

    model =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "item #2", scoped_position: 1},
        %{}
      )
      |> Repo.insert!()

    assert ranked_ids(Model, [1, 100]) == [model1.id, model.id, model2.id, model3.id]
  end

  test "scoped: inserting item with an inserting position at #1" do
    model1 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #1"}, %{})
      |> Repo.insert!()

    model2 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #2"}, %{})
      |> Repo.insert!()

    model3 =
      Model.changeset(%Model{scope: 1, title: "no position, going to be #3"}, %{})
      |> Repo.insert!()

    model =
      Model.changeset(%Model{scope: 1, title: "item #1", scoped_position: 0}, %{})
      |> Repo.insert!()

    assert ranked_ids(Model, 1) == [model.id, model1.id, model2.id, model3.id]
  end

  test "multi scoped: inserting item with an inserting position at #1" do
    model1 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #1"},
        %{}
      )
      |> Repo.insert!()

    model2 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #2"},
        %{}
      )
      |> Repo.insert!()

    model3 =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "no position, going to be #3"},
        %{}
      )
      |> Repo.insert!()

    model =
      Model.changeset_multiscope(
        %Model{scope: 1, scope2: 100, title: "item #1", scoped_position: 0},
        %{}
      )
      |> Repo.insert!()

    assert ranked_ids(Model, [1, 100]) == [model.id, model1.id, model2.id, model3.id]
  end

  ## Moving

  test "scoped: updating item with the same position" do
    model = Model.changeset(%Model{scope: 1, title: "no position"}, %{}) |> Repo.insert!()

    model1 =
      Model.changeset(model, %{title: "item with a position", scope: 1})
      |> Repo.update!()

    assert model.scoped_rank == model1.scoped_rank
  end

  test "multi scoped: updating item with the same position" do
    model =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "no position"}, %{})
      |> Repo.insert!()

    model1 =
      Model.changeset_multiscope(model, %{title: "item with a position", scope: 1, scope2: 100})
      |> Repo.update!()

    assert model.scoped_rank == model1.scoped_rank
  end

  test "scoped: replacing an item below" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!()
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!()
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!()
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!()
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!()

    model2 |> Model.changeset(%{scoped_position: 3}) |> Repo.update()

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model4.id, model2.id, model5.id]
  end

  test "multi scoped: replacing an item below" do
    model1 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #1"}, %{})
      |> Repo.insert!()

    model2 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #2"}, %{})
      |> Repo.insert!()

    model3 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #3"}, %{})
      |> Repo.insert!()

    model4 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #4"}, %{})
      |> Repo.insert!()

    model5 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #5"}, %{})
      |> Repo.insert!()

    model2 |> Model.changeset_multiscope(%{scoped_position: 3}) |> Repo.update()

    assert ranked_ids(Model, [1, 100]) == [model1.id, model3.id, model4.id, model2.id, model5.id]
  end

  test "scoped: replacing an item above" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!()
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!()
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!()
    model4 = Model.changeset(%Model{scope: 1, title: "item #4"}, %{}) |> Repo.insert!()
    model5 = Model.changeset(%Model{scope: 1, title: "item #5"}, %{}) |> Repo.insert!()

    model4 |> Model.changeset(%{scoped_position: 1}) |> Repo.update()

    assert ranked_ids(Model, 1) == [model1.id, model4.id, model2.id, model3.id, model5.id]
  end

  test "multi scoped: replacing an item above" do
    model1 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #1"}, %{})
      |> Repo.insert!()

    model2 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #2"}, %{})
      |> Repo.insert!()

    model3 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #3"}, %{})
      |> Repo.insert!()

    model4 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #4"}, %{})
      |> Repo.insert!()

    model5 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #5"}, %{})
      |> Repo.insert!()

    model4 |> Model.changeset_multiscope(%{scoped_position: 1}) |> Repo.update()

    assert ranked_ids(Model, [1, 100]) == [model1.id, model4.id, model2.id, model3.id, model5.id]
  end

  test "scoped: updating item with a tail position" do
    model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!()
    model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!()
    model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!()

    model2 |> Model.changeset(%{scoped_position: 4}) |> Repo.update()

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model2.id]
  end

  test "multi scoped: updating item with a tail position" do
    model1 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #1"}, %{})
      |> Repo.insert!()

    model2 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #2"}, %{})
      |> Repo.insert!()

    model3 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #3"}, %{})
      |> Repo.insert!()

    model2 |> Model.changeset_multiscope(%{scoped_position: 4}) |> Repo.update()

    assert ranked_ids(Model, [1, 100]) == [model1.id, model3.id, model2.id]
  end

  test "scoped: moving between scopes" do
    scope1_model1 = Model.changeset(%Model{scope: 1, title: "item #1"}, %{}) |> Repo.insert!()
    scope1_model2 = Model.changeset(%Model{scope: 1, title: "item #2"}, %{}) |> Repo.insert!()
    scope1_model3 = Model.changeset(%Model{scope: 1, title: "item #3"}, %{}) |> Repo.insert!()

    scope2_model1 = Model.changeset(%Model{scope: 2, title: "item #1"}, %{}) |> Repo.insert!()
    scope2_model2 = Model.changeset(%Model{scope: 2, title: "item #2"}, %{}) |> Repo.insert!()
    scope2_model3 = Model.changeset(%Model{scope: 2, title: "item #3"}, %{}) |> Repo.insert!()

    scope1_model2 |> Model.changeset(%{scoped_position: 4, scope: 2}) |> Repo.update()

    assert Repo.get(Model, scope1_model1.id).scope == 1
    assert Repo.get(Model, scope1_model3.id).scope == 1
    assert ranked_ids(Model, 1) == [scope1_model1.id, scope1_model3.id]

    assert ranked_ids(Model, 2) == [
             scope2_model1.id,
             scope2_model2.id,
             scope2_model3.id,
             scope1_model2.id
           ]
  end

  test "multi scoped: moving between scopes" do
    scope1_model1 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #1"}, %{})
      |> Repo.insert!()

    scope1_model2 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #2"}, %{})
      |> Repo.insert!()

    scope1_model3 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: 100, title: "item #3"}, %{})
      |> Repo.insert!()

    scope2_model1 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: 100, title: "item #1"}, %{})
      |> Repo.insert!()

    scope2_model2 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: 100, title: "item #2"}, %{})
      |> Repo.insert!()

    scope2_model3 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: 100, title: "item #3"}, %{})
      |> Repo.insert!()

    scope1_model2
    |> Model.changeset_multiscope(%{scoped_position: 4, scope: 2, scope2: 100})
    |> Repo.update()

    assert Repo.get(Model, scope1_model1.id).scope == 1
    assert Repo.get(Model, scope1_model3.id).scope == 1
    assert ranked_ids(Model, [1, 100]) == [scope1_model1.id, scope1_model3.id]

    assert ranked_ids(Model, [2, 100]) == [
             scope2_model1.id,
             scope2_model2.id,
             scope2_model3.id,
             scope1_model2.id
           ]
  end

  test "multi scoped: moving between scopes with nil values" do
    scope1_model1 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: nil, title: "item #1"}, %{})
      |> Repo.insert!()

    scope1_model2 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: nil, title: "item #2"}, %{})
      |> Repo.insert!()

    scope1_model3 =
      Model.changeset_multiscope(%Model{scope: 1, scope2: nil, title: "item #3"}, %{})
      |> Repo.insert!()

    scope2_model1 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: nil, title: "item #1"}, %{})
      |> Repo.insert!()

    scope2_model2 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: nil, title: "item #2"}, %{})
      |> Repo.insert!()

    scope2_model3 =
      Model.changeset_multiscope(%Model{scope: 2, scope2: nil, title: "item #3"}, %{})
      |> Repo.insert!()

    scope1_model2
    |> Model.changeset_multiscope(%{scoped_position: 4, scope: 2, scope2: nil})
    |> Repo.update()

    assert Repo.get(Model, scope1_model1.id).scope == 1
    assert Repo.get(Model, scope1_model3.id).scope == 1
    assert ranked_ids(Model, [1, nil]) == [scope1_model1.id, scope1_model3.id]

    assert ranked_ids(Model, [2, nil]) == [
             scope2_model1.id,
             scope2_model2.id,
             scope2_model3.id,
             scope1_model2.id
           ]
  end

  ## Deletion

  test "scoped: deleting an item" do
    model1 = Model.changeset(%Model{title: "item #1", scope: 1}, %{}) |> Repo.insert!()
    model2 = Model.changeset(%Model{title: "item #2", scope: 1}, %{}) |> Repo.insert!()
    model3 = Model.changeset(%Model{title: "item #3", scope: 1}, %{}) |> Repo.insert!()
    model4 = Model.changeset(%Model{title: "item #4", scope: 1}, %{}) |> Repo.insert!()
    model5 = Model.changeset(%Model{title: "item #5", scope: 1}, %{}) |> Repo.insert!()

    model2 |> Repo.delete()

    assert ranked_ids(Model, 1) == [model1.id, model3.id, model4.id, model5.id]
  end

  test "multi scoped: deleting an item" do
    model1 =
      Model.changeset(%Model{title: "item #1", scope: 1, scope2: 100}, %{}) |> Repo.insert!()

    model2 =
      Model.changeset(%Model{title: "item #2", scope: 1, scope2: 100}, %{}) |> Repo.insert!()

    model3 =
      Model.changeset(%Model{title: "item #3", scope: 1, scope2: 100}, %{}) |> Repo.insert!()

    model4 =
      Model.changeset(%Model{title: "item #4", scope: 1, scope2: 100}, %{}) |> Repo.insert!()

    model5 =
      Model.changeset(%Model{title: "item #5", scope: 1, scope2: 100}, %{}) |> Repo.insert!()

    model2 |> Repo.delete()

    assert ranked_ids(Model, [1, 100]) == [model1.id, model3.id, model4.id, model5.id]
  end
end
