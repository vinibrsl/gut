defmodule GutTest do
  use ExUnit.Case, async: true

  defmodule PickAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.get(opts, :index, 0)

    @impl true
    def choose(_subject, _question, choices, index) do
      {id, _description} = Enum.at(choices, index)
      {:ok, id}
    end
  end

  defmodule SubjectAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init([]), do: nil

    @impl true
    def choose(~s({"answer":true}), _question, [{id, _}], nil), do: {:ok, id}
  end

  defmodule InvalidAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :return)

    @impl true
    def choose(_subject, _question, _choices, return), do: return
  end

  test "returns the exact value selected from a list" do
    choices = [:no, true, {:team, 3}]

    assert {:ok, {:team, 3}} =
             Gut.feel("ticket", "Which value?", choices, adapter: {PickAdapter, index: 2})
  end

  test "returns keyword keys and range members" do
    assert {:ok, :technical} =
             Gut.feel(
               "ticket",
               "Which team?",
               [
                 billing: "Payment problem",
                 technical: "Product problem"
               ],
               adapter: {PickAdapter, index: 1}
             )

    assert {:ok, 4} =
             Gut.feel("ticket", "How severe?", 1..5, adapter: {PickAdapter, index: 3})
  end

  test "encodes non-string subjects as JSON" do
    assert {:ok, :yes} =
             Gut.feel(%{answer: true}, "Is the answer true?", [:yes], adapter: SubjectAdapter)
  end

  test "rejects invalid local input" do
    opts = [adapter: PickAdapter]

    assert_raise ArgumentError, ~r/non-empty string/, fn ->
      Gut.feel("subject", "", [:yes], opts)
    end

    assert_raise ArgumentError, ~r/must not be empty/, fn ->
      Gut.feel("subject", "Question?", [], opts)
    end

    assert_raise ArgumentError, ~r/must be unique/, fn ->
      Gut.feel("subject", "Question?", [:yes, :yes], opts)
    end

    assert_raise ArgumentError, ~r/at most 100/, fn ->
      Gut.feel("subject", "Question?", 1..101, opts)
    end
  end

  test "rejects unknown IDs and invalid adapter results" do
    assert {:error, %Gut.Error{reason: :invalid_answer, cause: "missing"}} =
             Gut.feel("subject", "Question?", [:yes],
               adapter: {InvalidAdapter, return: {:ok, "missing"}}
             )

    assert {:error, %Gut.Error{reason: :adapter_error, cause: :invalid}} =
             Gut.feel("subject", "Question?", [:yes], adapter: {InvalidAdapter, return: :invalid})
  end

  test "passes through adapter errors and raises them from feel!" do
    error = %Gut.Error{reason: :timeout, message: "timed out", cause: :timeout}
    opts = [adapter: {InvalidAdapter, return: {:error, error}}]

    assert {:error, ^error} = Gut.feel("subject", "Question?", [:yes], opts)
    assert_raise Gut.Error, "timed out", fn -> Gut.feel!("subject", "Question?", [:yes], opts) end
  end
end
