defmodule Gut.Test do
  @moduledoc """
  A deterministic adapter for tests.

  Configure it in `config/test.exs` to prevent tests from making LLM requests:

      config :gut, adapter: Gut.Test

  The adapter selects the first choice by default. To control calls made by
  application code, register a stub in the test process:

      Gut.Test.stub(fn _subject, question, _choices ->
        if question == "Which team?", do: :technical, else: :billing
      end)

  The stub must return an offered choice value. Stubs are local to the test
  process and are visible to tasks started by it. Other processes do not inherit
  them. Concurrent tests can use different stubs.
  """

  @behaviour Gut.Adapter

  @doc "Registers a choice function for the current test process."
  @spec stub((String.t(), String.t(), [{String.t(), String.t()}] -> term())) :: :ok
  def stub(fun) when is_function(fun, 3) do
    Process.put(:gut_test_stub, fun)
    :ok
  end

  @impl true
  def init([]), do: :ok

  def init(_opts) do
    raise ArgumentError, "Gut.Test does not accept adapter options"
  end

  @impl true
  def choose(subject, question, choices, :ok) do
    case stub_for(self()) || Enum.find_value(Process.get(:"$callers", []), &stub_for/1) do
      nil -> {:ok, choices |> hd() |> elem(0)}
      fun -> {:ok, {:gut_test_value, fun.(subject, question, choices)}}
    end
  end

  defp stub_for(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, :gut_test_stub)
      nil -> nil
    end
  end
end
