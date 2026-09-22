defmodule Gut.TestTest do
  use ExUnit.Case, async: true

  test "selects the first choice by default" do
    assert {:ok, :billing} =
             Gut.feel("ticket", "Which team?", [:billing, :technical], adapter: Gut.Test)
  end

  test "selects the configured choice index" do
    assert {:ok, :technical} =
             Gut.feel("ticket", "Which team?", [:billing, :technical],
               adapter: {Gut.Test, index: 1}
             )
  end

  test "rejects invalid configuration" do
    assert_raise ArgumentError, ~r/non-negative :index/, fn -> Gut.Test.init(index: -1) end

    assert_raise ArgumentError, ~r/outside the available choices/, fn ->
      Gut.feel("ticket", "Which team?", [:billing], adapter: {Gut.Test, index: 1})
    end
  end
end
