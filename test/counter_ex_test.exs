defmodule CounterExTest do
  use ExUnit.Case

  setup context do
    unless context[:skip_setup] do
      {:ok, _pid} = start_supervised({CounterEx, []})
    end

    :ok
  end

  describe "start_link/1" do
    @tag :skip_setup
    test "starts with default ETS backend" do
      {:ok, pid} = start_supervised({CounterEx, name: :test_ets_backend}, id: :test_start)
      assert Process.alive?(pid)

      {:ok, info} = CounterEx.Keeper.info(:test_ets_backend)
      assert info.type == :ets
    end

    @tag :skip_setup
    test "starts with Atomics backend" do
      {:ok, _pid} =
        start_supervised(
          {CounterEx, name: :test_atomics_backend, backend: CounterEx.Backend.Atomics, backend_opts: [capacity: 100]},
          id: :test_atomics
        )

      {:ok, info} = CounterEx.Keeper.info(:test_atomics_backend)
      assert info.type == :atomics
    end

    @tag :skip_setup
    test "starts with Counters backend" do
      {:ok, _pid} =
        start_supervised(
          {CounterEx, name: :test_counters_backend, backend: CounterEx.Backend.Counters, backend_opts: [capacity: 100]},
          id: :test_counters
        )

      {:ok, info} = CounterEx.Keeper.info(:test_counters_backend)
      assert info.type == :counters
    end
  end

  describe "inc/1-4" do
    test "increments counter in default namespace" do
      assert {:ok, 1} = CounterEx.inc(:my_counter)
      assert {:ok, 2} = CounterEx.inc(:my_counter)
      assert {:ok, 3} = CounterEx.inc(:my_counter)
    end

    test "increments counter by custom step" do
      assert {:ok, 5} = CounterEx.inc(:my_counter, 5)
      assert {:ok, 15} = CounterEx.inc(:my_counter, 10)
    end

    test "uses default value" do
      assert {:ok, 105} = CounterEx.inc(:my_counter, 5, 100)
    end

    test "increments counter in custom namespace" do
      assert {:ok, 1} = CounterEx.inc(:metrics, :requests, 1, 0)
      assert {:ok, 2} = CounterEx.inc(:metrics, :requests, 1, 0)
    end

    test "handles binary keys" do
      assert {:ok, 1} = CounterEx.inc("my_counter")
      assert {:ok, 2} = CounterEx.inc("my_counter")
    end
  end

  describe "get/1-2" do
    test "returns nil for non-existent counter" do
      assert {:ok, nil} = CounterEx.get(:my_counter)
    end

    test "returns counter value" do
      {:ok, _} = CounterEx.inc(:my_counter)
      assert {:ok, 1} = CounterEx.get(:my_counter)
    end

    test "gets counter from custom namespace" do
      {:ok, _} = CounterEx.inc(:metrics, :requests, 1, 0)
      assert {:ok, 1} = CounterEx.get(:metrics, :requests)
    end
  end

  describe "set/2-3" do
    test "sets counter value" do
      assert {:ok, 42} = CounterEx.set(:my_counter, 42)
      assert {:ok, 42} = CounterEx.get(:my_counter)
    end

    test "sets counter in custom namespace" do
      assert {:ok, 100} = CounterEx.set(:metrics, :requests, 100)
      assert {:ok, 100} = CounterEx.get(:metrics, :requests)
    end

    test "overwrites existing value" do
      {:ok, _} = CounterEx.inc(:my_counter)
      {:ok, _} = CounterEx.set(:my_counter, 50)
      assert {:ok, 50} = CounterEx.get(:my_counter)
    end
  end

  describe "reset/1-3" do
    test "resets counter to 0" do
      {:ok, _} = CounterEx.inc(:my_counter, 10)
      {:ok, _} = CounterEx.reset(:my_counter)
      assert {:ok, 0} = CounterEx.get(:my_counter)
    end

    test "resets counter to custom value" do
      {:ok, _} = CounterEx.inc(:my_counter, 10)
      {:ok, _} = CounterEx.reset(:my_counter, 5)
      assert {:ok, 5} = CounterEx.get(:my_counter)
    end

    test "resets counter in custom namespace" do
      {:ok, _} = CounterEx.inc(:metrics, :requests, 10, 0)
      {:ok, _} = CounterEx.reset(:metrics, :requests, 0)
      assert {:ok, 0} = CounterEx.get(:metrics, :requests)
    end
  end

  describe "delete/1-2" do
    test "deletes a counter" do
      {:ok, _} = CounterEx.inc(:my_counter)
      assert :ok = CounterEx.delete(:my_counter)
      assert {:ok, nil} = CounterEx.get(:my_counter)
    end

    test "deletes counter from custom namespace" do
      {:ok, _} = CounterEx.inc(:metrics, :requests, 1, 0)
      assert :ok = CounterEx.delete(:metrics, :requests)
      assert {:ok, nil} = CounterEx.get(:metrics, :requests)
    end
  end

  describe "all/0-1" do
    test "returns all counters in default namespace" do
      {:ok, _} = CounterEx.inc(:counter1)
      {:ok, _} = CounterEx.inc(:counter2, 2)
      {:ok, _} = CounterEx.inc(:counter3, 3)

      assert {:ok, counters} = CounterEx.all()
      assert counters[:counter1] == 1
      assert counters[:counter2] == 2
      assert counters[:counter3] == 3
    end

    test "returns all counters in custom namespace" do
      {:ok, _} = CounterEx.inc(:metrics, :requests, 1, 0)
      {:ok, _} = CounterEx.inc(:metrics, :errors, 1, 0)

      assert {:ok, counters} = CounterEx.all(:metrics)
      assert counters == %{requests: 1, errors: 1}
    end

    test "namespaces are isolated" do
      {:ok, _} = CounterEx.inc(:counter1)
      {:ok, _} = CounterEx.inc(:metrics, :counter1, 1, 0)

      {:ok, default_counters} = CounterEx.all()
      {:ok, metrics_counters} = CounterEx.all(:metrics)

      assert default_counters[:counter1] == 1
      assert metrics_counters[:counter1] == 1
    end
  end

  describe "delete_namespace/1" do
    test "deletes all counters in namespace" do
      {:ok, _} = CounterEx.inc(:metrics, :requests, 1, 0)
      {:ok, _} = CounterEx.inc(:metrics, :errors, 1, 0)

      assert :ok = CounterEx.delete_namespace(:metrics)
      assert {:ok, %{}} = CounterEx.all(:metrics)
    end

    test "doesn't affect other namespaces" do
      {:ok, _} = CounterEx.inc(:counter1)
      {:ok, _} = CounterEx.inc(:metrics, :requests, 1, 0)

      :ok = CounterEx.delete_namespace(:metrics)

      {:ok, default_counters} = CounterEx.all()
      assert default_counters[:counter1] == 1
    end
  end

  describe "compare_and_swap/3-4" do
    test "swaps when value matches" do
      {:ok, _} = CounterEx.set(:my_counter, 10)
      assert {:ok, 20} = CounterEx.compare_and_swap(:my_counter, 10, 20)
      assert {:ok, 20} = CounterEx.get(:my_counter)
    end

    test "fails when value doesn't match" do
      {:ok, _} = CounterEx.set(:my_counter, 10)
      assert {:error, :mismatch, 10} = CounterEx.compare_and_swap(:my_counter, 5, 20)
      assert {:ok, 10} = CounterEx.get(:my_counter)
    end

    test "works in custom namespace" do
      {:ok, _} = CounterEx.set(:metrics, :requests, 10)
      assert {:ok, 20} = CounterEx.compare_and_swap(:metrics, :requests, 10, 20)
      assert {:ok, 20} = CounterEx.get(:metrics, :requests)
    end
  end

  describe "info/0" do
    test "returns backend information" do
      {:ok, info} = CounterEx.info()

      assert info.type in [:ets, :atomics, :counters]
      assert is_atom(info.backend)
      assert is_list(info.namespaces)
      assert is_integer(info.counters_count)
    end
  end

  describe "sweep functionality" do
    test "periodically clears all counters when interval is set" do
      # Start a new instance with sweep
      {:ok, _pid} =
        start_supervised({CounterEx, interval: 100, name: :sweep_test}, id: :sweep_test)

      {:ok, _} = CounterEx.Keeper.increment(:sweep_test, :default, :counter, 1, 0)
      {:ok, 1} = CounterEx.Keeper.get_value(:sweep_test, :default, :counter)

      # Wait for sweep
      Process.sleep(150)

      {:ok, nil} = CounterEx.Keeper.get_value(:sweep_test, :default, :counter)
    end
  end

  describe "backward compatibility" do
    test "start_keeper/0 returns child spec tuple" do
      assert {CounterEx.Keeper, []} = CounterEx.start_keeper()
    end

    test "start_keeper_with_sweep/1 returns child spec tuple" do
      assert {CounterEx.Keeper, [interval: 1000]} = CounterEx.start_keeper_with_sweep(1000)
    end

    test "start_keeper_with_sweep/1 returns error for non-integer" do
      assert {:error, :interval_is_not_integer} = CounterEx.start_keeper_with_sweep("invalid")
    end
  end
end

