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

  @max 8388607
  @min -8388607

  defstruct repo:         nil,
            module:       nil,
            position_field:        :position,
            rank_field: :rank,
            scope_field:        nil,
            current_last: nil

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
  def set_order(changeset, position_field, rank_field, scope_field \\ nil) do
    changeset
    |> prepare_changes( fn changeset ->
      case changeset.action do
        :insert -> EctoOrdered.before_insert changeset, position_field, rank_field, scope_field
        :update -> EctoOrdered.before_update changeset, position_field, rank_field, scope_field
      end
    end)
  end

  @doc false
  def before_insert(cs, position_field, rank_field, scope_field) do
    struct = %Order{module: cs.data.__struct__,
                    position_field: position_field,
                    rank_field: rank_field,
                    scope_field: scope_field,
                    repo: cs.repo
                   }

    if get_field(cs, position_field) do
      update_rank(struct, cs)
    else
      update_rank(struct, put_change(cs, position_field, :last))
    end
  end

  @doc false
  def before_update(cs, position_field, rank_field, scope_field \\ nil) do
    struct = %Order{module: cs.data.__struct__,
                    position_field: position_field,
                    rank_field: rank_field,
                    scope_field: scope_field,
                    repo: cs.repo
                   }
    case fetch_change(cs, position_field) do
      {:ok, _} -> update_rank(struct, cs)
      :error -> cs
    end
  end

  defp update_rank(%Order{rank_field: rank_field, position_field: position_field} = struct, cs) do
    case get_field(cs, position_field) do
      :last -> %Order{current_last: current_last} = update_current_last(struct)
        if current_last do
          put_change(cs, rank_field, rank_between(@max, current_last))
        else
          update_rank(struct, put_change(cs, position_field, :middle))
        end
      :middle -> put_change(cs, rank_field, rank_between(@max, @min))
      nil -> update_rank(struct, put_change(cs, position_field, :last))
      position when is_integer(position) ->
        {rank_before, rank_after} = neighbours_at_position(struct, position, cs.data)
        put_change(cs, rank_field, rank_between(rank_after, rank_before))
    end
  end

  defp neighbours_at_position(%Order{module: module,
                                     rank_field: rank_field,
                                     repo: repo
                                    }, position, _) when position <= 0 do
    first = (from m in module,
             select: field(m, ^rank_field),
             order_by: [asc: field(m, ^rank_field)],
             limit: 1
    ) |> repo.one

    {@min, first}
  end

  defp neighbours_at_position(%Order{module: module,
                                     rank_field: rank_field,
                                     repo: repo
                          } = struct, position, existing) do
    %Order{current_last: current_last} = update_current_last(struct)
    neighbours = (from m in module,
     select: field(m, ^rank_field),
     order_by: [asc: field(m, ^rank_field)],
     limit: 2,
     offset: ^(position - 1)
    )
    |> exclude_existing(existing)
    |> repo.all
    case neighbours do
      [] -> {current_last, @max}
      [bef] -> {bef, @max}
      [bef, aft] -> {bef, aft}
    end
  end

  defp exclude_existing(query, %{id: nil}) do
    query
  end

  defp exclude_existing(query, existing) do
    from r in query, where: r.id != ^existing.id
  end

  defp update_current_last(%Order{current_last: nil,
                                module: module,
                                rank_field: rank_field,
                                repo: repo
                               } = struct) do
    last = (from m in module,
            select: field(m, ^rank_field),
            order_by: [desc: field(m, ^rank_field)],
            limit: 1
    )
    |> repo.one
    if last do
    %Order{struct | current_last: last}
    else
      %Order{struct | current_last: @min}
    end
  end

  defp update_current_last(%Order{} = struct) do
    # noop. We've already got the last.
    struct
  end

  defp rank_between(nil, nil) do
    rank_between(8388607, -8388607)
  end

  defp rank_between(above, below) do
    ( above - below ) / 2
    |> round
    |> + below
  end

end
