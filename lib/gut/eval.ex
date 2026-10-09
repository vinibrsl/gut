defmodule Gut.Eval do
  @moduledoc """
  Evaluates one subject against a named question.

  Reuse a question declared with `Gut.Question` and check the selected choice
  with `Gut.Eval.Assertions`. The evaluation value is opaque. Pass it to an
  assertion instead of reading its fields.

      import Gut.Eval.Assertions, only: [assert_choice: 2]

      Gut.Eval.run("Charged twice", {MyApp.Support, :team})
      |> assert_choice(:billing)

  Use a real adapter for live evaluations, not `Gut.Test`. Keep stubbed
  application tests separate. A passing evaluation checks one observed answer;
  it does not establish model accuracy or production reliability.
  """

  @typedoc "An opaque evaluation value for assertion pipelines."
  @opaque t :: %__MODULE__{
            result: {:ok, term()} | {:error, Gut.Error.t()},
            duration: non_neg_integer()
          }

  @enforce_keys [:result, :duration]
  defstruct [:result, :duration]

  @doc """
  Calls `Gut.feel/3` once with a subject and a named question.

  `opts` accepts only `:adapter` and `:allow_unsure`. Call options override
  question settings. An adapter of `nil` uses application configuration. Keep
  provider options inside the adapter tuple. See `Gut.feel/3` for details.

  A list or map is one subject, not a dataset. This function does not retry
  evaluations or cache answers. Adapter transport retries remain unchanged, so
  one call can make more than one HTTP request.

  Returns an opaque value for `Gut.Eval.Assertions`, including on adapter or
  provider failure. Invalid local input preserves the exceptions from
  `Gut.feel/3`.

  Measures the full call with `System.monotonic_time/0`, including question
  lookup, validation, subject encoding, adapter initialization, and provider
  work. Pass the evaluation to `Gut.Eval.Assertions.assert_latency/2` to check
  a per-call limit. The duration remains internal.
  """
  @spec run(term(), {module(), atom()}, keyword()) :: t()
  def run(subject, {module, name} = question, opts \\ [])
      when is_atom(module) and is_atom(name) do
    start = System.monotonic_time()
    result = Gut.feel(subject, question, opts)
    duration = System.monotonic_time() - start
    %__MODULE__{result: result, duration: duration}
  end
end
