defmodule CounterEx.Backend.ETSTest do
  use ExUnit.Case, async: true

  alias CounterEx.Backend.ETS

  setup do
    # Use unique table name per test to avoid conflicts in async tests
    table_name = :"counter_ex_ets_test_#{System.unique_integer([:positive])}"
    {:ok, state} = ETS.init(base_table_name: table_name)
    %{state: state}
  end

  describe "init/1" do
    test "initializes with default options" do
      assert {:ok, state} = ETS.init([])
      assert state.base_name == :counter_ex_ets
      assert is_reference(state.registry)
    end

    test "initializes with custom base name" do
      assert {:ok, state} = ETS.init(base_table_name: :custom)
      assert state.base_name == :custom
    end
  end

  describe "inc/5" do
    test "increments a counter by 1", %{state: state} do
      assert {:ok, 1} = ETS.inc(state, :default, :counter, 1, 0)
      assert {:ok, 2} = ETS.inc(state, :default, :counter, 1, 0)
      assert {:ok, 3} = ETS.inc(state, :default, :counter, 1, 0)
    end

    test "increments a counter by custom step", %{state: state} do
      assert {:ok, 5} = ETS.inc(state, :default, :counter, 5, 0)
      assert {:ok, 15} = ETS.inc(state, :default, :counter, 10, 0)
    end

    test "uses default value for new counter", %{state: state} do
      assert {:ok, 105} = ETS.inc(state, :default, :counter, 5, 100)
    end

    test "increments in different namespaces independently", %{state: state} do
      assert {:ok, 1} = ETS.inc(state, :ns1, :counter, 1, 0)
      assert {:ok, 1} = ETS.inc(state, :ns2, :counter, 1, 0)
      assert {:ok, 2} = ETS.inc(state, :ns1, :counter, 1, 0)
      assert {:ok, 2} = ETS.inc(state, :ns2, :counter, 1, 0)
    end

    test "handles binary keys", %{state: state} do
      assert {:ok, 1} = ETS.inc(state, :default, "my_counter", 1, 0)
      assert {:ok, 2} = ETS.inc(state, :default, "my_counter", 1, 0)
    end
  end

  describe "get/3" do
    test "returns nil for non-existent counter", %{state: state} do
      assert {:ok, nil} = ETS.get(state, :default, :counter)
    end

    test "returns nil for non-existent namespace", %{state: state} do
      assert {:ok, nil} = ETS.get(state, :nonexistent, :counter)
    end

    test "returns counter value", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 1, 0)
      assert {:ok, 1} = ETS.get(state, :default, :counter)
    end

    test "returns correct value after multiple increments", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 5, 0)
      {:ok, _} = ETS.inc(state, :default, :counter, 10, 0)
      assert {:ok, 15} = ETS.get(state, :default, :counter)
    end
  end

  describe "set/4" do
    test "sets counter to specific value", %{state: state} do
      assert {:ok, 42} = ETS.set(state, :default, :counter, 42)
      assert {:ok, 42} = ETS.get(state, :default, :counter)
    end

    test "overwrites existing counter", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 1, 0)
      assert {:ok, 100} = ETS.set(state, :default, :counter, 100)
      assert {:ok, 100} = ETS.get(state, :default, :counter)
    end

    test "works in different namespaces", %{state: state} do
      {:ok, _} = ETS.set(state, :ns1, :counter, 10)
      {:ok, _} = ETS.set(state, :ns2, :counter, 20)

      assert {:ok, 10} = ETS.get(state, :ns1, :counter)
      assert {:ok, 20} = ETS.get(state, :ns2, :counter)
    end
  end

  describe "reset/4" do
    test "resets counter to 0", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 5, 0)
      assert {:ok, 0} = ETS.reset(state, :default, :counter, 0)
      assert {:ok, 0} = ETS.get(state, :default, :counter)
    end

    test "resets counter to custom value", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 5, 0)
      assert {:ok, 10} = ETS.reset(state, :default, :counter, 10)
      assert {:ok, 10} = ETS.get(state, :default, :counter)
    end
  end

  describe "delete/3" do
    test "deletes a counter", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter, 1, 0)
      assert :ok = ETS.delete(state, :default, :counter)
      assert {:ok, nil} = ETS.get(state, :default, :counter)
    end

    test "returns :ok for non-existent counter", %{state: state} do
      assert :ok = ETS.delete(state, :default, :nonexistent)
    end

    test "returns :ok for non-existent namespace", %{state: state} do
      assert :ok = ETS.delete(state, :nonexistent, :counter)
    end
  end

  describe "get_all/2" do
    test "returns empty map for non-existent namespace", %{state: state} do
      assert {:ok, %{}} = ETS.get_all(state, :nonexistent)
    end

    test "returns empty map when namespace has no counters", %{state: state} do
      assert {:ok, %{}} = ETS.get_all(state, :default)
    end

    test "returns all counters in namespace", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = ETS.inc(state, :default, :counter2, 2, 0)
      {:ok, _} = ETS.inc(state, :default, :counter3, 3, 0)

      assert {:ok, counters} = ETS.get_all(state, :default)
      assert counters == %{counter1: 1, counter2: 2, counter3: 3}
    end

    test "returns only counters from specified namespace", %{state: state} do
      {:ok, _} = ETS.inc(state, :ns1, :counter1, 1, 0)
      {:ok, _} = ETS.inc(state, :ns2, :counter2, 2, 0)

      assert {:ok, %{counter1: 1}} = ETS.get_all(state, :ns1)
      assert {:ok, %{counter2: 2}} = ETS.get_all(state, :ns2)
    end
  end

  describe "delete_namespace/2" do
    test "deletes all counters in namespace", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = ETS.inc(state, :default, :counter2, 2, 0)

      assert :ok = ETS.delete_namespace(state, :default)
      assert {:ok, %{}} = ETS.get_all(state, :default)
    end

    test "returns :ok for non-existent namespace", %{state: state} do
      assert :ok = ETS.delete_namespace(state, :nonexistent)
    end

    test "doesn't affect other namespaces", %{state: state} do
      {:ok, _} = ETS.inc(state, :ns1, :counter1, 1, 0)
      {:ok, _} = ETS.inc(state, :ns2, :counter2, 2, 0)

      assert :ok = ETS.delete_namespace(state, :ns1)
      assert {:ok, %{}} = ETS.get_all(state, :ns1)
      assert {:ok, %{counter2: 2}} = ETS.get_all(state, :ns2)
    end
  end

  describe "compare_and_swap/5" do
    test "swaps when value matches", %{state: state} do
      {:ok, _} = ETS.set(state, :default, :counter, 10)
      assert {:ok, 20} = ETS.compare_and_swap(state, :default, :counter, 10, 20)
      assert {:ok, 20} = ETS.get(state, :default, :counter)
    end

    test "fails when value doesn't match", %{state: state} do
      {:ok, _} = ETS.set(state, :default, :counter, 10)
      assert {:error, :mismatch, 10} = ETS.compare_and_swap(state, :default, :counter, 5, 20)
      assert {:ok, 10} = ETS.get(state, :default, :counter)
    end

    test "creates counter with new value when expecting 0 and counter doesn't exist", %{
      state: state
    } do
      assert {:ok, 10} = ETS.compare_and_swap(state, :default, :counter, 0, 10)
      assert {:ok, 10} = ETS.get(state, :default, :counter)
    end

    test "fails when counter doesn't exist and not expecting 0", %{state: state} do
      assert {:error, :mismatch, 0} = ETS.compare_and_swap(state, :default, :counter, 5, 10)
    end
  end

  describe "info/1" do
    test "returns backend information", %{state: state} do
      {:ok, info} = ETS.info(state)

      assert info.type == :ets
      assert info.backend == CounterEx.Backend.ETS
      assert is_atom(info.base_name)
      assert is_list(info.namespaces)
      assert is_integer(info.counters_count)
      assert is_map(info.counters_by_namespace)
    end

    test "reports correct counter count", %{state: state} do
      {:ok, _} = ETS.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = ETS.inc(state, :default, :counter2, 1, 0)
      {:ok, _} = ETS.inc(state, :ns1, :counter3, 1, 0)

      {:ok, info} = ETS.info(state)

      assert info.counters_count == 3
      assert info.counters_by_namespace[:default] == 2
      assert info.counters_by_namespace[:ns1] == 1
    end
  end

  describe "concurrency" do
    test "handles concurrent increments correctly", %{state: state} do
      tasks =
        for _ <- 1..100 do
          Task.async(fn -> ETS.inc(state, :default, :counter, 1, 0) end)
        end

      results = Task.await_many(tasks)

      # All tasks should succeed
      assert Enum.all?(results, fn {:ok, _} -> true end)

      # Final count should be 100
      assert {:ok, 100} = ETS.get(state, :default, :counter)
    end

    test "handles concurrent operations on different keys", %{state: state} do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            ETS.inc(state, :default, :"counter#{rem(i, 10)}", 1, 0)
          end)
        end

      Task.await_many(tasks)

      {:ok, counters} = ETS.get_all(state, :default)

      # Should have 10 different counters
      assert map_size(counters) == 10

      # Total count should be 50
      total = counters |> Map.values() |> Enum.sum()
      assert total == 50
    end
  end
end
