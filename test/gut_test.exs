defmodule GutTest do
  use ExUnit.Case
  doctest Gut

  test "greets the world" do
    assert Gut.hello() == :world
  end
end
