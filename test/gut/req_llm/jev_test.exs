defmodule Gut.ReqLLM.JevTest do
  use ExUnit.Case, async: true

  alias Gut.Error
  alias Gut.ReqLLM.Jev

  test "requires a model" do
    assert_raise ArgumentError, ~r/requires a :model option/, fn -> Jev.init([]) end
  end

  test "maps ReqLLM failures" do
    state = Jev.init(model: "unknown:model")

    assert {:error, %Error{reason: :adapter_error, cause: :unknown_provider}} =
             Jev.choose("subject", "question", [{"0", "yes"}], state)
  end
end
