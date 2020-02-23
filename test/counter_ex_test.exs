defmodule CounterExTest do
  use ExUnit.Case
  doctest CounterEx

  test "greets the world" do
    assert CounterEx.hello() == :world
  end
end
