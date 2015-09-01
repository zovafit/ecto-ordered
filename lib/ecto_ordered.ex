defmodule EctoOrdered do
  @moduledoc """
  EctoOrdered is an extension for Ecto models to support ordered model position in a list within
  a table.

  In order to use it, `use EctoOrdered` should be included into a model

  Following options are accepted:

  * `field` — the field that is used to track the position (:position by default)
  * `scope` — scoping field (nil by default)
  * `repo`  - Ecto repository that will be used to find the table to adjust the numbering (required)

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

  defmacro __using__(opts \\ []) do
    struct = %{repo: repo, field: field, move: move} = build(opts, __CALLER__)
    struct = Macro.escape(struct)

    quote location: :keep do
      field = unquote(field)
      require unquote(repo)

      def __ecto_ordered__increment__(query)  do
        unquote(repo).update_all(m in query,
        [{unquote(field), fragment("? + 1", m.unquote(field))}])
      end

      def __ecto_ordered__decrement__(query)  do
        unquote(repo).update_all(m in query,
        [{unquote(field), fragment("? - 1", m.unquote(field))}])
      end

      @doc """
      Creates a changeset for adjusting the #{field} field
      """
      def changeset(model, unquote(move)) do
        changeset(model, unquote(move), nil)
      end
      def changeset(model, unquote(move), params) do
        cast(params, model, [unquote(field)], [])
      end

      @doc """
      Creates a changeset with an adjusted #{field} field
      """
      def unquote(move)(model, new_position) do
        cs = change(model, [{unquote(field), new_position}])
        %Ecto.Changeset{cs | valid?: true}
      end

      callback_args = [unquote(struct)]

      before_insert EctoOrdered, :before_insert, callback_args
      before_update EctoOrdered, :before_update, callback_args
      before_delete EctoOrdered, :before_delete, callback_args
    end
  end

  def increment_position(%Order{module: module, field: field, scope: nil, new_position: split_by}) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by
    module.__ecto_ordered__increment__(query)
  end
  def increment_position(%Order{module: module, field: field, scope: scope, new_position: split_by, new_scope: new_scope}) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by and field(m, ^scope) == ^new_scope
    module.__ecto_ordered__increment__(query)
  end

  def decrement_position(%Order{module: module, field: field, old_position: split_by, until: until, scope: nil}) do
    query = from m in module,
            where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
    module.__ecto_ordered__decrement__(query)
  end
  def decrement_position(%Order{module: module, field: field, scope: scope, old_position: split_by, until: until, new_scope: new_scope}) do
    query = from m in module,
            where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
                   and field(m, ^scope) == ^new_scope
    module.__ecto_ordered__decrement__(query)
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

  defp build(opts, caller) do
    module = caller.module
    unless repo = opts[:repo] do
      raise ArgumentError, message:
      "EctoOrdered requires :repo to be specified for " <>
      "#{inspect module}.#{to_string(opts[:field])}"
    end

    if field = opts[:field] do
      opts = [{:move, :"move_#{field}"}|opts]
    end

    %{struct(Order, opts)|repo: Macro.expand(repo, caller), module: module}
  end

  defp update_old_scope(%Order{scope: scope} = struct, cs) do
    %{struct|old_scope: get_change(cs, scope)}
  end

  defp update_new_scope(%Order{scope: scope} = struct, cs) do
    %{struct|new_scope: Map.get(cs.model, scope)}
  end

  defp update_new_position(%Order{field: field} = struct, cs) do
    %{struct|new_position: get_change(cs, field)}
  end

  defp update_old_position(%Order{field: field} = struct, cs) do
    %{struct|old_position: Map.get(cs.model, field)}
  end

  defp update_max(%Order{repo: repo} = struct, cs) do
    rows = lock_table(struct, cs) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    %{struct|max: max}
  end

  def before_insert(cs, %Order{field: field} = struct) do
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

  def before_update(cs, struct) do
    struct
    |> update_old_scope(cs)
    |> update_new_scope(cs)
    |> reorder_model(cs)
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

  def before_delete(cs, struct) do
    struct = %Order{max: max} = struct
                                |> update_max(cs)
                                |> update_old_position(cs)
                                |> update_new_scope(cs)
    decrement_position(%{struct|until: max})
    cs
  end

  defp lock_table(%Order{module: module, field: field, scope: nil}, _cs) do
    from(m in module, lock: "FOR UPDATE") |> select(field)
  end
  defp lock_table(%Order{module: module, field: field, scope: scope}, cs) do
    new_scope = get_field(cs, scope)
    from(m in module, lock: "FOR UPDATE") |> scope_query(field, scope, new_scope)
  end

  defp select(q, field) do
    Ecto.Query.select(q, [m], field(m, ^field))
  end

  defp scope_query(q, field, scope, nil) do
    q
    |> select(field)
    |> where([m], is_nil(field(m, ^scope)))
  end
  defp scope_query(q, field, scope, new_scope) do
    q
    |> select(field)
    |> where([m], field(m, ^scope) == ^new_scope)
  end
end
