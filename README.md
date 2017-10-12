EctoOrdered
===========
[![Build Status](https://travis-ci.org/maartenvanvliet/ecto-ordered.svg?branch=master)](https://travis-ci.org/maartenvanvliet/ecto-ordered)

Ecto extension to support ordered list items. Similar to [acts_as_list](https://github.com/swanandp/acts_as_list), but
for [Ecto](https://github.com/elixir-lang/ecto)

It uses a rank column in the database to store the rank. This will contain non-consecutive integers so new records can be placed in between two old records and no updates to the old records are needed. The position field is therefore virtual. See:  [ranked-model](https://github.com/mixonic/ranked-model)


Add the latest stable release to your mix.exs file:

```elixir
defp deps do
  [
    {:ecto_ordered, git: "https://github.com/maartenvanvliet/ecto-ordered", branch: "master"}
  ]
end
```

Examples
--------
### Global positioning
```elixir

defmodule MyModel do
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

### Scoped positioning
```elixir
defmodule MyModel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ordered_list_item" do
    field :title,            :string
    field :position,         :integer, virtual: true
    field :rank,             :integer
    field :move,             :any, virtual: true
    field :reference_id,     :integer
    field :scope             :integer
  end

  def changeset(model, params) do
    model
    |> cast(params, [:position, :title, :move, :reference_id])
    |> set_order(:position, :rank, :reference_id)
  end
end
```

### Multi scoped positioning
Same as above but with a list for the scope in the changeset
```elixir
  def changeset(model, params) do
    model
    |> cast(params, [:position, :title, :move, :reference_id])
    |> set_order(:position, :rank, [:reference_id, :scope])
  end
```



