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
  def init(_opts), do: raise("Gut.ReqLLM.Jev is not implemented yet")

  @impl true
  def choose(_subject, _question, _choices, _state),
    do: raise("Gut.ReqLLM.Jev is not implemented yet")
end
