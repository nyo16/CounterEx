defmodule CounterExTest do
  use ExUnit.Case, async: true

  setup context do
    {:ok, pid} = CounterEx.Keeper.start_link()
    Map.put(context, :pid, pid)
  end

  doctest CounterEx, import: true
end
