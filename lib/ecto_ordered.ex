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

      def __ecto_ordered__select__(q) do
        Ecto.Query.select(q, [m], m.unquote(field))
      end

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
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) >= ^split_by
                                                          and is_nil(m.unquote(scope)))
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__increment_position_query__(split_by, scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) >= ^split_by
                                                   and m.unquote(scope) == ^scope)
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, nil) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) > ^split_by
                                                          and m.unquote(field) <= ^until
                                                          and is_nil(m.unquote(scope)))
          __ecto_ordered__decrement__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) > ^split_by
                                                   and m.unquote(field) <= ^until
                                                   and m.unquote(scope) == ^scope)
          __ecto_ordered__decrement__(query)
        end

        def __ecto_ordered__scope_query__(q, scope) do
          q
          |> __ecto_ordered__select__()
          |> Ecto.Query.where([m], m.unquote(scope) == ^scope)
        end

        def __ecto_ordered__scope_nil_query__(q) do
          q
          |> __ecto_ordered__select__()
          |> Ecto.Query.where([m], is_nil(m.unquote(scope)))
        end
      else
        def __ecto_ordered__increment_position_query__(split_by, _scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) >= ^split_by)
          __ecto_ordered__increment__(query)
        end

        def __ecto_ordered__decrement_position_query__(split_by, until, _scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(field) > ^split_by
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
    rows = lock_table(cs, scope) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    cond do
      is_nil(get_field(cs, field)) ->
        # Doesn't have a position assigned
        cs |>
          put_change(field, max + 1)
      not is_nil(get_field(cs, field)) ->
         # Has a position assigned
         module.__ecto_ordered__increment_position_query__(get_change(cs, field), get_field(cs, scope))
         validate_position!(cs, field, get_change(cs, field), max)
      true ->
        cs
    end
  end

  def before_update(cs, repo, field, scope) do
    if not is_nil(scope) and not is_nil(get_change(cs, scope))
       and Map.get(cs.model, scope) != get_change(cs, scope) do
      cs
       |> put_change(scope, Map.get(cs.model, scope))
       |> before_delete(repo, field, scope)
      before_insert(cs, repo, field, scope)
    else
      rows = lock_table(cs, scope) |> repo.all
      module = cs.model.__struct__
      max = (rows == [] && 0) || Enum.max(rows)
      cond do
        Map.has_key?(cs.changes, field) and get_change(cs, field) != Map.get(cs.model, field) and
        get_change(cs, field) > Map.get(cs.model, field) ->
          module.__ecto_ordered__decrement_position_query__(Map.get(cs.model, field), get_change(cs, field), get_field(cs, scope))
          cs = if get_change(cs, field) == max + 1 do
            cs |> put_change(field, max)
          else
            cs
          end
          validate_position!(cs, field, get_change(cs, field), max)
        Map.has_key?(cs.changes, field) and get_change(cs, field) != Map.get(cs.model, field) and
        get_change(cs, field) < Map.get(cs.model, field) ->
          module.__ecto_ordered__decrement_position_query__(Map.get(cs.model, field), max, get_field(cs, scope))
          module.__ecto_ordered__increment_position_query__(get_change(cs, field), get_field(cs, scope))
          validate_position!(cs, field, get_change(cs, field), max)
        true ->
          cs
      end
    end
  end

  def before_delete(cs, repo, field, scope) do
    rows = lock_table(cs, scope) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    module.__ecto_ordered__decrement_position_query__(Map.get(cs.model, field), max, get_field(cs, scope))
    cs
  end

  defp lock_table(cs, scope) do
    module = cs.model.__struct__
    scope = p[:scope]
    q = from m in module, lock: "FOR UPDATE"

    cond do
      is_nil(scope) ->
        module.__ecto_ordered__select__(q)
      is_nil(get_field(cs, scope)) ->
        module.__ecto_ordered__scope_nil_query__(q, scope)
      scoped = get_field(cs, scope) ->
        module.__ecto_ordered__scope_query__(q, scoped)
    end
  end
end
