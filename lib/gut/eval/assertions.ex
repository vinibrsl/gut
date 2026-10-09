defmodule Gut.Eval.Assertions do
  @moduledoc """
  Checks opaque values from `Gut.Eval.run/3`.

  Import these functions to use assertion pipelines. Successful assertions
  return the input unchanged. Failures raise `ExUnit.AssertionError` and stop
  the pipeline. Assertions make no model calls.
  """

  @doc """
  Checks that the selected choice matches `expected` with strict equality (`===`).

  Accepts all valid choice values, including booleans, integers, and `:unsure`.
  Returns the evaluation unchanged on success. A wrong choice or an adapter or
  provider error raises `ExUnit.AssertionError`.

  Failure messages show the selected value or `Gut.Error.reason` and the
  expected choice. They omit the subject, provider response, error message,
  and error cause.
  """
  @spec assert_choice(Gut.Eval.t(), term()) :: Gut.Eval.t()
  def assert_choice(%Gut.Eval{result: {:ok, selected}} = evaluation, expected) do
    if selected === expected do
      evaluation
    else
      raise ExUnit.AssertionError,
        message: "expected choice #{inspect(expected)}, got #{inspect(selected)}"
    end
  end

  def assert_choice(%Gut.Eval{result: {:error, %Gut.Error{reason: reason}}}, expected) do
    raise ExUnit.AssertionError,
      message: "expected choice #{inspect(expected)}, got Gut.Error reason #{inspect(reason)}"
  end

  @doc """
  Checks that a successful call completes in at most `max_ms` milliseconds.

      Gut.Eval.run("Charged twice", {MyApp.Support, :team})
      |> assert_choice(:billing)
      |> assert_latency(max_ms: 5_000)

  Requires exactly one `:max_ms` option with a non-negative integer value.
  Invalid options raise `ArgumentError`. There is no default limit.

  Compares native elapsed time without truncating milliseconds. A fractional
  millisecond above the limit fails. Returns the evaluation unchanged on
  success. Excess duration or an adapter or provider error raises
  `ExUnit.AssertionError`. Failure messages show the duration or error reason
  and the expected limit, without subject or provider data.

  This assertion checks a completed call. It does not cancel requests or set
  provider timeouts. Use adapter timeout settings and ExUnit's test timeout
  for those controls. Set the limit from application requirements. Provider
  load, network conditions, transport retries, and prompt caching can affect
  duration. One passing call does not establish a p95 or p99 latency objective.
  """
  @spec assert_latency(Gut.Eval.t(), keyword()) :: Gut.Eval.t()
  def assert_latency(evaluation, opts) do
    maximum = validate_latency_options!(opts)

    case evaluation do
      %Gut.Eval{result: {:ok, _}, duration: duration} ->
        if duration <= System.convert_time_unit(maximum, :millisecond, :native) do
          evaluation
        else
          elapsed_ms = duration / System.convert_time_unit(1, :millisecond, :native)

          raise ExUnit.AssertionError,
            message: "expected latency at most #{maximum} ms, got #{elapsed_ms} ms"
        end

      %Gut.Eval{result: {:error, %Gut.Error{reason: reason}}} ->
        raise ExUnit.AssertionError,
          message:
            "expected latency at most #{maximum} ms, got Gut.Error reason #{inspect(reason)}"
    end
  end

  defp validate_latency_options!(max_ms: maximum)
       when is_integer(maximum) and maximum >= 0,
       do: maximum

  defp validate_latency_options!(_opts) do
    raise ArgumentError, "latency options must be exactly one non-negative integer :max_ms"
  end
end
