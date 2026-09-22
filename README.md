# Gut

Use LLM judgment in regular Elixir control flow. Gut turns subjective input into a fixed value your application can route, match, store, and act on.

- Route tickets, leads, and reports to the right workflow.
- Classify intent, sentiment, topic, or risk.
- Score urgency, quality, or severity on a bounded scale.
- Automate clear cases and send uncertain work to a person.

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

Gut gives the model a fixed set of choices, then maps its answer back to the original value. Your application gets `:billing`, not a generated string that it still needs to parse.

## What you can do

Use Gut when the input is subjective but the result must be concrete:

```elixir
Gut.feel(review, "What is the sentiment?", [:positive, :neutral, :negative])
#=> {:ok, :positive}

Gut.feel(messages, "How frustrated is the customer?", 1..5)
#=> {:ok, 4}

Gut.feel(report, "Does this need manual review?", [true, false])
#=> {:ok, true}
```

A successful result means the provider returned one of your choices. It does not mean the judgment is correct.

## Installation

Add `gut` and `req_llm` to your dependencies:

```elixir
def deps do
  [
    {:gut, "~> 0.1.0"},
    {:req_llm, "~> 1.24"}
  ]
end
```

Configure a model. For example, use a Jev evaluation model:

```elixir
config :gut,
  adapter: {Gut.ReqLLM.Jev, model: "typesafe:jev-latest"}
```

Or use `Gut.ReqLLM` with any LLM model supported by ReqLLM:

```elixir
config :gut,
  adapter: {Gut.ReqLLM, model: "anthropic:claude-haiku-4-5"}
```

Options after `:model` pass through to `ReqLLM.generate_text/3`.

## Choices

Pass a list when each value explains itself:

```elixir
Gut.feel(email, "Is this spam?", [true, false])
```

Pass keyword choices when the model needs more context:

```elixir
Gut.feel(ticket, "Which team should handle this?",
  billing: "Payment, invoice, or refund problems",
  technical: "Product defects or access problems",
  other: "Anything else"
)
```

Pass an integer range for a bounded score:

```elixir
Gut.feel(messages, "How frustrated is the customer?", 1..5)
```

Gut returns the selected list value, keyword key, or range member. Choices must be unique and contain no more than 100 values.

Use `Gut.feel!/4` when a provider failure should raise:

```elixir
team = Gut.feel!(ticket, "Which team should handle this?", [:billing, :technical])
```

## Subjects

Gut sends strings as plain text and encodes other values as JSON.

Derive `Gut.Subject` to control which struct fields leave your application:

```elixir
defmodule Ticket do
  @derive {Gut.Subject, only: [:subject, :body]}
  defstruct [:subject, :body, :internal_notes]
end
```

Prefer `:only` so new fields are not sent by accident. You can also implement `Gut.Subject` when a subject needs a custom text representation.

Gut treats the subject as untrusted data in its prompt. This reduces accidental prompt confusion, but it does not prevent prompt injection.

## Errors

`Gut.feel/4` returns `{:error, %Gut.Error{}}` for provider and adapter failures. The `reason` field is stable enough for control flow:

- `:timeout`
- `:rate_limited`
- `:unauthorized`
- `:invalid_answer`
- `:adapter_error`

The `cause` field keeps the original error for logging. Invalid local input raises `ArgumentError` before the adapter runs.

## Testing

Use `Gut.Test` in `config/test.exs` to keep tests deterministic and prevent LLM requests:

```elixir
config :gut, adapter: Gut.Test
```

It selects the first choice by default. Set a zero-based index when a test needs another result:

```elixir
config :gut, adapter: {Gut.Test, index: 1}
```

`Gut.Test` has no shared state, so tests can use `async: true`. Mock your application's domain boundary when individual tests need different judgments.

## Custom adapters

Implement the `Gut.Adapter` behaviour to use another provider or evaluation system. Configure the module globally or for one call:

```elixir
Gut.feel(subject, question, choices, adapter: MyApp.GutAdapter)
```

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
