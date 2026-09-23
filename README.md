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

Choose one of these options to configure the adapter:

### Option 1: Jev evaluation

Configure [`Gut.ReqLLM.Jev`](https://hexdocs.pm/gut/Gut.ReqLLM.Jev.html) to use a Jev evaluation model:

```elixir
config :gut,
  adapter: {Gut.ReqLLM.Jev,
    model: "typesafe:jev-latest",
    api_key: System.fetch_env!("TYPESAFE_API_KEY")}
```

### Option 2: Other LLM models

Use [`Gut.ReqLLM`](https://hexdocs.pm/gut/Gut.ReqLLM.html) with any ReqLLM-supported model:

```elixir
config :gut,
  adapter: {Gut.ReqLLM,
    model: "anthropic:claude-haiku-4-5",
    api_key: System.fetch_env!("ANTHROPIC_API_KEY")}
```

With `Gut.ReqLLM`, options other than `:model` pass to `ReqLLM.generate_text/3`.

### Option 3: Local models with Ollama

Start [Ollama](https://hexdocs.pm/req_llm/ollama.html) and pull a model:

```sh
ollama pull llama3.2
```

Then use the same `Gut.ReqLLM` adapter. No API key is needed:

```elixir
config :gut, adapter: {Gut.ReqLLM, model: "ollama:llama3.2"}
```

Ollama must be running at its default address, `http://localhost:11434`. See the [ReqLLM Ollama guide](https://hexdocs.pm/req_llm/ollama.html) to use a different address.

### Option 4: Custom adapter

An adapter connects Gut to a decision system. Gut passes it the subject, question, and choices. The adapter returns the ID of the selected choice. Implement [`Gut.Adapter`](https://hexdocs.pm/gut/Gut.Adapter.html) to use your own model or service:

```elixir
defmodule MyApp.BumblebeeAdapter do
  @behaviour Gut.Adapter

  def init([]), do: nil

  def choose(subject, _question, choices, _state) do
    %{predictions: predictions} = Nx.Serving.batched_run(MyApp.Classifier, subject)
    %{label: label} = Enum.max_by(predictions, & &1.score)

    case Enum.find(choices, fn {_id, description} -> description == label end) do
      {id, _} -> {:ok, id}
      nil -> {:error, %Gut.Error{reason: :invalid_answer, message: "Unknown label"}}
    end
  end
end

config :gut, adapter: MyApp.BumblebeeAdapter
```

## Usage

Use a list when the choices need no descriptions. For example, sort incoming mail:

```elixir
case Gut.feel(%{from: email.from, subject: email.subject, body: email.body},
       "Is this spam?", [true, false]) do
  {:ok, true} -> Mailbox.move(email, :spam)
  {:ok, false} -> Mailbox.move(email, :inbox)
  {:error, error} -> {:error, error}
end
```

Use keyword choices when the model needs descriptions. For example, route a ticket after loading it from the database:

```elixir
with %Ticket{} = ticket <- Repo.get(Ticket, id),
     {:ok, team} <- Gut.feel(%{subject: ticket.subject, body: ticket.body},
       "Which team should handle this?",
       billing: "Payments, invoices, and refunds",
       technical: "Product defects and access problems",
       other: "Anything else"
     ),
     {:ok, ticket} <- Repo.update(Ecto.Changeset.change(ticket, team: Atom.to_string(team))) do
  Support.notify_team(ticket)
else
  nil -> {:error, :not_found}
  error -> error
end
```

An integer range works for scores. For example, flag a conversation when the customer is frustrated:

```elixir
case Gut.feel(messages, "How frustrated is the customer?", 1..5) do
  {:ok, score} when score >= 4 -> Support.flag_for_review(conversation_id)
  {:ok, _score} -> :ok
  {:error, error} -> {:error, error}
end
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
