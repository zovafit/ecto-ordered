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
    if is_nil(opts[:repo]) do
      raise ArgumentError, message:
      "EctoOrdered requires :repo to be specified for " <>
      "#{inspect __CALLER__.module}.#{to_string(opts[:field])}"
    end
    opts = Keyword.merge([field: :position, scope: nil, repo: nil], opts)
    move = :"move_#{opts[:field]}"
    string_field = :"#{opts[:field]}"
    quote location: :keep do
      require Ecto.Query
      require unquote(opts[:repo])

      def __ecto_ordered__select__(q, unquote(opts)) do
        Ecto.Query.select(q, [m], m.unquote(opts[:field]))
      end

      defp __ecto_ordered__increment__(query, unquote(opts))  do
        unquote(opts[:repo]).update_all(m in query,
        [{unquote(opts[:field]), fragment("? + 1", m.unquote(opts[:field]))}])
      end

      defp __ecto_ordered__decrement__(query, unquote(opts))  do
        unquote(opts[:repo]).update_all(m in query,
        [{unquote(opts[:field]), fragment("? - 1", m.unquote(opts[:field]))}])
      end

      if is_nil(unquote(opts[:scope])) do
        def __ecto_ordered__increment_position_query__(unquote(opts), split_by, _scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) >= ^split_by)
          __ecto_ordered__increment__(query, unquote(opts))
        end

        def __ecto_ordered__decrement_position_query__(unquote(opts), split_by, until, _scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) > ^split_by
                                  and m.unquote(opts[:field]) <= ^until)
          __ecto_ordered__decrement__(query, unquote(opts))
        end

      else
        def __ecto_ordered__increment_position_query__(unquote(opts), split_by, nil) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) >= ^split_by
                                                          and is_nil(m.unquote(opts[:scope])))
          __ecto_ordered__increment__(query, unquote(opts))
        end

        def __ecto_ordered__increment_position_query__(unquote(opts), split_by, scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) >= ^split_by
                                                   and m.unquote(opts[:scope]) == ^scope)
          __ecto_ordered__increment__(query, unquote(opts))
        end

        def __ecto_ordered__decrement_position_query__(unquote(opts), split_by, until, nil) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) > ^split_by
                                                          and m.unquote(opts[:field]) <= ^until
                                                          and is_nil(m.unquote(opts[:scope])))
          __ecto_ordered__decrement__(query, unquote(opts))
        end

        def __ecto_ordered__decrement_position_query__(unquote(opts), split_by, until, scope) do
          query = Ecto.Query.from(m in __MODULE__, where: m.unquote(opts[:field]) > ^split_by
                                                   and m.unquote(opts[:field]) <= ^until
                                                   and m.unquote(opts[:scope]) == ^scope)
          __ecto_ordered__decrement__(query, unquote(opts))
        end
      end

      unless is_nil(unquote(opts[:scope])) do

        def __ecto_ordered__scope_query__(q, unquote(opts), scope) do
          q
            |> __ecto_ordered__select__(unquote(opts))
            |> Ecto.Query.where([m], m.unquote(opts[:scope]) == ^scope)
        end

        def __ecto_ordered__scope_nil_query__(q, unquote(opts)) do
          q
            |> __ecto_ordered__select__(unquote(opts))
            |> Ecto.Query.where([m], is_nil(m.unquote(opts[:scope])))
        end

      end

      @doc ~s|
      Creates a changeset for adjusting the #{unquote(string_field)} field
      |
      def changeset(model, unquote(move)) do
        changeset(model, unquote(move), nil)
      end

      def changeset(model, unquote(move), params) do
        params
          |> cast(model, [unquote(string_field)], [])
      end

      @doc ~s|
      Creates a changeset with an adjusted #{unquote(string_field)} field
      |
      def unquote(move)(model, new_position) do
        cs = model
         |> change([{unquote(opts[:field]), new_position}])
        %Ecto.Changeset{cs | valid?: true}
      end

      before_insert EctoOrdered, :before_insert, [unquote(opts)]
      before_update EctoOrdered, :before_update, [unquote(opts)]
      before_delete EctoOrdered, :before_delete, [unquote(opts)]
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

  def before_insert(cs, p) do
    repo = p[:repo]
    field = p[:field]
    scope_field = p[:scope]
    rows = lock_table(cs, p) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    cond do
      is_nil(get_field(cs, field)) ->
        # Doesn't have a position assigned
        cs |>
          put_change(field, max + 1)
      not is_nil(get_field(cs, field)) ->
         # Has a position assigned
         module.__ecto_ordered__increment_position_query__(p, get_change(cs, field), get_field(cs, scope_field))
         validate_position!(cs, field, get_change(cs, field), max)
      true ->
        cs
    end
  end

  def before_update(cs, p) do
    repo = p[:repo]
    field = p[:field]
    scope_field = p[:scope]
    rows = lock_table(cs, p) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    cond do
      Map.has_key?(cs.changes, field) and get_change(cs, field) != Map.get(cs.model, field) and
      get_change(cs, field) > Map.get(cs.model, field) ->
        module.__ecto_ordered__decrement_position_query__(p, Map.get(cs.model, field), get_change(cs, field), get_field(cs, scope_field))
        cs = if get_change(cs, field) == max + 1 do
          cs |> put_change(field, max)
        else
          cs
        end
        validate_position!(cs, field, get_change(cs, field), max)
      Map.has_key?(cs.changes, field) and get_change(cs, field) != Map.get(cs.model, field) and
      get_change(cs, field) < Map.get(cs.model, field) ->
        module.__ecto_ordered__decrement_position_query__(p, Map.get(cs.model, field), max, get_field(cs, scope_field))
        module.__ecto_ordered__increment_position_query__(p, get_change(cs, field), get_field(cs, scope_field))
        validate_position!(cs, field, get_change(cs, field), max)
      true ->
        cs
    end
  end

  def before_delete(cs, p) do
    repo = p[:repo]
    field = p[:field]
    scope_field = p[:scope]
    rows = lock_table(cs, p) |> repo.all
    module = cs.model.__struct__
    max = (rows == [] && 0) || Enum.max(rows)
    module.__ecto_ordered__decrement_position_query__(p, Map.get(cs.model, field), max, get_field(cs, scope_field))
    cs
  end

  defp lock_table(cs, p) do
    module = cs.model.__struct__
    scope = p[:scope]
    q = from m in module, lock: true
    cond do
      is_nil(p[:scope]) ->
        q |> module.__ecto_ordered__select__(p)
      is_nil(get_field(cs, scope)) ->
        q |> module.__ecto_ordered__scope_nil_query__(p)
      scoped = get_field(cs, scope) ->
        q |> module.__ecto_ordered__scope_query__(p, scoped)
    end
  end

end
