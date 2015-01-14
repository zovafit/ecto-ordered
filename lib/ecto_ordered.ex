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

  import Ecto.Query
  import Ecto.Changeset

  defmodule InvalidMove do
    defexception type: nil
    def message(%__MODULE__{type: :too_large}), do: "too large"
    def message(%__MODULE__{type: :too_small}), do: "too small"
  end

  defmacro __using__(opts \\ []) do
    unless repo = opts[:repo] do
      raise ArgumentError, message:
      "EctoOrdered requires :repo to be specified for " <>
      "#{inspect __CALLER__.module}.#{to_string(opts[:field])}"
    end
    field = Keyword.get(opts, :field, :position)
    move = :"move_#{field}"
    scope = Keyword.get(opts, :scope)

    quote location: :keep do
      require Ecto.Query
      require unquote(repo)
      alias Ecto.Query

      defp __ecto_ordered__increment__(query)  do
        unquote(repo).update_all(m in query,
        [{unquote(field), fragment("? + 1", m.unquote(field))}])
      end

      defp __ecto_ordered__decrement__(query)  do
        unquote(repo).update_all(m in query,
        [{unquote(field), fragment("? - 1", m.unquote(field))}])
      end

      if unquote(scope) do
        def __ecto_ordered__increment_position_query__(split_by, nil) do
          query = Query.from m in __MODULE__,
                  where: m.unquote(field) >= ^split_by and is_nil(m.unquote(scope))
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__increment_position_query__(split_by, scope) do
          query = Query.from m in __MODULE__,
                  where: m.unquote(field) >= ^split_by and m.unquote(scope) == ^scope
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, nil) do
          query = Query.from m in __MODULE__,
                  where: m.unquote(field) > ^split_by and m.unquote(field) <= ^until
                         and is_nil(m.unquote(scope))
          __ecto_ordered__decrement__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, scope) do
          query = Query.from(m in __MODULE__,
                  where: m.unquote(field) > ^split_by and m.unquote(field) <= ^until
                         and m.unquote(scope) == ^scope)
          __ecto_ordered__decrement__(query)
        end

        def __ecto_ordered__scope_query__(q, scope) do
          q
          |> EctoOrdered.select(unquote(field))
          |> Query.where([m], m.unquote(scope) == ^scope)
        end

        def __ecto_ordered__scope_nil_query__(q) do
          q
          |> EctoOrdered.select(unquote(field))
          |> Query.where([m], is_nil(m.unquote(scope)))
        end
      else
        def __ecto_ordered__increment_position_query__(split_by, _scope) do
          query = Query.from(m in __MODULE__, where: m.unquote(field) >= ^split_by)
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, _scope) do
          query = Query.from(m in __MODULE__, where: m.unquote(field) > ^split_by
                                  and m.unquote(field) <= ^until)
          __ecto_ordered__decrement__(query)
        end
      end

      @doc """
      Creates a changeset for adjusting the #{unquote(field)} field
      """
      def changeset(model, unquote(move)) do
        changeset(model, unquote(move), nil)
      end

      def changeset(model, unquote(move), params) do
        params
        |> cast(model, [unquote(field)], [])
      end

      @doc """
      Creates a changeset with an adjusted #{unquote(field)} field
      """
      def unquote(move)(model, new_position) do
        cs = model
             |> change([{unquote(field), new_position}])
        %Ecto.Changeset{cs | valid?: true}
      end

      callback_args = [unquote(repo), unquote(field), unquote(scope)]

      before_insert EctoOrdered, :before_insert, callback_args
      before_update EctoOrdered, :before_update, callback_args
      before_delete EctoOrdered, :before_delete, callback_args
    end
  end

  def select(q, field) do
    Ecto.Query.select(q, [m], field(m, ^field))
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

  def before_insert(cs, repo, field, scope) do
    rows = lock_table(cs, scope, field) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    position_assigned = get_field(cs, field)

    if position_assigned do
      new_position = get_change(cs, field)
      scope_field = get_field(cs, scope)
      module.__ecto_ordered__increment_position_query__(new_position, scope_field)
      validate_position!(cs, field, new_position, max)
    else
      put_change(cs, field, max + 1)
    end
  end

  def before_update(cs, repo, field, scope) do
    new_scope = get_change(cs, scope)
    scope_value = Map.get(cs.model, scope)

    before_update(cs, repo, field, scope, new_scope, scope_value)
  end
  defp before_update(cs, repo, field, scope, new_scope, scope_value)
      when not is_nil(new_scope) and scope_value != new_scope do
    cs
    |> put_change(scope, Map.get(cs.model, scope))
    |> before_delete(repo, field, scope)
    before_insert(cs, repo, field, scope)
  end
  defp before_update(%{model: %{__struct__: module}} = cs, repo, field, scope, _new_scope, _scope_value) do
    rows = lock_table(cs, scope, field) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    new_position = get_change(cs, field)
    field_value = Map.get(cs.model, field)
    scope_field = get_field(cs, scope)

    adjust_position(cs, module, max, field, scope_field, new_position, field_value)
  end

  defp adjust_position(cs, module, max, field, scope_field, new_position, field_value)
      when new_position > field_value do
    module.__ecto_ordered__decrement_position_query__(field_value, new_position, scope_field)
    cs = if new_position == max + 1, do: put_change(cs, field, max), else: cs
    validate_position!(cs, field, new_position, max)
  end
  defp adjust_position(cs, module, max, field, scope_field, new_position, field_value)
      when new_position < field_value do
    module.__ecto_ordered__decrement_position_query__(field_value, max, scope_field)
    module.__ecto_ordered__increment_position_query__(new_position, scope_field)
    validate_position!(cs, field, new_position, max)
  end
  defp adjust_position(cs, _, _, _, _, _, _) do
    cs
  end

  def before_delete(%{model: %{__struct__: module}} = cs, repo, field, scope) do
    rows = lock_table(cs, scope, field) |> repo.all
    max = (rows == [] && 0) || Enum.max(rows)
    field_value = Map.get(cs.model, field)
    new_scope = get_field(cs, scope)

    module.__ecto_ordered__decrement_position_query__(field_value, max, new_scope)
    cs
  end

  defp lock_table(%{model: %{__struct__: module}}, nil, field) do
    q = from m in module, lock: "FOR UPDATE"
    EctoOrdered.select(q, field)
  end
  defp lock_table(%{model: %{__struct__: module}} = cs, scope, field) do
    q = from m in module, lock: "FOR UPDATE"

    case get_field(cs, scope) do
      nil ->
        module.__ecto_ordered__scope_nil_query__(q, scope)
      scoped ->
        module.__ecto_ordered__scope_query__(q, scoped)
    end
  end
end
