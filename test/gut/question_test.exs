defmodule Gut.QuestionTest do
  use ExUnit.Case, async: false

  alias Gut.Question

  defmodule ReturnAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :return)

    @impl true
    def choose(_subject, _question, _choices, result), do: result
  end

  defmodule UnexpectedAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(_opts), do: raise("adapter must not run")

    @impl true
    def choose(_subject, _question, _choices, _state), do: raise("adapter must not run")
  end

  defmodule Questions do
    use Gut.Question

    @teams [billing: "Payments", technical: "Product problems"]

    defquestion(:team,
      question: "Which team?",
      choices: @teams,
      adapter: Gut.Test,
      allow_unsure: true
    )

    defquestion(:urgent, question: "Is it urgent?", choices: [true, false])
    defquestion(:severity, question: "How severe?", choices: 1..5)

    defquestion(:runtime, question: "Which?", choices: [:yes], adapter: UnexpectedAdapter)
  end

  defmodule InvalidQuestions do
    use Gut.Question

    defquestion(:nil_question, question: nil, choices: [:yes])
    defquestion(:nil_choices, question: "Which?", choices: nil)
    defquestion(:empty_question, question: "", choices: [:yes])
    defquestion(:empty_choices, question: "Which?", choices: [])
    defquestion(:duplicate_values, question: "Which?", choices: [:yes, :yes])
    defquestion(:invalid_description, question: "Which?", choices: [yes: true])
    defquestion(:too_many_choices, question: "Which?", choices: 1..101)
    defquestion(:invalid_unsure, question: "Which?", choices: [:yes], allow_unsure: :yes)
    defquestion(:reserved_unsure, question: "Which?", choices: [:unsure], allow_unsure: true)
  end

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end

  setup do
    previous = Application.fetch_env(:gut, :adapter)

    on_exit(fn ->
      case previous do
        {:ok, adapter} -> Application.put_env(:gut, :adapter, adapter)
        :error -> Application.delete_env(:gut, :adapter)
      end
    end)
  end

  test "reuses the question and descriptions with each call's subject" do
    Gut.Test.stub(fn subject, question, choices ->
      assert question == "Which team?"
      assert {"0", "Payments"} in choices
      assert {"1", "Product problems"} in choices
      if subject == "Invoice", do: :billing, else: :technical
    end)

    assert {:ok, :billing} = Gut.feel("Invoice", {Questions, :team})
    assert {:ok, :technical} = Gut.feel("Cannot sign in", {Questions, :team})
  end

  test "uses declaration options before application options" do
    Application.put_env(:gut, :adapter, UnexpectedAdapter)
    Gut.Test.stub(fn _, _, _ -> :unsure end)

    assert {:ok, :unsure} = Gut.feel("Unclear", {Questions, :team})
  end

  test "call options replace declaration options" do
    assert {:ok, :technical} =
             Gut.feel("Ticket", {Questions, :team}, adapter: {ReturnAdapter, return: {:ok, "1"}})

    assert {:error, %Gut.Error{reason: :invalid_answer}} =
             Gut.feel("Ticket", {Questions, :team},
               adapter: {ReturnAdapter, return: {:ok, "2"}},
               allow_unsure: false
             )
  end

  test "uses application options and supports lists and ranges" do
    Application.put_env(:gut, :adapter, Gut.Test)

    assert {:ok, true} = Gut.feel(%{message: "Today"}, {Questions, :urgent})
    assert {:ok, 1} = Gut.feel(["Message"], {Questions, :severity})

    Gut.Test.stub(fn _, _, _ -> 4 end)
    assert {:ok, 4} = Gut.feel("Message", {Questions, :severity})
  end

  test "accepts question structs directly with call overrides" do
    question = %Question{
      question: "Which team?",
      choices: [billing: "Payments", technical: "Product problems"],
      adapter: Gut.Test,
      allow_unsure: true
    }

    assert {:ok, :billing} = Gut.feel("Ticket", question)

    assert {:ok, :technical} =
             Gut.feel("Ticket", question, adapter: {ReturnAdapter, return: {:ok, "1"}})

    assert {:error, %Gut.Error{reason: :invalid_answer}} =
             Gut.feel("Ticket", question,
               adapter: {ReturnAdapter, return: {:ok, "2"}},
               allow_unsure: false
             )
  end

  test "nil selects the current application adapter for every call form" do
    question = %Question{question: "Which?", choices: [true, false]}
    Application.put_env(:gut, :adapter, Gut.Test)

    assert {:ok, true} = Gut.feel("Ticket", question)
    assert {:ok, :billing} = Gut.feel("Ticket", {Questions, :team}, adapter: nil)
    assert {:ok, true} = Gut.feel("Ticket", "Which?", [true, false], adapter: nil)

    Application.put_env(:gut, :adapter, {ReturnAdapter, return: {:ok, "1"}})

    assert {:ok, false} = Gut.feel("Ticket", question)
    assert {:ok, false} = Gut.feel("Ticket", {Questions, :urgent})
    assert {:ok, :technical} = Gut.feel("Ticket", {Questions, :team}, adapter: nil)
  end

  test "requires question and choices when constructing a question" do
    assert_raise ArgumentError, fn -> struct!(Question, question: "Which?") end
    assert_raise ArgumentError, fn -> struct!(Question, choices: [:yes]) end
  end

  test "named declarations do not expose question/1" do
    refute function_exported?(Questions, :question, 1)
  end

  test "declarations require question and choices and reject unknown fields" do
    for {opts, error} <- [
          {[question: "Which?"], ArgumentError},
          {[choices: [:yes]], ArgumentError},
          {[question: "Which?", choices: [:yes], unknown: true], KeyError}
        ] do
      module =
        Module.concat(__MODULE__, "InvalidDeclaration#{System.unique_integer([:positive])}")

      assert_raise error, fn ->
        Code.compile_quoted(
          quote do
            defmodule unquote(module) do
              use Gut.Question

              defquestion(:invalid, unquote(Macro.escape(opts)))
            end
          end
        )
      end
    end
  end

  test "validation returns valid questions unchanged without initializing adapters" do
    for choices <- [[:yes, :no], [yes: "Yes", no: "No"], 1..5, 5..1//-2] do
      question = %Question{question: "Which?", choices: choices, adapter: UnexpectedAdapter}
      assert {:ok, ^question} = Question.validate(question)
      assert ^question = Question.validate!(question)
    end

    question = %Question{question: "Which?", choices: [:yes], adapter: nil}
    assert {:ok, ^question} = Question.validate(question)
    assert ^question = Question.validate!(question)
  end

  test "validation returns errors without raising and the bang version raises the same message" do
    question = %Question{question: "Which?", choices: [:yes], adapter: UnexpectedAdapter}

    for {fields, message} <- [
          {[question: ""], "question must be a non-empty string"},
          {[question: nil], "question must be a non-empty string"},
          {[choices: []], "choices must not be empty"},
          {[choices: 1..101], "choices must contain at most 100 values"},
          {[choices: List.duplicate(:yes, 101)], "choices must contain at most 100 values"},
          {[choices: nil], "choices must be a non-empty list, keyword list, or integer range"},
          {[choices: [yes: true]], "keyword choice descriptions must be strings"},
          {[choices: [:yes, :yes]], "choices must be unique"},
          {[choices: [yes: "Yes", yes: "Again"]], "choices must be unique"},
          {[allow_unsure: :yes], "supported options are :adapter and boolean :allow_unsure"},
          {[choices: [:unsure], allow_unsure: true],
           ":unsure is reserved when allow_unsure is true"},
          {[choices: [unsure: "Unsure"], allow_unsure: true],
           ":unsure is reserved when allow_unsure is true"},
          {[adapter: "invalid"], "adapter must be a module or a {module, options} tuple"},
          {[adapter: {Gut.Test, :invalid}],
           "adapter must be a module or a {module, options} tuple"},
          {[adapter: {Gut.Test, [:invalid]}], "adapter options must be a keyword list"}
        ] do
      invalid = struct!(question, fields)
      assert {:error, ^message} = Question.validate(invalid)
      assert_raise ArgumentError, message, fn -> Question.validate!(invalid) end
    end
  end

  test "validation rejects invalid adapter configuration shapes" do
    for adapter <- ["adapter", {Gut.Test, :invalid}, {Gut.Test, [:invalid]}] do
      question = %Question{question: "Which?", choices: [:yes], adapter: adapter}
      assert_raise ArgumentError, fn -> Question.validate!(question) end
      assert_raise ArgumentError, fn -> Gut.feel("Ticket", question) end
    end
  end

  test "validates question settings after call overrides" do
    question = %Question{
      question: "Which?",
      choices: [:yes],
      adapter: "invalid",
      allow_unsure: :invalid
    }

    assert {:ok, :yes} =
             Gut.feel("Ticket", question, adapter: Gut.Test, allow_unsure: false)

    question = %Question{question: "Which?", choices: [:unsure], allow_unsure: true}
    assert {:ok, :unsure} = Gut.feel("Ticket", question, adapter: Gut.Test, allow_unsure: false)
  end

  test "validates named question settings after call overrides" do
    assert {:ok, :yes} =
             Gut.feel("Ticket", {InvalidQuestions, :invalid_unsure},
               adapter: Gut.Test,
               allow_unsure: false
             )

    assert {:ok, :unsure} =
             Gut.feel("Ticket", {InvalidQuestions, :reserved_unsure},
               adapter: Gut.Test,
               allow_unsure: false
             )
  end

  test "uses the existing adapter default when no adapter is specified" do
    Application.delete_env(:gut, :adapter)

    assert_raise ArgumentError, ~r/requires a :model option/, fn ->
      Gut.feel("Message", {Questions, :urgent})
    end
  end

  test "returns provider errors unchanged" do
    error = %Gut.Error{reason: :timeout, message: "timed out", cause: :timeout}

    assert {:error, ^error} =
             Gut.feel("Ticket", {Questions, :team},
               adapter: {ReturnAdapter, return: {:error, error}}
             )
  end

  test "initializes adapters only when a question is called" do
    assert_raise RuntimeError, "adapter must not run", fn ->
      Gut.feel("Ticket", {Questions, :runtime})
    end

    assert {:ok, :yes} = Gut.feel("Ticket", {Questions, :runtime}, adapter: Gut.Test)
  end

  test "rejects invalid local input before running the adapter" do
    for opts <- [
          :invalid,
          [unknown: true],
          [question: "Replacement?"],
          [choices: [:other]],
          [allow_unsure: :yes],
          [adapter: Gut.Test, adapter: Gut.Test],
          [allow_unsure: true, allow_unsure: false]
        ] do
      assert_raise ArgumentError, fn -> Gut.feel("Ticket", {Questions, :team}, opts) end
    end

    assert_raise ArgumentError, fn ->
      Gut.feel(self(), {Questions, :team}, adapter: UnexpectedAdapter)
    end

    assert_raise FunctionClauseError, fn ->
      Gut.feel("Ticket", {Questions, :missing})
    end

    assert_raise UndefinedFunctionError, fn ->
      Gut.feel("Ticket", {String, :team})
    end
  end

  test "named calls emit the existing telemetry events" do
    id = "named-question-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        id,
        [[:gut, :feel, :start], [:gut, :feel, :stop]],
        &__MODULE__.handle_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)

    assert {:ok, :billing} = Gut.feel("Ticket", {Questions, :team})
    assert_receive {[:gut, :feel, :start], %{system_time: _}, %{adapter: Gut.Test, model: nil}}
    assert_receive {[:gut, :feel, :stop], %{duration: duration}, %{outcome: :ok}}
    assert duration >= 0
    refute_receive {[:gut, :feel, :start], _, _}
  end

  test "rejects malformed definitions before running the adapter" do
    for name <- [
          :nil_question,
          :nil_choices,
          :empty_question,
          :empty_choices,
          :duplicate_values,
          :invalid_description,
          :too_many_choices,
          :invalid_unsure,
          :reserved_unsure
        ] do
      assert_raise ArgumentError, fn ->
        Gut.feel("Ticket", {InvalidQuestions, name}, adapter: UnexpectedAdapter)
      end
    end
  end
end
