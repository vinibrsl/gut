defmodule Gut do
  @moduledoc """
  Picks one value from a fixed set of choices with an LLM.

  Gut presents the subject, question, and choices to the configured adapter. It
  then maps the adapter's answer back to the original Elixir value. It does not
  return a string copy of that value or create atoms from model output.

  ## Examples

      {:ok, true} =
        Gut.feel(
          "Please fix this today.",
          "Does this convey time pressure?",
          [true, false]
        )

  Use descriptions when a choice needs more context:

      {:ok, :billing} =
        Gut.feel(
          ticket,
          "Which team should handle this?",
          billing: "Payment, invoice, or refund problems",
          technical: "Product defects or access problems",
          other: "Anything else"
        )

  Integer ranges are also valid choices:

      {:ok, 4} = Gut.feel(messages, "How frustrated is the customer?", 1..5)

  A successful result means that the adapter returned a valid choice. It does
  not mean that the judgment is correct.

  Set `allow_unsure: true` to offer uncertainty as a choice. Gut returns
  `{:ok, :unsure}` if the adapter selects it. The adapter may still select a
  choice when it should be unsure.

  ## Subjects

  Gut sends string subjects as plain text. It encodes all other subjects as
  JSON. Derive `Gut.Subject` to control which struct fields the adapter receives
  without changing the struct's general JSON representation:

      defmodule Ticket do
        @derive {Gut.Subject, only: [:subject, :body]}
        defstruct [:subject, :body, :internal_notes]
      end

  This also works with structs defined by `Ecto.Schema`.

  Gut treats the subject as untrusted data when it builds a prompt. This reduces
  accidental prompt confusion, but it does not prevent prompt injection.

  ## Configuration

  Configure an adapter as a module or a `{module, options}` tuple:

      config :gut,
        adapter: {Gut.ReqLLM, model: "anthropic:claude-haiku-4-5"}

  Pass `:adapter` to `feel/4` or `feel!/4` to replace the configured adapter for
  one call:

      Gut.feel(subject, question, choices,
        adapter: {MyApp.Adapter, model: MyApp.Classifier}
      )

  The call option takes precedence over application configuration. See
  `Gut.Adapter` to implement an adapter.

  ## Errors

  Adapter and provider failures return `{:error, %Gut.Error{}}`. Use the error's
  `reason` field for control flow and its `cause` field for logging. `feel!/4`
  raises the same error instead.

  Invalid local input raises `ArgumentError` before the adapter runs. This
  includes invalid questions, choices, options, subjects, and adapter
  configuration.
  """

  @default_adapter {Gut.ReqLLM, []}

  @doc """
  Calls a named question with the given subject.

  Pass a `{module, name}` tuple. Define named
  questions with `use Gut.Question` and `Gut.Question.defquestion/2`.

  This function uses the question's adapter and `:allow_unsure` settings.
  An adapter of `nil` uses the application adapter at call time.
  Use `feel/3` to override these settings for one call.

  Gut validates question fields before the adapter runs. Invalid fields raise
  `ArgumentError`. Unknown question names raise `FunctionClauseError`.

  ## Examples

      defmodule Support do
        use Gut.Question

        defquestion :team,
          question: "Which team?",
          choices: [:billing, :technical]
      end

      Gut.feel(ticket, {Support, :team})
      #=> {:ok, :billing}
  """
  @spec feel(term(), Gut.Question.t() | {module(), atom()}) ::
          {:ok, term()} | {:error, Gut.Error.t()}
  def feel(subject, question), do: feel(subject, question, [])

  @doc """
  Calls a question with options, or an inline question without options.

  For named questions, `opts` accepts `:adapter` and
  `:allow_unsure`. Call options override the question's settings. An adapter
  of `nil` selects the application adapter. Call options cannot change the
  question text or choices. See `feel/4` for option details.

  For inline questions, pass the question string and choices as the second
  and third arguments. This form uses the defaults described in `feel/4`.

  ## Examples

      Gut.feel(ticket, {Support, :team}, adapter: Gut.Test)
      #=> {:ok, :billing}

      Gut.feel(review, "What is the sentiment?", [:positive, :neutral, :negative])
      #=> {:ok, :positive}
  """
  @spec feel(term(), Gut.Question.t() | {module(), atom()}, keyword()) ::
          {:ok, term()} | {:error, Gut.Error.t()}
  @spec feel(term(), String.t(), nonempty_list(term()) | Range.t()) ::
          {:ok, term()} | {:error, Gut.Error.t()}
  def feel(subject, {module, name}, opts) when is_atom(module) and is_atom(name) do
    feel(subject, module.__gut_question__(name), opts)
  end

  def feel(subject, %Gut.Question{} = question, opts) do
    validate_options!(opts)

    run_question(subject, struct!(question, opts))
  end

  def feel(subject, question, choices), do: feel(subject, question, choices, [])

  @doc """
  Asks the configured adapter to choose the value that best answers `question`.

  `subject` can be a string or any value that implements `Jason.Encoder`.
  Structs can derive or implement `Gut.Subject` for a Gut-specific
  representation. `question` must be a non-empty string.

  `choices` must contain between 1 and 100 choices. It can be:

    * a list of unique values;
    * an integer range; or
    * a keyword list with string descriptions.

  Lists and ranges return the selected value. Keyword lists present each value
  as a description and return the selected key.

  ## Options

    * `:adapter` - a `Gut.Adapter` module or a `{module, options}` tuple. It
      replaces the adapter from the `:gut` application configuration for this
      call. `nil` uses the application adapter.
    * `:allow_unsure` - adds an unsure choice when `true`. Gut returns
      `{:ok, :unsure}` if the adapter selects it. Defaults to `false`.

  Adapter and provider failures return `{:error, %Gut.Error{}}`. Invalid local
  input raises `ArgumentError` before the adapter runs.

  ## Examples

      Gut.feel(review, "What is the sentiment?", [:positive, :neutral, :negative])
      #=> {:ok, :positive}

      Gut.feel(ticket, "Which team should handle this?",
        billing: "Payment or invoice problems",
        technical: "Product or access problems"
      )
      #=> {:ok, :technical}

      Gut.feel(messages, "How frustrated is the customer?", 1..5)
      #=> {:ok, 4}
  """
  @spec feel(term(), String.t(), nonempty_list(term()) | Range.t(), keyword()) ::
          {:ok, term()} | {:error, Gut.Error.t()}
  def feel(subject, question, choices, opts) do
    feel(subject, %Gut.Question{question: question, choices: choices}, opts)
  end

  @doc """
  Asks the configured adapter to choose a value and returns it directly.

  This function accepts the same arguments and options as `feel/4`. It returns
  the selected value, including `:unsure` when enabled. It raises `Gut.Error`
  for an adapter or provider failure. Invalid local input raises `ArgumentError`.

  ## Examples

      Gut.feel!(ticket, "Which team should handle this?",
        billing: "Payment or invoice problems",
        technical: "Product or access problems"
      )
      #=> :billing
  """
  @spec feel!(term(), String.t(), nonempty_list(term()) | Range.t(), keyword()) :: term()
  def feel!(subject, question, choices, opts \\ []) do
    case feel(subject, question, choices, opts) do
      {:ok, choice} -> choice
      {:error, error} -> raise error
    end
  end

  defp run_question(subject, question) do
    adapter =
      case question.adapter do
        nil -> Application.get_env(:gut, :adapter, @default_adapter)
        adapter -> adapter
      end

    question = Gut.Question.validate!(%{question | adapter: adapter})
    {adapter_choices, values} = normalize_choices(question.choices)
    subject = Gut.Subject.to_text(subject)
    {adapter, adapter_opts} = normalize_adapter(question.adapter)

    {adapter_choices, values} =
      maybe_allow_unsure(adapter_choices, values, question.allow_unsure)

    state = adapter.init(adapter_opts)
    choose(adapter, state, adapter_opts, subject, question.question, adapter_choices, values)
  end

  defp choose(adapter, state, adapter_opts, subject, question, adapter_choices, values) do
    metadata = %{adapter: adapter, model: Keyword.get(adapter_opts, :model)}
    start = System.monotonic_time()
    :telemetry.execute([:gut, :feel, :start], %{system_time: System.system_time()}, metadata)

    result =
      try do
        adapter.choose(subject, question, adapter_choices, state)
      catch
        kind, reason ->
          :telemetry.execute(
            [:gut, :feel, :exception],
            %{duration: System.monotonic_time() - start},
            Map.put(metadata, :kind, kind)
          )

          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    result = choose_result(result, values, adapter)

    :telemetry.execute(
      [:gut, :feel, :stop],
      %{duration: System.monotonic_time() - start},
      Map.put(metadata, :outcome, outcome(result))
    )

    result
  end

  defp choose_result({:ok, {:gut_test_value, value}}, values, Gut.Test) do
    if Enum.any?(values, fn {_id, choice} -> choice === value end) do
      {:ok, value}
    else
      raise ArgumentError, "Gut.Test stub value is not among the choices"
    end
  end

  defp choose_result({:ok, id}, values, _adapter) when is_binary(id),
    do: selected_value(id, values)

  defp choose_result({:error, %Gut.Error{} = error}, _values, _adapter),
    do: {:error, error}

  defp choose_result(result, _values, _adapter), do: {:error, adapter_error(result)}

  defp outcome({:ok, _}), do: :ok
  defp outcome({:error, %Gut.Error{reason: reason}}), do: reason

  defp normalize_choices(choices) when is_list(choices) do
    {values, descriptions} =
      if Keyword.keyword?(choices) do
        Enum.unzip(choices)
      else
        {choices, Enum.map(choices, &inspect/1)}
      end

    build_choices(values, descriptions)
  end

  defp normalize_choices(%Range{} = choices) do
    choices
    |> Enum.to_list()
    |> normalize_choices()
  end

  defp build_choices(values, descriptions) do
    choices =
      Enum.with_index(descriptions, fn description, index ->
        {Integer.to_string(index), description}
      end)

    value_by_id =
      values
      |> Enum.with_index()
      |> Map.new(fn {value, index} -> {Integer.to_string(index), value} end)

    {choices, value_by_id}
  end

  defp maybe_allow_unsure(choices, values, false), do: {choices, values}

  defp maybe_allow_unsure(choices, values, true) do
    id = Integer.to_string(length(choices))

    {choices ++
       [
         {id,
          "Choose this if the subject does not provide enough information or none of the choices fits"}
       ], Map.put(values, id, :unsure)}
  end

  defp validate_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "options must be a keyword list"
    end

    keys = Keyword.keys(opts)

    if keys -- [:adapter, :allow_unsure] != [] or keys != Enum.uniq(keys) do
      raise ArgumentError, "supported options are :adapter and boolean :allow_unsure"
    end
  end

  defp normalize_adapter(adapter) when is_atom(adapter), do: validate_adapter!(adapter, [])

  defp normalize_adapter({adapter, opts}), do: validate_adapter!(adapter, opts)

  defp validate_adapter!(adapter, opts) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :init, 1) and
         function_exported?(adapter, :choose, 4) do
      {adapter, opts}
    else
      raise ArgumentError, "adapter must implement init/1 and choose/4"
    end
  end

  defp selected_value(id, values) do
    case Map.fetch(values, id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, invalid_answer(id)}
    end
  end

  defp invalid_answer(id) do
    %Gut.Error{
      reason: :invalid_answer,
      message: "adapter returned an unknown choice ID",
      cause: id
    }
  end

  defp adapter_error(result) do
    %Gut.Error{
      reason: :adapter_error,
      message: "adapter returned an invalid result",
      cause: result
    }
  end
end
