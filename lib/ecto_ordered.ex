defmodule EctoOrdered do
  @moduledoc """
  EctoOrdered provides changeset methods for updating ordering an ordering column

  It should be added to your schema like so:

  ```
  defmodule OrderedListItem do
    use Ecto.Schema
    import Ecto.Changeset

    schema "ordered_list_item" do
      field :title,            :string
      field :position,         :integer
    end

    def changeset(model, params) do
      model
      |> cast(params, [:position, :title])
      |> set_order(:position)
    end

    def delete(model) do
      model
      |> cast(%{}, [])
      |> Map.put(:action, :delete)
      |> set_order(:position)
    end
  end
  ```

  Note the `delete` function used to ensure that the remaining items are repositioned on
  deletion.

  """

  defstruct repo:         nil,
            module:       nil,
            field:        :position,
            new_position: nil,
            old_position: nil,
            move:         :move_position,
            scope:        nil,
            old_scope:    nil,
            new_scope:    nil,
            until:        nil,
            max:          nil

  defmodule InvalidMove do
    defexception type: nil
    def message(%__MODULE__{type: :too_large}), do: "too large"
    def message(%__MODULE__{type: :too_small}), do: "too small"
  end

  import Ecto.Query
  import Ecto.Changeset
  alias EctoOrdered, as: Order

  @doc """
  Returns a changeset which will include updates to the other ordered rows
  within the same transaction as the insertion, deletion or update of this row.

  The arguments are as follows:
  - `changeset` the changeset which is part of the ordered list
  - `field` the field in which the order should be stored
  - `scope` the field in which the scope for the order should be stored (optional)
  """
  def set_order(changeset, field, scope \\ nil) do
    prepare_changes(changeset, fn changeset ->
      case changeset.action do
        :insert -> EctoOrdered.before_insert changeset, %EctoOrdered{repo: changeset.repo,
                                                                    field: field,
                                                                    scope: scope}
        :update -> EctoOrdered.before_update changeset, %EctoOrdered{repo: changeset.repo,
                                                                    field: field,
                                                                    scope: scope}
        :delete -> EctoOrdered.before_delete changeset, %EctoOrdered{repo: changeset.repo,
                                                                    field: field,
                                                                    scope: scope}
      end
    end)
  end

  @doc false
  def before_insert(cs, %Order{field: field} = struct) do
    struct = %{struct|module: cs.model.__struct__}
    struct = %Order{max: max} = update_max(struct, cs)
    position_assigned = get_field(cs, field)

    if position_assigned do
      struct = struct
      |> update_new_scope(cs)
      |> update_new_position(cs)
      increment_position(struct)
      validate_position!(cs, struct)
    else
      put_change(cs, field, max + 1)
    end
  end

  @doc false
  def before_update(cs, struct) do
    %{struct|module: cs.model.__struct__}
    |> update_old_scope(cs)
    |> update_new_scope(cs)
    |> reorder_model(cs)
  end

  defp increment_position(%Order{module: module, field: field, scope: nil, new_position: split_by} = struct) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by
    execute_increment(struct, query)
  end

  defp increment_position(%Order{module: module, field: field, scope: scope, new_position: split_by, new_scope: new_scope} = struct) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by and field(m, ^scope) == ^new_scope
    execute_increment(struct, query)
  end

  defp decrement_position(%Order{module: module, field: field, old_position: split_by, until: until, scope: nil} = struct) do
    query = from m in module,
            where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
    execute_decrement(struct, query)
  end

  defp decrement_position(%Order{module: module, field: field, old_position: split_by, until: nil, old_scope: old_scope, scope: scope} = struct) do
    query = from m in module,
    where: field(m, ^field) > ^split_by
    and field(m, ^scope) == ^old_scope
    execute_decrement(struct, query)
  end

  defp decrement_position(%Order{module: module, field: field, scope: scope, old_position: split_by, until: until, old_scope: old_scope} = struct) do
    query = from m in module,
    where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
            and field(m, ^scope) == ^old_scope
    execute_decrement(struct, query)
  end

  defp validate_position!(cs, %Order{field: field, new_position: position, max: max}) when position > max + 1 do
    raise EctoOrdered.InvalidMove, type: :too_large
    %Ecto.Changeset{ cs | valid?: false } |> add_error(field, :too_large)
  end
  defp validate_position!(cs, %Order{field: field, new_position: position}) when position < 1 do
    raise EctoOrdered.InvalidMove, type: :too_small
    %Ecto.Changeset{ cs | valid?: false } |> add_error(field, :too_small)
  end
  defp validate_position!(cs, _), do: cs

  defp update_old_scope(%Order{scope: scope} = struct, cs) do
    %{struct|old_scope: Map.get(cs.model, scope)}
  end

  defp update_new_scope(%Order{scope: scope} = struct, cs) do
    %{struct|new_scope: get_field(cs, scope)}
  end

  defp update_new_position(%Order{field: field} = struct, cs) do
    %{struct|new_position: get_field(cs, field)}
  end

  defp update_old_position(%Order{field: field} = struct, cs) do
    %{struct|old_position: Map.get(cs.model, field)}
  end

  defp update_max(%Order{repo: repo} = struct, cs) do
    rows = query(struct, cs) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    %{struct|max: max}
  end


  defp reorder_model(%Order{scope: scope, old_scope: old_scope, new_scope: new_scope} = struct, cs)
      when not is_nil(old_scope) and new_scope != old_scope do
    cs
    |> put_change(scope, new_scope)
    |> before_delete(struct)

    before_insert(cs, struct)
  end
  defp reorder_model(struct, cs) do
    struct
    |> update_max(cs)
    |> update_new_position(cs)
    |> update_old_position(cs)
    |> adjust_position(cs)
  end

  defp adjust_position(%Order{max: max, field: field, new_position: new_position, old_position: old_position} = struct, cs)
      when new_position > old_position do
    struct = %{struct|until: new_position}

    decrement_position(struct)
    cs = if new_position == max + 1, do: put_change(cs, field, max), else: cs
    validate_position!(cs, struct)
  end
  defp adjust_position(%Order{max: max, new_position: new_position, old_position: old_position} = struct, cs)
      when new_position < old_position do
    struct = %{struct|until: max}

    decrement_position(struct)
    increment_position(struct)
    validate_position!(cs, struct)
  end

  defp adjust_position(_struct, cs) do
    cs
  end

  @doc false
  def before_delete(cs, struct) do
    struct = %Order{max: max} = %{struct | module: cs.model.__struct__}
                                |> update_max(cs)
                                |> update_old_position(cs)
                                |> update_old_scope(cs)
    decrement_position(%{struct|until: max})
    cs
  end

  defp query(%Order{module: module, field: field, scope: nil}, _cs) do
    from(m in module) |> selector(field)
  end

  defp query(%Order{module: module, field: field, scope: scope}, cs) do
     new_scope = get_field(cs, scope)
     scope_query(module, field, scope, new_scope)
  end

  defp selector(q, field) do
    Ecto.Query.select(q, [m], field(m, ^field))
  end

  defp execute_increment(%Order{repo: repo, field: field}, query) do
    query
    |> repo.update_all([inc: [{field, 1}]])
  end

  defp execute_decrement(%Order{repo: repo, field: field}, query) do
    query |> repo.update_all([inc: [{field, -1}]])
  end

  defp scope_query(q, field, scope, nil) do
    q
    |> selector(field)
    |> where([m], is_nil(field(m, ^scope)))
  end

  defp scope_query(q, field, scope, new_scope) do
    q
    |> selector(field)
    |> where([m], field(m, ^scope) == ^new_scope)
  end
end
