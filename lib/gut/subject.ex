defprotocol Gut.Subject do
  @moduledoc """
  Converts a subject into the value that Gut sends to an adapter.

  The result is the text sent to the adapter. Gut sends strings unchanged and
  encodes other values as JSON.

  Derive this protocol to choose which struct fields Gut can send:

      defmodule Ticket do
        @derive {Gut.Subject, only: [:subject, :body]}
        defstruct [:subject, :body, :internal_notes]
      end

  Derivation accepts `:only` or `:except`. Prefer `:only` so new fields are not
  exposed by accident. A derivation without options includes every struct field.

  Implement the protocol directly when a subject needs a custom representation.
  """

  @fallback_to_any true

  @doc "Returns the text sent as the subject."
  @spec to_text(t()) :: String.t()
  def to_text(subject)
end

defimpl Gut.Subject, for: Any do
  defmacro __deriving__(module, struct, opts) do
    fields = fields_to_include(struct, opts)

    quote do
      defimpl Gut.Subject, for: unquote(module) do
        def to_text(subject) do
          subject
          |> Map.take(unquote(fields))
          |> Gut.Subject.Any.to_text()
        end
      end
    end
  end

  def to_text(subject) when is_binary(subject), do: subject

  def to_text(subject) do
    case Jason.encode(subject) do
      {:ok, encoded} ->
        encoded

      {:error, cause} ->
        raise ArgumentError, "subject cannot be encoded as JSON: #{message(cause)}"
    end
  end

  defp message(cause) when is_exception(cause), do: Exception.message(cause)
  defp message(cause), do: inspect(cause)

  defp fields_to_include(struct, opts) do
    fields = Map.keys(struct) -- [:__struct__]

    cond do
      only = Keyword.get(opts, :only) ->
        validate_fields!(:only, only, fields)
        only

      except = Keyword.get(opts, :except) ->
        validate_fields!(:except, except, fields)
        fields -- except

      true ->
        fields
    end
  end

  defp validate_fields!(option, selected, fields) do
    case selected -- fields do
      [] ->
        :ok

      unknown ->
        raise ArgumentError, "#{inspect(option)} contains unknown fields: #{inspect(unknown)}"
    end
  end
end
