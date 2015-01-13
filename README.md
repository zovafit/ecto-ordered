EctoOrdered
===========

Ecto extension to support ordered list items. Similar to (acts_as_list)[https://github.com/swanandp/acts_as_list], but
for (Ecto)[https://github.com/elixir-lang/ecto]

Examples
--------

```elixir
# Global positioning
defmodule MyModel do
  use Ecto.Model
  use EctoOrdered

  schema "models" do
    field :position, :integer
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
end

# Creating and insertion happen as usually (Repo.insert/delete), however,
# to use movement tracking, changesets or wrapper 'moving API' should be used

> MyModel.move_position(my_model, 6) #=> cs
> MyModel.changeset(my_model, :move_position, %{"position" => 6}) # Useful for handling external requests
```
