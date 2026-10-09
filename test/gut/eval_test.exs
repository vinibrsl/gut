defmodule Gut.EvalTest do
  use ExUnit.Case, async: false

  import Gut.Eval.Assertions, only: [assert_choice: 2, assert_latency: 2]

  defmodule Adapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: opts

    @impl true
    def choose(subject, question, choices, opts) do
      send(self(), {:adapter_call, subject, question, choices, opts})
      Keyword.get(opts, :return, {:ok, "0"})
    end
  end

  defmodule Questions do
    use Gut.Question

    defquestion(:team,
      question: "Which team?",
      choices: [billing: "Payments", technical: "Product defects"],
      adapter: {Adapter, model: "declared-model"},
      allow_unsure: true
    )

    defquestion(:configured,
      question: "Which team?",
      choices: [:billing, :technical]
    )

    defquestion(:values,
      question: "Which value?",
      choices: [true, false, 1, 1.0, {:team, 3}, "text", nil, [:nested], %{key: :value}],
      adapter: Adapter
    )

    defquestion(:invalid_question, question: "", choices: [:billing], adapter: Adapter)
    defquestion(:invalid_choices, question: "Which team?", choices: [], adapter: Adapter)
  end

  test "reuses the named question and calls the adapter only once" do
    evaluation = Gut.Eval.run("Charged twice", {Questions, :team})

    assert_receive {:adapter_call, "Charged twice", "Which team?", choices,
                    [model: "declared-model"]}

    assert [{"0", "Payments"}, {"1", "Product defects"}, {"2", _}] = choices
    assert assert_choice(evaluation, :billing) === evaluation
    assert assert_choice(evaluation, :billing) |> assert_choice(:billing) === evaluation
    refute_received {:adapter_call, _, _, _, _}
  end

  test "call options override the declared adapter and uncertainty setting" do
    evaluation =
      Gut.Eval.run("Cannot sign in", {Questions, :team},
        adapter: {Adapter, model: "override-model", return: {:ok, "1"}},
        allow_unsure: false
      )

    assert assert_choice(evaluation, :technical) === evaluation

    assert_receive {:adapter_call, "Cannot sign in", "Which team?",
                    [{"0", "Payments"}, {"1", "Product defects"}], opts}

    assert opts == [model: "override-model", return: {:ok, "1"}]
  end

  test "nil adapters use application configuration at call time" do
    previous = Application.fetch_env(:gut, :adapter)

    on_exit(fn ->
      case previous do
        {:ok, adapter} -> Application.put_env(:gut, :adapter, adapter)
        :error -> Application.delete_env(:gut, :adapter)
      end
    end)

    Application.put_env(:gut, :adapter, {Adapter, return: {:ok, "1"}})
    Gut.Eval.run("subject", {Questions, :configured}) |> assert_choice(:technical)
    Gut.Eval.run("subject", {Questions, :team}, adapter: nil) |> assert_choice(:technical)

    Application.put_env(:gut, :adapter, Adapter)
    Gut.Eval.run("subject", {Questions, :configured}) |> assert_choice(:billing)
  end

  test "lists and maps remain single subjects" do
    for subject <- [["one", "two"], %{request: "Charged twice"}] do
      Gut.Eval.run(subject, {Questions, :team}) |> assert_choice(:billing)
      assert_receive {:adapter_call, encoded, "Which team?", _, _}
      assert Jason.decode!(encoded) == Jason.decode!(Jason.encode!(subject))
      refute_received {:adapter_call, _, _, _, _}
    end
  end

  test "choice assertions preserve each valid choice type" do
    values = [true, false, 1, 1.0, {:team, 3}, "text", nil, [:nested], %{key: :value}]

    for {value, index} <- Enum.with_index(values) do
      evaluation =
        Gut.Eval.run("subject", {Questions, :values},
          adapter: {Adapter, return: {:ok, Integer.to_string(index)}}
        )

      assert assert_choice(evaluation, value) === evaluation
    end
  end

  test "choice assertions use strict numeric equality" do
    for {id, selected, expected} <- [{"2", 1, 1.0}, {"3", 1.0, 1}] do
      evaluation =
        Gut.Eval.run("subject", {Questions, :values}, adapter: {Adapter, return: {:ok, id}})

      error = assert_raise ExUnit.AssertionError, fn -> assert_choice(evaluation, expected) end
      assert error.message =~ inspect(selected)
      assert error.message =~ "expected choice #{inspect(expected)}"
    end
  end

  test "supports unsure from declaration and call options" do
    for {name, opts} <- [
          {:team, [adapter: {Adapter, return: {:ok, "2"}}]},
          {:configured, [adapter: {Adapter, return: {:ok, "2"}}, allow_unsure: true]}
        ] do
      evaluation = Gut.Eval.run("unclear", {Questions, name}, opts)
      assert assert_choice(evaluation, :unsure) === evaluation
    end
  end

  test "wrong-choice failures omit the subject and stop the pipeline" do
    evaluation = Gut.Eval.run("sensitive subject", {Questions, :team})
    assert_receive {:adapter_call, _, _, _, _}

    error =
      assert_raise ExUnit.AssertionError, fn ->
        evaluation
        |> assert_choice(:technical)
        |> then(fn value ->
          send(self(), :continued)
          value
        end)
      end

    assert error.message =~ "expected choice :technical"
    assert error.message =~ ":billing"
    refute error.message =~ "sensitive subject"
    refute_received :continued
    refute_received {:adapter_call, _, _, _, _}
  end

  test "provider-error failures show only the reason and expected choice" do
    for reason <- [:timeout, :rate_limited, :unauthorized, :invalid_answer, :adapter_error] do
      provider_error = %Gut.Error{
        reason: reason,
        message: "sensitive provider message",
        cause: %{response: "sensitive provider response"}
      }

      evaluation =
        Gut.Eval.run("sensitive subject", {Questions, :team},
          adapter: {Adapter, return: {:error, provider_error}}
        )

      assert_receive {:adapter_call, _, _, _, _}
      error = assert_raise ExUnit.AssertionError, fn -> assert_choice(evaluation, :billing) end
      assert error.message =~ "expected choice :billing"
      assert error.message =~ inspect(reason)
      refute error.message =~ "sensitive"
      refute_received {:adapter_call, _, _, _, _}
    end
  end

  test "invalid adapter answers do not expose provider responses" do
    evaluation =
      Gut.Eval.run("sensitive subject", {Questions, :team},
        adapter: {Adapter, return: {:ok, "sensitive provider response"}}
      )

    error = assert_raise ExUnit.AssertionError, fn -> assert_choice(evaluation, :billing) end
    assert error.message =~ ":invalid_answer"
    refute error.message =~ "sensitive"
  end

  test "latency assertions check nearby limits on the same completed call" do
    evaluation = Gut.Eval.run("sensitive subject", {Questions, :team})
    assert_receive {:adapter_call, _, _, _, _}

    error = assert_raise ExUnit.AssertionError, fn -> assert_latency(evaluation, max_ms: 0) end
    assert error.message =~ "expected latency at most 0 ms"
    refute error.message =~ "sensitive"

    [_, measured] = Regex.run(~r/got ([\d.eE+-]+) ms/, error.message)
    elapsed_ms = String.to_float(measured)
    assert elapsed_ms > 0
    upper_limit = ceil(elapsed_ms)
    lower_limit = upper_limit - 1

    assert assert_latency(evaluation, max_ms: upper_limit) === evaluation

    assert evaluation
           |> assert_choice(:billing)
           |> assert_latency(max_ms: upper_limit)
           |> assert_choice(:billing) === evaluation

    assert evaluation
           |> assert_latency(max_ms: upper_limit)
           |> assert_choice(:billing) === evaluation

    failure =
      assert_raise ExUnit.AssertionError, fn ->
        evaluation
        |> assert_latency(max_ms: lower_limit)
        |> then(fn value ->
          send(self(), :continued)
          value
        end)
      end

    assert failure.message =~ "expected latency at most #{lower_limit} ms"
    assert failure.message =~ "got #{measured} ms"
    refute_received :continued
    refute_received {:adapter_call, _, _, _, _}
  end

  test "latency assertions fail on provider errors even with a generous limit" do
    for reason <- [:timeout, :rate_limited, :unauthorized, :invalid_answer, :adapter_error] do
      provider_error = %Gut.Error{
        reason: reason,
        message: "sensitive provider message",
        cause: %{response: "sensitive provider response"}
      }

      evaluation =
        Gut.Eval.run("sensitive subject", {Questions, :team},
          adapter: {Adapter, return: {:error, provider_error}}
        )

      assert_receive {:adapter_call, _, _, _, _}

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_latency(evaluation, max_ms: 60_000)
        end

      assert error.message =~ "expected latency at most 60000 ms"
      assert error.message =~ inspect(reason)
      refute error.message =~ "sensitive"
      refute_received {:adapter_call, _, _, _, _}
    end
  end

  test "latency assertions require exactly one non-negative integer limit" do
    evaluation = Gut.Eval.run("subject", {Questions, :team})
    assert_receive {:adapter_call, _, _, _, _}

    for opts <- [
          [],
          [max_ms: -1],
          [max_ms: 1.0],
          [max_ms: true],
          [max_ms: nil],
          [max_ms: "1"],
          [max_ms: 1, max_ms: 2],
          [max_ms: 1, extra: 2],
          [maximum: 1],
          %{max_ms: 1},
          nil,
          :invalid,
          [1],
          [{:max_ms, 1} | :invalid]
        ] do
      assert_raise ArgumentError, fn -> assert_latency(evaluation, opts) end
    end

    refute_received {:adapter_call, _, _, _, _}
  end

  test "invalid local input preserves Gut.feel exceptions without calling the adapter" do
    cases = [
      {"subject", :invalid_question, []},
      {"subject", :invalid_choices, []},
      {"subject", :team, [model: "not a call option"]},
      {"subject", :team, [allow_unsure: :yes]},
      {"subject", :team, [adapter: {Adapter, :invalid}]},
      {"subject", :team, [adapter: NotAnAdapter]},
      {"subject", :team, [adapter: Adapter, adapter: Adapter]},
      {"subject", :team, %{}},
      {self(), :team, []}
    ]

    for {subject, name, opts} <- cases do
      original = assert_raise ArgumentError, fn -> Gut.feel(subject, {Questions, name}, opts) end

      assert_raise ArgumentError, original.message, fn ->
        Gut.Eval.run(subject, {Questions, name}, opts)
      end
    end

    assert_raise FunctionClauseError, fn -> Gut.Eval.run("subject", {Questions, :unknown}) end
    refute_received {:adapter_call, _, _, _, _}
  end
end
