# Gut

TBD.

## Installation

Add `gut` to your dependencies:

```elixir
def deps do
  [
    {:gut, "~> 0.1.0"}
  ]
end
```

## Development

Gut requires Elixir 1.14 or later.

```sh
mix deps.get
pre-commit install
```

Run the checks:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
```
