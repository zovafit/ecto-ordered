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
    struct = %{repo: repo, field: field, scope: scope, move: move} = build(opts, __CALLER__)
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

      callback_args = [unquote(repo), field, unquote(scope)]

      before_insert EctoOrdered, :before_insert, callback_args
      before_update EctoOrdered, :before_update, [unquote(struct)]
      before_delete EctoOrdered, :before_delete, [unquote(struct)]
    end
  end

  defp build(opts, caller) do
    unless repo = opts[:repo] do
      raise ArgumentError, message:
      "EctoOrdered requires :repo to be specified for " <>
      "#{inspect caller.module}.#{to_string(opts[:field])}"
    end

    opts = Keyword.put(opts, :repo, Macro.expand(repo, caller))
    if field = opts[:field] do
      opts = [{:move, :"move_#{field}"}|opts]
    end

    struct(Order, opts)
  end

  defp update_scope(%Order{scope: scope} = struct, cs) do
    old_scope = get_change(cs, scope)
    new_scope = Map.get(cs.model, scope)

    struct
    |> Map.put(:old_scope, old_scope)
    |> Map.put(:new_scope, new_scope)
  end

  def increment_position(module, field, _scope, split_by, nil) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by
    module.__ecto_ordered__increment__(query)
  end
  def increment_position(module, field, scope, split_by, new_scope) do
    query = from m in module,
            where: field(m, ^field) >= ^split_by and field(m, ^scope) == ^new_scope
    module.__ecto_ordered__increment__(query)
  end

  def decrement_position(module, %Order{field: field, old_position: split_by, until: until, scope: nil}) do
    query = from m in module,
            where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
    module.__ecto_ordered__decrement__(query)
  end
  def decrement_position(module, %Order{field: field, scope: scope, old_position: split_by, until: until, new_scope: new_scope}) do
    query = from m in module,
            where: field(m, ^field) > ^split_by and field(m, ^field) <= ^until
                   and field(m, ^scope) == ^new_scope
    module.__ecto_ordered__decrement__(query)
  end

  defp validate_position!(cs, field, position, max) when position > max + 1 do
    raise EctoOrdered.InvalidMove, type: :too_large
    %Ecto.Changeset{ cs | valid?: false } |> add_error(field, :too_large)
  end
  defp validate_position!(cs, field, position, _) when position < 1 do
    raise EctoOrdered.InvalidMove, type: :too_small
    %Ecto.Changeset{ cs | valid?: false } |> add_error(field, :too_small)
  end
  defp validate_position!(cs, _, _, _), do: cs

  def before_insert(%{model: %{__struct__: module}} = cs, repo, field, scope) do
    rows = lock_table(cs, scope, field) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    position_assigned = get_field(cs, field)

    if position_assigned do
      new_position = get_change(cs, field)
      new_scope = get_field(cs, scope)
      increment_position(module, field, scope, new_position, new_scope)
      validate_position!(cs, field, new_position, max)
    else
      put_change(cs, field, max + 1)
    end
  end

  def before_update(cs, struct) do
    struct
    |> update_scope(cs)
    |> reorder_model(cs)
  end

  defp reorder_model(%Order{repo: repo, field: field, scope: scope, old_scope: old_scope, new_scope: new_scope} = struct, cs)
      when not is_nil(old_scope) and new_scope != old_scope do
    cs
    |> put_change(scope, new_scope)
    |> before_delete(struct)
    before_insert(cs, repo, field, scope)
  end
  defp reorder_model(%Order{repo: repo, field: field, scope: scope} = struct, cs) do
    rows = lock_table(cs, scope, field) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    new_position = get_change(cs, field)
    old_position = Map.get(cs.model, field)

    struct = %{struct | old_position: old_position, new_position: new_position, max: max}
    adjust_position(struct, cs)
  end

  defp adjust_position(%Order{max: max, field: field, new_position: new_position, old_position: old_position} = struct, cs)
      when new_position > old_position do
    module = cs.model.__struct__
    struct = %{struct|until: new_position}

    decrement_position(module, struct)
    cs = if new_position == max + 1, do: put_change(cs, field, max), else: cs
    validate_position!(cs, field, new_position, max)
  end
  defp adjust_position(%Order{max: max, field: field, scope: scope, new_position: new_position, old_position: old_position} = struct, cs)
      when new_position < old_position do
    new_scope = get_field(cs, scope)
    module = cs.model.__struct__
    struct = %{struct|until: max}

    decrement_position(module, struct)
    increment_position(module, field, scope, new_position, new_scope)
    validate_position!(cs, field, new_position, max)
  end
  defp adjust_position(_struct, cs) do
    cs
  end

  def before_delete(cs, %Order{repo: repo, field: field, scope: scope} = struct) do
    rows = lock_table(cs, scope, field) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    old_position = Map.get(cs.model, field)
    new_scope = get_field(cs, scope)
    struct = %{struct|until: max, old_position: old_position, new_scope: new_scope}

    decrement_position(cs.model.__struct__, struct)
    cs
  end

  defp lock_table(%{model: %{__struct__: module}}, nil, field) do
    q = from m in module, lock: "FOR UPDATE"
    select(q, field)
  end
  defp lock_table(%{model: %{__struct__: module}} = cs, scope, _field) do
    q = from m in module, lock: "FOR UPDATE"

    new_scope = get_field(cs, scope)
    scope_query(q, field, scope, new_scope)
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
