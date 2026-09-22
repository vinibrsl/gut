defmodule Gut.ReqLLM do
  @moduledoc """
  Adapts ReqLLM to the `Gut.Adapter` contract.

  This adapter requires the optional `req_llm` dependency. Applications that
  use it must add `req_llm` to their dependencies:

      {:req_llm, "~> 1.24"}

  Adapter options pass through to `ReqLLM.generate_text/3`. This adapter owns
  the structured output option and uses strict validation with a temperature
  of zero unless the adapter options override it.
  """

  @behaviour Gut.Adapter

  @impl true
  def init(_opts), do: raise("Gut.ReqLLM is not implemented yet")

  @impl true
  def choose(_subject, _question, _choices, _state),
    do: raise("Gut.ReqLLM is not implemented yet")
end
