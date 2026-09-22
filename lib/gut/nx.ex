defmodule Gut.Nx do
  @moduledoc """
  Runs a local choice model with Nx.

  This adapter requires the optional `nx` dependency. Applications that use it
  must add `nx` to their dependencies:

      {:nx, "~> 1.0"}
  """

  @behaviour Gut.Adapter

  @impl true
  def init(_opts), do: raise("Gut.Nx is not implemented yet")

  @impl true
  def choose(_subject, _question, _choices, _state),
    do: raise("Gut.Nx is not implemented yet")
end
