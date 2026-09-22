defmodule Gut.ReqLLM.Jev do
  @moduledoc """
  Uses a Jev evaluation model through ReqLLM.

  This adapter requires the optional `req_llm` dependency. Applications that
  use it must add `req_llm` to their dependencies:

      {:req_llm, "~> 1.24"}

  Adapter options pass through to `ReqLLM.evaluate/4`. The configured model
  must support evaluation requests, such as `"typesafe:jev-latest"`.
  """

  @behaviour Gut.Adapter

  @impl true
  def init(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "Gut.ReqLLM.Jev options must be a keyword list"
    end

    case Keyword.pop(opts, :model) do
      {nil, _opts} -> raise ArgumentError, "Gut.ReqLLM.Jev requires a :model option"
      {model, opts} -> {model, opts}
    end
  end

  @impl true
  def choose(subject, question, choices, {model, opts}) do
    questions = %{
      choice: %{
        type: :choice,
        instructions: question,
        criteria: Map.new(choices)
      }
    }

    case ReqLLM.evaluate(model, subject, questions, opts) do
      {:ok, %{object: %{"choice" => %{"choice" => id}}}} when is_binary(id) -> {:ok, id}
      {:ok, response} -> {:error, invalid_response(response)}
      {:error, error} -> {:error, error(error)}
    end
  end

  defp invalid_response(response) do
    %Gut.Error{
      reason: :adapter_error,
      message: "ReqLLM evaluation returned no choice",
      cause: response
    }
  end

  defp error(%{__struct__: ReqLLM.Error.API.Timeout} = cause), do: error(:timeout, cause)

  defp error(%{__struct__: ReqLLM.Error.API.Request, status: status} = cause)
       when status in [408, 504],
       do: error(:timeout, cause)

  defp error(%{__struct__: ReqLLM.Error.API.Request, status: 429} = cause),
    do: error(:rate_limited, cause)

  defp error(%{__struct__: ReqLLM.Error.API.Request, status: status} = cause)
       when status in [401, 403],
       do: error(:unauthorized, cause)

  defp error(%{__struct__: ReqLLM.Error.API.Request, cause: %{reason: :timeout}} = cause),
    do: error(:timeout, cause)

  defp error(cause), do: error(:adapter_error, cause)

  defp error(reason, cause) do
    %Gut.Error{
      reason: reason,
      message: "ReqLLM evaluation failed: #{error_message(cause)}",
      cause: cause
    }
  end

  defp error_message(cause) when is_exception(cause), do: Exception.message(cause)
  defp error_message(cause), do: inspect(cause)
end
