defmodule Gut.TestTest do
  use ExUnit.Case, async: true

  defmodule Router do
    def route(ticket) do
      case Gut.feel(ticket, "Which team?", [:billing, :technical], adapter: Gut.Test) do
        {:ok, :billing} -> :invoice
        {:ok, :technical} -> :repair
      end
    end
  end

  test "stubs application calls independently in concurrent tests" do
    Gut.Test.stub(fn _subject, _question, _choices -> :technical end)

    assert Router.route("ticket") == :repair
    assert Task.async(fn -> Router.route("ticket") end) |> Task.await() == :repair
  end

  test "selects another application path without changing global config" do
    Gut.Test.stub(fn _subject, _question, _choices -> :billing end)

    assert Router.route("ticket") == :invoice
  end

  test "rejects a stub value outside the offered choices" do
    Gut.Test.stub(fn _subject, _question, _choices -> :escalate end)

    assert_raise ArgumentError, ~r/not among the choices/, fn ->
      Router.route("ticket")
    end
  end

  test "does not share a stub with an unrelated process" do
    Gut.Test.stub(fn _subject, _question, _choices -> :technical end)

    parent = self()

    spawn(fn -> send(parent, {:route, Router.route("ticket")}) end)

    assert_receive {:route, :invoice}
  end

  test "selects the first choice by default" do
    assert {:ok, :billing} =
             Gut.feel("ticket", "Which team?", [:billing, :technical], adapter: Gut.Test)
  end

  test "stubs choices from a list, keyword list, or range" do
    Gut.Test.stub(fn _subject, _question, _choices -> :technical end)

    assert {:ok, :technical} =
             Gut.feel("ticket", "Which team?", [:billing, :technical], adapter: Gut.Test)

    assert {:ok, :technical} =
             Gut.feel("ticket", "Which team?", [billing: "Payments", technical: "Product"],
               adapter: Gut.Test
             )

    Gut.Test.stub(fn _subject, _question, _choices -> 4 end)
    assert {:ok, 4} = Gut.feel("ticket", "Score?", 1..5, adapter: Gut.Test)

    Gut.Test.stub(fn _subject, _question, _choices -> 1.0 end)
    assert {:ok, 1.0} = Gut.feel("ticket", "Number?", [1, 1.0], adapter: Gut.Test)
  end

  test "selects unsure only when offered" do
    Gut.Test.stub(fn _subject, _question, _choices -> :unsure end)

    assert {:ok, :unsure} =
             Gut.feel("ticket", "Which team?", [:billing],
               adapter: Gut.Test,
               allow_unsure: true
             )
  end

  test "rejects invalid configuration" do
    assert_raise ArgumentError, ~r/does not accept adapter options/, fn ->
      Gut.feel("ticket", "Which team?", [:billing], adapter: {Gut.Test, index: 1})
    end
  end
end
