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

  @max_choices 100
  @default_adapter {Gut.ReqLLM, []}

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
      call.

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
  @spec feel(term(), String.t(), list() | Range.t(), keyword()) ::
          {:ok, term()} | {:error, Gut.Error.t()}
  def feel(subject, question, choices, opts \\ []) do
    validate_question!(question)
    {adapter_choices, values} = normalize_choices!(choices)
    subject = encode_subject!(subject)
    {adapter, adapter_opts} = adapter!(opts)
    state = adapter.init(adapter_opts)

    case adapter.choose(subject, question, adapter_choices, state) do
      {:ok, id} when is_binary(id) -> selected_value(id, values)
      {:error, %Gut.Error{} = error} -> {:error, error}
      result -> {:error, adapter_error(result)}
    end
  end

  @doc """
  Asks the configured adapter to choose a value and returns it directly.

  This function accepts the same arguments and options as `feel/4`. It returns
  the selected value on success and raises `Gut.Error` for an adapter or
  provider failure. Invalid local input raises `ArgumentError`.

  ## Examples

      Gut.feel!(ticket, "Which team should handle this?",
        billing: "Payment or invoice problems",
        technical: "Product or access problems"
      )
      #=> :billing
  """
  @spec feel!(term(), String.t(), list() | Range.t(), keyword()) :: term()
  def feel!(subject, question, choices, opts \\ []) do
    case feel(subject, question, choices, opts) do
      {:ok, choice} -> choice
      {:error, error} -> raise error
    end
  end

  defp validate_question!(question) when is_binary(question) and byte_size(question) > 0,
    do: :ok

  defp validate_question!(_question),
    do: raise(ArgumentError, "question must be a non-empty string")

  defp normalize_choices!(choices) when is_list(choices) do
    validate_choice_count!(choices)

    if Keyword.keyword?(choices) do
      normalize_keyword_choices!(choices)
    else
      normalize_value_choices!(choices)
    end
  end

  defp normalize_choices!(%Range{} = choices) do
    choices
    |> Enum.take(@max_choices + 1)
    |> normalize_value_choices!()
  end

  defp normalize_choices!(_choices),
    do: raise(ArgumentError, "choices must be a non-empty list, keyword list, or integer range")

  defp normalize_keyword_choices!(choices) do
    unless Enum.all?(choices, fn {_key, description} -> is_binary(description) end) do
      raise ArgumentError, "keyword choice descriptions must be strings"
    end

    values = Enum.map(choices, &elem(&1, 0))
    validate_unique!(values)
    build_choices(values, Enum.map(choices, &elem(&1, 1)))
  end

  defp normalize_value_choices!(choices) do
    validate_choice_count!(choices)
    validate_unique!(choices)
    build_choices(choices, Enum.map(choices, &inspect/1))
  end

  defp validate_choice_count!([]), do: raise(ArgumentError, "choices must not be empty")

  defp validate_choice_count!(choices) when length(choices) > @max_choices,
    do: raise(ArgumentError, "choices must contain at most #{@max_choices} values")

  defp validate_choice_count!(_choices), do: :ok

  defp validate_unique!(choices) do
    if MapSet.size(MapSet.new(choices)) != length(choices) do
      raise ArgumentError, "choices must be unique"
    end
  end

  defp build_choices(values, descriptions) do
    choices =
      descriptions
      |> Enum.with_index()
      |> Enum.map(fn {description, index} -> {Integer.to_string(index), description} end)

    value_by_id =
      values
      |> Enum.with_index()
      |> Map.new(fn {value, index} -> {Integer.to_string(index), value} end)

    {choices, value_by_id}
  end

  defp encode_subject!(subject), do: Gut.Subject.to_text(subject)

  defp adapter!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "options must be a keyword list"
    end

    if Keyword.keys(opts) -- [:adapter] != [] or length(Keyword.get_values(opts, :adapter)) > 1 do
      raise ArgumentError, "the only supported option is :adapter"
    end

    opts
    |> Keyword.get(:adapter, Application.get_env(:gut, :adapter, @default_adapter))
    |> normalize_adapter!()
  end

  defp normalize_adapter!(adapter) when is_atom(adapter), do: validate_adapter!(adapter, [])

  defp normalize_adapter!({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "adapter options must be a keyword list"
    end

    validate_adapter!(adapter, opts)
  end

  defp normalize_adapter!(_adapter),
    do: raise(ArgumentError, "adapter must be a module or a {module, options} tuple")

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
