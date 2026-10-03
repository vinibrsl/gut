defmodule Gut.Question do
  @moduledoc """
  Defines reusable questions for `Gut.feel/2` and `Gut.feel/3`.

  Use `use Gut.Question` to import `defquestion/2`. Call named questions with
  `Gut.feel(subject, {module, name})`.

  ## Declaration options

    * `:question` - a non-empty string. Required.
    * `:choices` - between 1 and 100 unique values, as a list, an integer range,
      or a keyword list with string descriptions. Required. See `Gut.feel/4`.
    * `:adapter` - a `Gut.Adapter` module or a `{module, options}` tuple.
      Defaults to `nil`, which uses the application adapter at call time.
    * `:allow_unsure` - adds an unsure choice when `true`. Defaults to `false`.
      The value `:unsure` is reserved when this option is enabled.

  Call options override the question's adapter and `:allow_unsure` settings.
  Gut validates the resulting options before the adapter runs.

  ## Examples

      defmodule Support do
        use Gut.Question

        defquestion :team,
          question: "Which team?",
          choices: [billing: "Payment problems", technical: "Product problems"]
      end

      Gut.feel(ticket, {Support, :team})
      #=> {:ok, :billing}
  """

  @type t :: %__MODULE__{
          question: String.t(),
          choices: nonempty_list(term()) | Range.t(),
          adapter: Gut.Adapter.spec() | nil,
          allow_unsure: boolean()
        }

  @enforce_keys [:question, :choices]
  defstruct [:question, :choices, adapter: nil, allow_unsure: false]

  @max_choices 100

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Gut.Question, only: [defquestion: 2]
    end
  end

  @doc """
  Defines a named question for `Gut.feel/2` and `Gut.feel/3`.

  `name` must be a literal atom. The declaration requires `:question` and
  `:choices` and accepts `:adapter` and `:allow_unsure`. Declaration values
  are stored at compile time. Fields are validated when the question is called,
  after call options override declaration options.

  Unknown question names raise `FunctionClauseError` when called.

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
  defmacro defquestion(name, opts) when is_atom(name) do
    quote do
      @gut_question struct!(Gut.Question, unquote(opts))

      @doc false
      def __gut_question__(unquote(name)), do: @gut_question
    end
  end

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = question) do
    with :ok <- validate_question(question.question),
         {:ok, values} <- validate_choices(question.choices),
         :ok <- validate_allow_unsure(question.allow_unsure, values),
         :ok <- validate_adapter(question.adapter) do
      {:ok, question}
    end
  end

  @doc false
  @spec validate!(t()) :: t()
  def validate!(question) do
    case validate(question) do
      {:ok, question} -> question
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp validate_question(question) when is_binary(question) and byte_size(question) > 0,
    do: :ok

  defp validate_question(_question), do: {:error, "question must be a non-empty string"}

  defp validate_choices([]), do: {:error, "choices must not be empty"}

  defp validate_choices(choices) when is_list(choices) and length(choices) > @max_choices,
    do: {:error, "choices must contain at most #{@max_choices} values"}

  defp validate_choices(choices) when is_list(choices) do
    keyword? = Keyword.keyword?(choices)
    values = if keyword?, do: Keyword.keys(choices), else: choices

    cond do
      keyword? and not Enum.all?(choices, fn {_key, description} -> is_binary(description) end) ->
        {:error, "keyword choice descriptions must be strings"}

      MapSet.size(MapSet.new(values)) != length(values) ->
        {:error, "choices must be unique"}

      true ->
        {:ok, values}
    end
  end

  defp validate_choices(%Range{} = choices) do
    choices
    |> Enum.take(@max_choices + 1)
    |> validate_choices()
  end

  defp validate_choices(_choices),
    do: {:error, "choices must be a non-empty list, keyword list, or integer range"}

  defp validate_allow_unsure(allow_unsure, values) do
    cond do
      not is_boolean(allow_unsure) ->
        {:error, "supported options are :adapter and boolean :allow_unsure"}

      allow_unsure and :unsure in values ->
        {:error, ":unsure is reserved when allow_unsure is true"}

      true ->
        :ok
    end
  end

  defp validate_adapter(adapter) when is_atom(adapter), do: :ok

  defp validate_adapter({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    if Keyword.keyword?(opts) do
      :ok
    else
      {:error, "adapter options must be a keyword list"}
    end
  end

  defp validate_adapter(_adapter),
    do: {:error, "adapter must be a module or a {module, options} tuple"}
end
