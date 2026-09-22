defmodule Gut.Test do
  @moduledoc """
  A deterministic adapter for tests.

  Configure it in `config/test.exs` to prevent tests from making LLM requests:

      config :gut, adapter: Gut.Test

  The adapter selects the first choice by default. Use the `:index` option to
  select another choice:

      config :gut, adapter: {Gut.Test, index: 1}

  The index is zero-based. Since the adapter has no shared state, it is safe to
  use in concurrent tests.
  """

  @behaviour Gut.Adapter

  @impl true
  def init([]), do: 0
  def init(index: index) when is_integer(index) and index >= 0, do: index

  def init(_opts) do
    raise ArgumentError, "Gut.Test expects a non-negative :index option"
  end

  @impl true
  def choose(_subject, _question, choices, index) do
    case Enum.fetch(choices, index) do
      {:ok, {id, _description}} -> {:ok, id}
      :error -> raise ArgumentError, "Gut.Test index #{index} is outside the available choices"
    end
  end
end
