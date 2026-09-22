defmodule Gut.Adapter do
  @moduledoc """
  Defines the contract between Gut and an LLM adapter.

  An adapter receives an encoded subject, a question, and a list of choices.
  Each choice contains an opaque ID and a description. The adapter returns one
  of those IDs. Gut maps the ID back to the original Elixir value.

  Configure an adapter as a module or as a `{module, options}` tuple:

      config :gut, adapter: {Gut.ReqLLM, model: "anthropic:claude-haiku-4-5"}

  Gut calls `c:init/1` and `c:choose/4` in the caller process.
  """

  @typedoc "An opaque choice ID and the description sent to the adapter."
  @type choice :: {id :: String.t(), description :: String.t()}

  @typedoc "An adapter module, with or without adapter-specific options."
  @type spec :: module() | {module(), keyword()}

  @doc """
  Validates the adapter options and returns the state passed to `c:choose/4`.

  Raises `ArgumentError` when the configuration is invalid. This callback must
  not start an unsupervised process.
  """
  @callback init(opts :: keyword()) :: state :: term()

  @doc """
  Chooses one of the supplied opaque IDs.

  Returns a `Gut.Error` when the adapter or its provider cannot make a choice.
  """
  @callback choose(
              subject :: String.t(),
              question :: String.t(),
              choices :: [choice()],
              state :: term()
            ) :: {:ok, String.t()} | {:error, Gut.Error.t()}
end
