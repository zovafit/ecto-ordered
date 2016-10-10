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
            current_last: nil,
            current_first: nil

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
    |> prepare_changes(fn changeset ->
      case changeset.action do
        :insert -> EctoOrdered.before_insert changeset, position_field, rank_field, scope_field
        :update -> EctoOrdered.before_update changeset, position_field, rank_field, scope_field
      end
    end)
  end

  @doc false
  def before_insert(cs, position_field, rank_field, scope_field) do
    order = %Order{module: cs.data.__struct__,
                    position_field: position_field,
                    rank_field: rank_field,
                    scope_field: scope_field,
                    repo: cs.repo
                   }

    updated = if get_field(cs, position_field) do
      order |> update_rank(cs)
    else
      order |> update_rank(put_change(cs, position_field, :last))
    end

    ensure_unique_position(updated, order)
  end

  @doc false
  def before_update(cs, position_field, rank_field, scope_field \\ nil) do
    order = %Order{module: cs.data.__struct__,
                    position_field: position_field,
                    rank_field: rank_field,
                    scope_field: scope_field,
                    repo: cs.repo
                   }
    case fetch_change(cs, position_field) do
      {:ok, _} -> order |> update_rank(cs) |> ensure_unique_position(order)
      :error -> cs
    end
  end

  defp update_rank(%Order{rank_field: rank_field, position_field: position_field} = order, cs) do
    case get_field(cs, position_field) do
      :last -> %Order{current_last: current_last} = update_current_last(order, cs)
        if current_last do
          put_change(cs, rank_field, rank_between(@max, current_last))
        else
          update_rank(order, put_change(cs, position_field, :middle))
        end
      :middle -> put_change(cs, rank_field, rank_between(@max, @min))
      nil -> update_rank(order, put_change(cs, position_field, :last))
      position when is_integer(position) ->
        {rank_before, rank_after} = neighbours_at_position(order, position, cs)
        put_change(cs, rank_field, rank_between(rank_after, rank_before))
    end
  end

  defp ensure_unique_position(cs, %Order{rank_field: rank_field} = order) do
    rank = get_field(cs, rank_field)
    if rank > @max || current_at_rank(order, cs) do
      shift_ranks(order, cs)
    end
    cs
  end

  defp shift_ranks(%Order{rank_field: rank_field} = order, cs) do
    current_rank = get_field(cs, rank_field)
    %Order{current_first: current_first} = update_current_first(order, cs)
    %Order{current_last: current_last} = update_current_last(order, cs)
    cond do
      current_first > @min && current_rank == @max -> shift_others_down(order, cs)
      current_last < @max - 1 && current_rank < current_last -> shift_others_up(order, cs)
      true -> rebalance_ranks(order, cs)
    end
  end

  defp rebalance_ranks(%Order{repo: repo,
                              rank_field: rank_field,
                              position_field: position_field
                             } = order, cs) do
    rows = current_order(order, cs)
    old_attempted_rank = get_field(cs, rank_field)
    count = length(rows) + 1

    rows
    |> Enum.with_index
    |> Enum.map(fn {row, index} ->
      old_rank = Map.get(row, rank_field)
      row
      |> change([{rank_field,  rank_for_row(old_rank, index, count, old_attempted_rank)}])
      |> repo.update!
    end)
    put_change(cs, rank_field, rank_for_row(0, get_field(cs, position_field), count, 1))
  end

  defp rank_for_row(old_rank, index, count, old_attempted_rank) do
    # If our old rank is less than the old attempted rank, then our effective index is fine
    new_index = if old_rank < old_attempted_rank do
      index
    # otherwise, we need to increment our index by 1
    else
      index + 1
    end
    round((@max - @min) / count) * new_index + @min
  end

  defp current_order(%Order{rank_field: rank_field, repo: repo} = order, cs) do
    order
    |> queryable
    |> ranked(rank_field)
    |> scope_query(order, cs)
    |> repo.all
  end

  defp shift_others_up(%Order{rank_field: rank_field,
                              repo: repo} = order, %{data: existing} = cs) do
    current_rank = get_field(cs, rank_field)
    order
    |> queryable
    |> where([r], field(r, ^rank_field) >= ^current_rank)
    |> exclude_existing(existing)
    |> repo.update_all([inc: [{rank_field, 1}]])
    cs
  end

  defp shift_others_down(%Order{rank_field: rank_field,
                                repo: repo} = order, %{data: existing} = cs) do
    current_rank = get_field(cs, rank_field)
    order
    |> queryable
    |> where([r], field(r, ^rank_field) <= ^current_rank)
    |> exclude_existing(existing)
    |> repo.update_all([inc: [{rank_field, -1}]])
    cs
  end

  defp current_at_rank(%Order{repo: repo, rank_field: rank_field} = order, cs) do
    rank = get_field(cs, rank_field)
    order
    |> queryable
    |> where([r], field(r, ^rank_field) == ^rank)
    |> limit(1)
    |> scope_query(order, cs)
    |> repo.one
  end

  defp neighbours_at_position(%Order{
                                     rank_field: rank_field,
                                     repo: repo
                                    } = order, position, cs) when position <= 0 do
    first = order
    |> queryable
    |> ranked(rank_field)
    |> select_rank(rank_field)
    |> limit(1)
    |> scope_query(order, cs) |> repo.one

    if first do
      {@min, first}
    else
      {@min, @max}
    end
  end

  defp neighbours_at_position(%Order{rank_field: rank_field,
                                     repo: repo
                          } = order, position, %{data: existing} = cs) do
    %Order{current_last: current_last} = update_current_last(order, cs)
    neighbours = order
    |> queryable
    |> ranked(rank_field)
    |> select_rank(rank_field)
    |> limit(2)
    |> offset(^(position - 1))
    |> scope_query(order, cs)
    |> exclude_existing(existing)
    |> repo.all
    case neighbours do
      [] -> {current_last, @max}
      [bef] -> {bef, @max}
      [bef, aft] -> {bef, aft}
    end
  end


  defp queryable(%Order{module: module}) do
    module
  end

  defp ranked(query, rank_field) do
    (from m in query, order_by: [asc: field(m, ^rank_field)])
  end

  defp select_rank(query, rank_field) do
    (from q in query, select: field(q, ^rank_field))
  end

  defp exclude_existing(query, %{id: nil}) do
    query
  end

  defp exclude_existing(query, existing) do
    from r in query, where: r.id != ^existing.id
  end

  defp update_current_last(%Order{current_last: nil,
                                rank_field: rank_field,
                                repo: repo,
                               } = order, cs) do
    last = order
    |> queryable
    |> select_rank(rank_field)
    |> order_by(desc: ^rank_field)
    |> limit(1)
    |> scope_query(order, cs)
    |> repo.one
    if last do
      %Order{order | current_last: last}
    else
      %Order{order | current_last: @min}
    end
  end

  defp update_current_last(%Order{} = order, _) do
    # noop. We've already got the last.
    order
  end

  defp update_current_first(%Order{current_first: nil,
                                  rank_field: rank_field,
                                  repo: repo
                                 } = order, cs) do
    first = order
    |> queryable
    |> ranked(rank_field)
    |> select_rank(rank_field)
    |> limit(1)
    |> scope_query(order, cs)
    |> repo.one

    if first do
      %Order{order | current_first: first}
    else
      order
    end
  end


  defp rank_between(nil, nil) do
    rank_between(8388607, -8388607)
  end

  defp rank_between(above, below) do
    round((above - below) / 2) + below
  end

  defp scope_query(query, %Order{scope_field: scope_field}, cs) do
    scope = get_field(cs, scope_field)
    if scope do
      (from q in query, where: field(q, ^scope_field) == ^scope)
    else
      query
    end
  end

end
