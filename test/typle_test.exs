defmodule TypleTest do
  use ExUnit.Case
  doctest Typle

  test "greets the world" do
    assert Typle.hello() == :world
  end
end
