# Gut

[Hex](https://hex.pm/packages/gut) · [Docs](https://hexdocs.pm/gut)

Gut is a simple DSL for LLM decisions in Elixir. It picks an Elixir value for your subject and question. No agent framework required, just a few lines of code and your LLM of choice.

```elixir
ticket = %{
  subject: "Charged twice for the same order",
  body: "Please refund the second charge."
}

Gut.feel(ticket, "Which team should handle this?",
  billing: "Payments, invoices, and refunds",
  technical: "Product defects and access problems",
  other: "Anything else"
)
#=> {:ok, :billing}
```

## Installation

Add `gut` and `req_llm` to `mix.exs`:

```elixir
def deps do
  [
    {:gut, "~> 0.1.0"},
    {:req_llm, "~> 1.24"}
  ]
end
```

Configure [`Gut.ReqLLM.Jev`](https://hexdocs.pm/gut/Gut.ReqLLM.Jev.html) to use a Jev evaluation model:

```elixir
config :gut,
  adapter: {Gut.ReqLLM.Jev,
    model: "typesafe:jev-latest",
    api_key: System.fetch_env!("TYPESAFE_API_KEY")}
```

Or use [`Gut.ReqLLM`](https://hexdocs.pm/gut/Gut.ReqLLM.html) with any ReqLLM-supported model:

```elixir
config :gut,
  adapter: {Gut.ReqLLM,
    model: "anthropic:claude-haiku-4-5",
    api_key: System.fetch_env!("ANTHROPIC_API_KEY")}
```

With `Gut.ReqLLM`, options other than `:model` pass to `ReqLLM.generate_text/3`.

You can also override the configured adapter for a single call:

```elixir
Gut.feel(report, "Does this need manual review?", [true, false],
  adapter: {Gut.ReqLLM,
    model: "anthropic:claude-haiku-4-5",
    api_key: System.fetch_env!("ANTHROPIC_API_KEY")}
)
```

To use another provider or evaluation system, implement [`Gut.Adapter`](https://hexdocs.pm/gut/Gut.Adapter.html).

## Usage

Use a list when the choices need no descriptions:

```elixir
Gut.feel(email, "Is this spam?", [true, false])
```

Use keyword choices when the model needs descriptions, as in the ticket example. An integer range works for scores:

```elixir
Gut.feel(messages, "How frustrated is the customer?", 1..5)
```

`Gut.feel/4` returns `{:error, %Gut.Error{}}` for provider and adapter failures. See [`Gut.Error`](https://hexdocs.pm/gut/Gut.Error.html) for error details. Use the `reason` field for control flow:

- `:timeout`
- `:rate_limited`
- `:unauthorized`
- `:invalid_answer`
- `:adapter_error`

`cause` contains the original error for logging.

## Subjects

Gut sends strings as plain text and encodes other values as JSON.

For structs, derive [`Gut.Subject`](https://hexdocs.pm/gut/Gut.Subject.html) to limit the fields sent to the model:

```elixir
defmodule Ticket do
  @derive {Gut.Subject, only: [:subject, :body]}
  defstruct [:subject, :body, :internal_notes]
end
```

## Testing

Use [`Gut.Test`](https://hexdocs.pm/gut/Gut.Test.html) in `config/test.exs` to run tests without LLM requests:

```elixir
config :gut, adapter: Gut.Test
```

It selects the first choice by default. Set a zero-based index to select another choice:

```elixir
config :gut, adapter: {Gut.Test, index: 1}
```

`Gut.Test` has no shared state, so tests can use `async: true`.

## Development

Gut requires Elixir 1.18 or later.

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
