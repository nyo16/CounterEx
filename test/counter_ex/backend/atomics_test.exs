defmodule CounterEx.Backend.AtomicsTest do
  use ExUnit.Case, async: true

  alias CounterEx.Backend.Atomics

  setup do
    {:ok, state} = Atomics.init(capacity: 100)
    %{state: state}
  end

  describe "init/1" do
    test "initializes with default capacity" do
      assert {:ok, state} = Atomics.init([])
      assert state.capacity == 1000
      assert state.signed == true
    end

    test "initializes with custom capacity" do
      assert {:ok, state} = Atomics.init(capacity: 500)
      assert state.capacity == 500
    end

    test "initializes with unsigned option" do
      assert {:ok, state} = Atomics.init(signed: false)
      assert state.signed == false
    end
  end

  describe "inc/5" do
    test "increments a counter by 1", %{state: state} do
      assert {:ok, 1} = Atomics.inc(state, :default, :counter, 1, 0)
      assert {:ok, 2} = Atomics.inc(state, :default, :counter, 1, 0)
      assert {:ok, 3} = Atomics.inc(state, :default, :counter, 1, 0)
    end

    test "increments a counter by custom step", %{state: state} do
      assert {:ok, 5} = Atomics.inc(state, :default, :counter, 5, 0)
      assert {:ok, 15} = Atomics.inc(state, :default, :counter, 10, 0)
    end

    test "uses default value for new counter", %{state: state} do
      assert {:ok, 105} = Atomics.inc(state, :default, :counter, 5, 100)
    end

    test "increments in different namespaces independently", %{state: state} do
      assert {:ok, 1} = Atomics.inc(state, :ns1, :counter, 1, 0)
      assert {:ok, 1} = Atomics.inc(state, :ns2, :counter, 1, 0)
      assert {:ok, 2} = Atomics.inc(state, :ns1, :counter, 1, 0)
      assert {:ok, 2} = Atomics.inc(state, :ns2, :counter, 1, 0)
    end

    test "returns error when capacity is exceeded", %{state: state} do
      # Fill up to capacity (100)
      for i <- 1..100 do
        assert {:ok, _} = Atomics.inc(state, :default, :"counter#{i}", 1, 0)
      end

      # 101st counter should fail
      assert {:error, :capacity_exceeded} =
               Atomics.inc(state, :default, :counter101, 1, 0)
    end

    test "handles binary keys", %{state: state} do
      assert {:ok, 1} = Atomics.inc(state, :default, "my_counter", 1, 0)
      assert {:ok, 2} = Atomics.inc(state, :default, "my_counter", 1, 0)
    end
  end

  describe "get/3" do
    test "returns nil for non-existent counter", %{state: state} do
      assert {:ok, nil} = Atomics.get(state, :default, :counter)
    end

    test "returns nil for non-existent namespace", %{state: state} do
      assert {:ok, nil} = Atomics.get(state, :nonexistent, :counter)
    end

    test "returns counter value", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter, 1, 0)
      assert {:ok, 1} = Atomics.get(state, :default, :counter)
    end

    test "returns correct value after multiple increments", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter, 5, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter, 10, 0)
      assert {:ok, 15} = Atomics.get(state, :default, :counter)
    end
  end

  describe "set/4" do
    test "sets counter to specific value", %{state: state} do
      assert {:ok, 42} = Atomics.set(state, :default, :counter, 42)
      assert {:ok, 42} = Atomics.get(state, :default, :counter)
    end

    test "overwrites existing counter", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter, 1, 0)
      assert {:ok, 100} = Atomics.set(state, :default, :counter, 100)
      assert {:ok, 100} = Atomics.get(state, :default, :counter)
    end

    test "returns error when capacity is exceeded" do
      {:ok, state} = Atomics.init(capacity: 2)

      {:ok, _} = Atomics.set(state, :default, :counter1, 10)
      {:ok, _} = Atomics.set(state, :default, :counter2, 20)

      assert {:error, :capacity_exceeded} = Atomics.set(state, :default, :counter3, 30)
    end
  end

  describe "delete/3" do
    test "deletes a counter and frees the slot", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter, 5, 0)
      assert :ok = Atomics.delete(state, :default, :counter)
      assert {:ok, nil} = Atomics.get(state, :default, :counter)
    end

    test "allows reuse of slot after delete" do
      {:ok, state} = Atomics.init(capacity: 2)

      # Fill capacity
      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter2, 1, 0)

      # Should fail - capacity exceeded
      assert {:error, :capacity_exceeded} = Atomics.inc(state, :default, :counter3, 1, 0)

      # Delete one counter
      :ok = Atomics.delete(state, :default, :counter1)

      # Now we should be able to create a new counter
      assert {:ok, 1} = Atomics.inc(state, :default, :counter3, 1, 0)
    end

    test "returns :ok for non-existent counter", %{state: state} do
      assert :ok = Atomics.delete(state, :default, :nonexistent)
    end
  end

  describe "get_all/2" do
    test "returns empty map for non-existent namespace", %{state: state} do
      assert {:ok, %{}} = Atomics.get_all(state, :nonexistent)
    end

    test "returns all counters in namespace", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter2, 2, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter3, 3, 0)

      assert {:ok, counters} = Atomics.get_all(state, :default)
      assert counters == %{counter1: 1, counter2: 2, counter3: 3}
    end

    test "returns only counters from specified namespace", %{state: state} do
      {:ok, _} = Atomics.inc(state, :ns1, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :ns2, :counter2, 2, 0)

      assert {:ok, %{counter1: 1}} = Atomics.get_all(state, :ns1)
      assert {:ok, %{counter2: 2}} = Atomics.get_all(state, :ns2)
    end
  end

  describe "delete_namespace/2" do
    test "resets all counters in namespace", %{state: state} do
      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter2, 2, 0)

      assert :ok = Atomics.delete_namespace(state, :default)
      assert {:ok, %{}} = Atomics.get_all(state, :default)
    end

    test "allows reuse of namespace capacity after delete_namespace" do
      {:ok, state} = Atomics.init(capacity: 2)

      # Fill capacity
      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter2, 2, 0)

      # Delete namespace
      :ok = Atomics.delete_namespace(state, :default)

      # Should be able to create new counters now
      assert {:ok, 1} = Atomics.inc(state, :default, :counter3, 1, 0)
      assert {:ok, 1} = Atomics.inc(state, :default, :counter4, 1, 0)
    end
  end

  describe "compare_and_swap/5" do
    test "swaps when value matches", %{state: state} do
      {:ok, _} = Atomics.set(state, :default, :counter, 10)
      assert {:ok, 20} = Atomics.compare_and_swap(state, :default, :counter, 10, 20)
      assert {:ok, 20} = Atomics.get(state, :default, :counter)
    end

    test "fails when value doesn't match", %{state: state} do
      {:ok, _} = Atomics.set(state, :default, :counter, 10)

      assert {:error, :mismatch, 10} =
               Atomics.compare_and_swap(state, :default, :counter, 5, 20)

      assert {:ok, 10} = Atomics.get(state, :default, :counter)
    end

    test "returns error when capacity exceeded" do
      {:ok, state} = Atomics.init(capacity: 1)
      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)

      assert {:error, :capacity_exceeded} =
               Atomics.compare_and_swap(state, :default, :counter2, 0, 10)
    end
  end

  describe "info/1" do
    test "returns backend information", %{state: state} do
      {:ok, info} = Atomics.info(state)

      assert info.type == :atomics
      assert info.backend == CounterEx.Backend.Atomics
      assert info.capacity == 100
      assert info.signed == true
      assert is_list(info.namespaces)
      assert is_integer(info.counters_count)
      assert is_float(info.utilization)
    end

    test "reports correct utilization", %{state: state} do
      # Add 50 counters out of 100 capacity
      for i <- 1..50 do
        Atomics.inc(state, :default, :"counter#{i}", 1, 0)
      end

      {:ok, info} = Atomics.info(state)
      assert info.counters_count == 50
      assert info.utilization == 50.0
    end

    test "reports free slots after deletion" do
      {:ok, state} = Atomics.init(capacity: 10)

      {:ok, _} = Atomics.inc(state, :default, :counter1, 1, 0)
      {:ok, _} = Atomics.inc(state, :default, :counter2, 1, 0)
      :ok = Atomics.delete(state, :default, :counter1)

      {:ok, info} = Atomics.info(state)
      assert info.counters_count == 1
      assert info.free_slots_by_namespace[:default] == 1
    end
  end

  describe "concurrency" do
    test "handles concurrent increments correctly", %{state: state} do
      tasks =
        for _ <- 1..100 do
          Task.async(fn -> Atomics.inc(state, :default, :counter, 1, 0) end)
        end

      results = Task.await_many(tasks)

      # All tasks should succeed
      assert Enum.all?(results, fn {:ok, _} -> true end)

      # Final count should be 100
      assert {:ok, 100} = Atomics.get(state, :default, :counter)
    end

    test "handles concurrent operations on different keys", %{state: state} do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Atomics.inc(state, :default, :"counter#{rem(i, 10)}", 1, 0)
          end)
        end

      Task.await_many(tasks)

      {:ok, counters} = Atomics.get_all(state, :default)

      # Should have 10 different counters
      assert map_size(counters) == 10

      # Total count should be 50
      total = counters |> Map.values() |> Enum.sum()
      assert total == 50
    end
  end
end
