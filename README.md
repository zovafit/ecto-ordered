EctoOrdered
===========

Ecto extension to support ordered list items. Similar to [acts_as_list](https://github.com/swanandp/acts_as_list), but
for [Ecto](https://github.com/elixir-lang/ecto)

Examples
--------

```elixir
# Global positioning
defmodule MyModel do
  use Ecto.Schema
  import EctoOrdered

  schema "models" do
    field :position, :integer
  end
  
  def changeset(model, params) do
    model
    |> cast(params, [], [:position])
    |> set_order(:position)
  end
end

# Scoped positioning
defmodule MyModel do
  use Ecto.Model
  use EctoOrdered, scope: :reference_id

  schema "models" do
    field :reference_id, :integer
    field :position,     :integer
  end
  
  def changeset(model, params) do
    model
    |> cast(params, [], [:position, :reference_id])
    |> set_order(:position, :reference_id)
  end
end

