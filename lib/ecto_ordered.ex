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
      field :position,         :integer, virtual: true
      field :rank,             :integer
      field :move,             :any, virtual: true
    end

    def changeset(model, params) do
      model
      |> cast(params, [:position, :title, :move])
      |> set_order(:position, :rank)
    end
  end
  ```


  """

  # These are the max bounds of an INT in postgresql
  @max 2147483647
  @min -2147483648

  defmodule Options do
    defstruct position_field: :position, move_field: :move,
      rank_field: :rank, scope_field: nil, module: nil
  end

  import Ecto.Query
  import Ecto.Changeset

  @doc """
  Returns a changeset which will include updates to the other ordered rows
  within the same transaction as the insertion, deletion or update of this row.

  The arguments are as follows:
  - `changeset` the changeset which is part of the ordered list
  - `position_field` the (virtual) field in which the order is set
  - `rank_field` the field in which the ranking should be stored
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
    options = %Options{
      position_field: position_field,
      rank_field: rank_field,
      scope_field: scope_field,
      module: cs.data.__struct__
    }

    updated = if get_field(cs, position_field) do
      options |> update_rank(cs)
    else
      options |> update_rank(put_change(cs, position_field, :last))
    end

    ensure_unique_position(updated, options)
  end

  @doc false
  def before_update(cs, position_field, rank_field, scope_field \\ nil) do
    options = %Options{
      position_field: position_field,
      rank_field: rank_field,
      scope_field: scope_field,
      module: cs.data.__struct__
    }
    case {fetch_change(cs, position_field), fetch_change(cs, options.move_field)} do
      {_, {:ok, _}} -> options |> move(cs, options.move_field) |> ensure_unique_position(options)
      {{:ok, _},_} -> options |> update_rank(cs) |> ensure_unique_position(options)
      foo ->
        cs
    end
  end

  defp update_rank(%Options{rank_field: rank_field, position_field: position_field} = options, cs) do
    case get_field(cs, position_field) do
      :last ->
        current_last = get_current_last(options, cs)
        if current_last do
          put_change(cs, rank_field, rank_between(@max, current_last))
        else
          update_rank(options, put_change(cs, position_field, :middle))
        end
      :middle -> put_change(cs, rank_field, rank_between(@max, @min))
      nil -> update_rank(options, put_change(cs, position_field, :last))
      position when is_integer(position) ->
        {rank_before, rank_after} = neighbours_at_position(options, position, cs)
        put_change(cs, rank_field, rank_between(rank_after, rank_before))
    end
  end

  defp move(options, changeset, move_field) do
    do_move(get_field(changeset, move_field), options, changeset)
  end

  def do_move(:up, options, changeset) do
    case get_previous_two(options, changeset) do
      {upper, lower} -> put_change(changeset, options.rank_field, rank_between(upper, lower))
      _ -> changeset
    end
  end

  def do_move(:down, options, changeset) do
    case get_next_two(options, changeset) do
      {upper, lower} -> put_change(changeset, options.rank_field, rank_between(upper, lower))
      _ -> changeset
    end
  end

  def do_move(_, options, changeset), do: changeset

  defp get_previous_two(options, cs) do
    current_rank = get_field(cs, options.rank_field)
    previous = options
    |> nearby_query(cs)
    |> where([r], field(r, ^options.rank_field) < ^current_rank)
    |> cs.repo.all
    case previous do
      [] -> nil
      [lower] -> {@min, lower}
      [upper, lower] -> {upper, lower}
    end
  end

  defp get_next_two(options, cs) do
    current_rank = get_field(cs, options.rank_field) 
    next = options
    |> nearby_query(cs)
    |> where([r], field(r, ^options.rank_field) > ^current_rank)
    |> cs.repo.all
    case next do
      [] -> nil
      [lower] -> {@max, lower}
      [upper, lower] -> {upper, lower}
    end
  end

  defp nearby_query(options, cs) do
    options
    |> rank_query
    |> scope_query(options, cs)
    |> select_rank(options.rank_field)
    |> limit(2)
    |> order_by(^options.rank_field)
  end

  defp ensure_unique_position(cs, %Options{rank_field: rank_field} = options) do
    # If we're not changing ranks, then don't bother
    rank = get_change(cs, rank_field)
    if rank != nil && (rank > @max || current_at_rank(options, cs)) do
      shift_ranks(options, cs)
    end
    cs
  end

  defp shift_ranks(%Options{rank_field: rank_field} = options, cs) do
    current_rank = get_field(cs, rank_field)
    current_first = get_current_first(options, cs)
    current_last = get_current_last(options, cs)
    cond do
      current_first > @min && current_rank == @max -> decrement_other_ranks(options, cs)
      current_last < @max - 1 && current_rank < current_last -> increment_other_ranks(options, cs)
      true -> rebalance_ranks(options, cs)
    end
  end

  defp rebalance_ranks(%Options{
                              rank_field: rank_field,
                              position_field: position_field
                             } = options, cs) do
    rows = current_order(options, cs)
    old_attempted_rank = get_field(cs, rank_field)
    count = length(rows) + 1

    rows
    |> Enum.with_index
    |> Enum.map(fn {row, index} ->
      old_rank = Map.get(row, rank_field)
      row
      |> change([{rank_field,  rank_for_row(old_rank, index, count, old_attempted_rank)}])
      |> cs.repo.update!
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

  defp current_order(%Options{rank_field: rank_field} = options, cs) do
    options
    |> rank_query
    |> scope_query(options, cs)
    |> cs.repo.all
  end

  defp increment_other_ranks(%Options{rank_field: rank_field} = options, %{data: existing} = cs) do
    current_rank = get_field(cs, rank_field)
    options.module
    |> where([r], field(r, ^rank_field) >= ^current_rank)
    |> exclude_existing(existing)
    |> cs.repo.update_all([inc: [{rank_field, 1}]])
    cs
  end

  defp decrement_other_ranks(%Options{rank_field: rank_field} = options, %{data: existing} = cs) do
    current_rank = get_field(cs, rank_field)
    options.module
    |> where([r], field(r, ^rank_field) <= ^current_rank)
    |> exclude_existing(existing)
    |> cs.repo.update_all([inc: [{rank_field, -1}]])
    cs
  end

  defp current_at_rank(%Options{rank_field: rank_field} = options, cs) do
    rank = get_field(cs, rank_field)
    options.module
    |> where([r], field(r, ^rank_field) == ^rank)
    |> limit(1)
    |> scope_query(options, cs)
    |> cs.repo.one
  end

  defp neighbours_at_position(%Options{
                                     rank_field: rank_field,
                                    } = options, position, cs) when position <= 0 do
    first = options
    |> rank_query
    |> select_rank(rank_field)
    |> limit(1)
    |> scope_query(options, cs) |> cs.repo.one

    if first do
      {@min, first}
    else
      {@min, @max}
    end
  end

  defp neighbours_at_position(%Options{rank_field: rank_field,
                          } = options, position, %{data: existing} = cs) do
    current_last = get_current_last(options, cs)
    neighbours = options
    |> rank_query
    |> select_rank(rank_field)
    |> limit(2)
    |> offset(^(position - 1))
    |> scope_query(options, cs)
    |> exclude_existing(existing)
    |> cs.repo.all
    case neighbours do
      [] -> {current_last, @max}
      [bef] -> {bef, @max}
      [bef, aft] -> {bef, aft}
    end
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

  defp get_current_last(%Options{
                                rank_field: rank_field,
                               } = options, cs) do
    last = options.module
    |> select_rank(rank_field)
    |> order_by(desc: ^rank_field)
    |> limit(1)
    |> scope_query(options, cs)
    |> cs.repo.one

    if last do
      last
    else
      @min
    end
  end

  defp get_current_first(%Options{rank_field: rank_field} = options, cs) do
    first = options
    |> rank_query
    |> select_rank(rank_field)
    |> order_by(asc: ^rank_field)
    |> limit(1)
    |> scope_query(options, cs)
    |> cs.repo.one

    if first do
      first
    else
      options
    end
  end


  defp rank_between(nil, nil) do
    rank_between(@max, @min)
  end

  defp rank_between(above, below) do
    round((above - below) / 2) + below
  end

  defp rank_query(options) do
    options.module
    |> ranked(options.rank_field)
  end

  defp scope_query(query, %Options{scope_field: scope_field}, cs) do
    scope = get_field(cs, scope_field)
    if scope do
      (from q in query, where: field(q, ^scope_field) == ^scope)
    else
      query
    end
  end

end
