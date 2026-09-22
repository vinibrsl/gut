defmodule Gut.ReqLLMTest do
  use ExUnit.Case, async: true

  test "requires a model" do
    assert_raise ArgumentError, ~r/requires a :model option/, fn -> Gut.ReqLLM.init([]) end
  end

  test "maps ReqLLM failures" do
    state = Gut.ReqLLM.init(model: "unknown:model")

    assert {:error, %Gut.Error{reason: :adapter_error, cause: :unknown_provider}} =
             Gut.ReqLLM.choose("subject", "question", [{"0", "yes"}], state)
  end
end
