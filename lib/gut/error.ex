defmodule Gut.Error do
  @moduledoc """
  Represents a runtime failure from Gut.

  `reason` provides stable control flow. `message` explains the failure. `cause`
  retains the original adapter or provider error for logging and inspection.

  Invalid local input raises `ArgumentError` instead of returning this error.
  """

  defexception [:reason, :message, :cause]

  @typedoc """
  A stable category for a runtime failure.

  * `:timeout` - the adapter or provider timed out
  * `:rate_limited` - the provider rejected the request rate
  * `:unauthorized` - the provider rejected the credentials
  * `:invalid_answer` - the adapter returned an ID that Gut did not provide
  * `:adapter_error` - the adapter failed for another reason or broke its contract
  """
  @type reason ::
          :timeout
          | :rate_limited
          | :unauthorized
          | :invalid_answer
          | :adapter_error

  @typedoc "A runtime error, including the original failure in `cause`."
  @type t :: %__MODULE__{
          reason: reason(),
          message: String.t(),
          cause: term()
        }
end
