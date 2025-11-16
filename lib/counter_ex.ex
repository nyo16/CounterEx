defmodule CounterEx do
  @moduledoc """
  High-performance counter library with pluggable backends and namespace support.

  CounterEx provides atomic counter operations with three backend options:
  - **ETS** (default): Dynamic counters, unlimited capacity
  - **Atomics**: Fixed capacity, ultra-fast operations
  - **Counters**: Fixed capacity, write-optimized

  ## Quick Start

      # Start the counter server (default ETS backend)
      {:ok, _pid} = CounterEx.start_link()

      # Increment counters
      {:ok, 1} = CounterEx.inc(:my_counter)
      {:ok, 2} = CounterEx.inc(:my_counter)

      # Get counter value
      {:ok, 2} = CounterEx.get(:my_counter)

      # Use namespaces to organize counters
      {:ok, 1} = CounterEx.inc(:metrics, :http_requests)
      {:ok, 1} = CounterEx.inc(:metrics, :db_queries)

  ## Backend Selection

      # Use Atomics backend for maximum performance
      {:ok, _pid} = CounterEx.start_link(
        backend: CounterEx.Backend.Atomics,
        backend_opts: [capacity: 10_000]
      )

      # Use Counters backend for write-heavy workloads
      {:ok, _pid} = CounterEx.start_link(
        backend: CounterEx.Backend.Counters,
        backend_opts: [capacity: 5_000]
      )

  ## Namespaces

  Counters can be organized into namespaces for logical grouping:

      {:ok, _} = CounterEx.inc(:http, :requests)
      {:ok, _} = CounterEx.inc(:http, :errors)
      {:ok, _} = CounterEx.inc(:db, :queries)

      # Get all counters in a namespace
      {:ok, counters} = CounterEx.all(:http)
      # => %{requests: 1, errors: 1}

  """

  alias CounterEx.Keeper
  alias CounterEx.Backend

  @default_namespace :default

  ## Supervisor Integration

  @doc """
  Returns a child spec for use in supervision trees.

  ## Examples

      children = [
        {CounterEx, backend: CounterEx.Backend.ETS},
        # ... other children
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Start the CounterEx server.

  ## Options

  - `:backend` - Backend module (default: `CounterEx.Backend.ETS`)
  - `:backend_opts` - Options for backend initialization
  - `:interval` - Sweep interval in milliseconds (clears all counters periodically)
  - `:name` - GenServer name (default: `CounterEx.Keeper`)

  ## Examples

      # Start with default ETS backend
      {:ok, pid} = CounterEx.start_link()

      # Start with Atomics backend
      {:ok, pid} = CounterEx.start_link(
        backend: CounterEx.Backend.Atomics,
        backend_opts: [capacity: 10_000]
      )

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Keeper.start_link(opts)
  end

  @doc """
  Returns supervisor child spec for backward compatibility.

  ## Examples

      children = [
        CounterEx.start_keeper(),
        # ... other children
      ]
  """
  @spec start_keeper :: {module(), keyword()}
  def start_keeper, do: {Keeper, []}

  @doc """
  Returns supervisor child spec with sweep interval for backward compatibility.

  ## Examples

      children = [
        CounterEx.start_keeper_with_sweep(60_000),
        # ... other children
      ]
  """
  @spec start_keeper_with_sweep(integer()) ::
          {module(), keyword()} | {:error, :interval_is_not_integer}
  def start_keeper_with_sweep(interval) when is_integer(interval) do
    {Keeper, [interval: interval]}
  end

  def start_keeper_with_sweep(_), do: {:error, :interval_is_not_integer}

  ## Counter Operations

  @doc """
  Increment a counter by the given step (default: 1).

  If the counter doesn't exist, it's initialized with `default` (default: 0) before incrementing.

  ## Examples

      {:ok, 1} = CounterEx.inc(:my_counter)
      {:ok, 2} = CounterEx.inc(:my_counter)
      {:ok, 12} = CounterEx.inc(:my_counter, 10)

      # With namespace
      {:ok, 1} = CounterEx.inc(:metrics, :requests)

      # With default value
      {:ok, 105} = CounterEx.inc(:counter, 5, 100)

  """
  @spec inc(Backend.key(), integer(), integer()) :: {:ok, integer()} | {:error, term()}
  @spec inc(Backend.namespace(), Backend.key(), integer(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def inc(key_or_namespace, step_or_key \\ 1, default_or_step \\ 0, default \\ 0)

  def inc(key, step, default, _default)
      when (is_atom(key) or is_binary(key)) and is_integer(step) and is_integer(default) do
    Keeper.increment(@default_namespace, key, step, default)
  end

  def inc(namespace, key, step, default)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) and
             is_integer(step) and is_integer(default) do
    Keeper.increment(namespace, key, step, default)
  end

  @doc """
  Get the current value of a counter.

  Returns `{:ok, value}` if the counter exists, or `{:ok, nil}` if it doesn't.

  ## Examples

      {:ok, nil} = CounterEx.get(:my_counter)
      {:ok, _} = CounterEx.inc(:my_counter)
      {:ok, 1} = CounterEx.get(:my_counter)

      # With namespace
      {:ok, value} = CounterEx.get(:metrics, :requests)

  """
  @spec get(Backend.key()) :: {:ok, integer() | nil} | {:error, term()}
  @spec get(Backend.namespace(), Backend.key()) :: {:ok, integer() | nil} | {:error, term()}
  def get(key_or_namespace, key \\ nil)

  def get(key, nil) when is_atom(key) or is_binary(key) do
    Keeper.get_value(@default_namespace, key)
  end

  def get(namespace, key)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) do
    Keeper.get_value(namespace, key)
  end

  @doc """
  Set a counter to a specific value.

  ## Examples

      {:ok, 42} = CounterEx.set(:my_counter, 42)
      {:ok, 42} = CounterEx.get(:my_counter)

      # With namespace
      {:ok, 100} = CounterEx.set(:metrics, :requests, 100)

  """
  @spec set(Backend.key(), integer()) :: {:ok, integer()} | {:error, term()}
  @spec set(Backend.namespace(), Backend.key(), integer()) :: {:ok, integer()} | {:error, term()}
  def set(key_or_namespace, value_or_key, value \\ nil)

  def set(key, value, nil) when (is_atom(key) or is_binary(key)) and is_integer(value) do
    Keeper.set(@default_namespace, key, value)
  end

  def set(namespace, key, value)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) and is_integer(value) do
    Keeper.set(namespace, key, value)
  end

  @doc """
  Reset a counter to the initial value (default: 0).

  ## Examples

      {:ok, _} = CounterEx.inc(:my_counter)
      {:ok, 0} = CounterEx.reset(:my_counter)

      # Reset to custom value
      {:ok, 10} = CounterEx.reset(:my_counter, 10)

      # With namespace
      {:ok, 0} = CounterEx.reset(:metrics, :requests)

  """
  @spec reset(Backend.key(), integer()) :: {:ok, integer()} | {:error, term()}
  @spec reset(Backend.namespace(), Backend.key(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def reset(key_or_namespace, value_or_key \\ 0, value \\ 0)

  def reset(key, value, _value) when (is_atom(key) or is_binary(key)) and is_integer(value) do
    Keeper.reset(@default_namespace, key, value)
  end

  def reset(namespace, key, value)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) and is_integer(value) do
    Keeper.reset(namespace, key, value)
  end

  @doc """
  Delete a counter.

  ## Examples

      {:ok, _} = CounterEx.inc(:my_counter)
      :ok = CounterEx.delete(:my_counter)
      {:ok, nil} = CounterEx.get(:my_counter)

      # With namespace
      :ok = CounterEx.delete(:metrics, :requests)

  """
  @spec delete(Backend.key()) :: :ok | {:error, term()}
  @spec delete(Backend.namespace(), Backend.key()) :: :ok | {:error, term()}
  def delete(key_or_namespace, key \\ nil)

  def delete(key, nil) when is_atom(key) or is_binary(key) do
    Keeper.delete(@default_namespace, key)
  end

  def delete(namespace, key)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) do
    Keeper.delete(namespace, key)
  end

  @doc """
  Get all counters in a namespace.

  Returns a map of counter keys to their values.

  ## Examples

      {:ok, _} = CounterEx.inc(:counter1)
      {:ok, _} = CounterEx.inc(:counter2)
      {:ok, counters} = CounterEx.all()
      # => %{counter1: 1, counter2: 1}

      # With specific namespace
      {:ok, counters} = CounterEx.all(:metrics)

  """
  @spec all() :: {:ok, %{Backend.key() => integer()}} | {:error, term()}
  @spec all(Backend.namespace()) :: {:ok, %{Backend.key() => integer()}} | {:error, term()}
  def all(namespace \\ @default_namespace) do
    Keeper.get_all_values(namespace)
  end

  @doc """
  Delete all counters in a namespace.

  ## Examples

      :ok = CounterEx.delete_namespace(:metrics)

  """
  @spec delete_namespace(Backend.namespace()) :: :ok | {:error, term()}
  def delete_namespace(namespace) do
    Keeper.delete_namespace(namespace)
  end

  @doc """
  Compare-and-swap operation.

  Atomically updates the counter to `new_value` only if its current value equals `expected`.

  Returns `{:ok, new_value}` on success, or `{:error, :mismatch, current_value}` if the
  current value doesn't match the expected value.

  ## Examples

      {:ok, 10} = CounterEx.set(:my_counter, 10)

      # CAS succeeds when value matches
      {:ok, 20} = CounterEx.compare_and_swap(:my_counter, 10, 20)

      # CAS fails when value doesn't match
      {:error, :mismatch, 20} = CounterEx.compare_and_swap(:my_counter, 10, 30)

      # With namespace
      {:ok, 5} = CounterEx.compare_and_swap(:metrics, :requests, 0, 5)

  """
  @spec compare_and_swap(Backend.key(), integer(), integer()) ::
          {:ok, integer()} | {:error, :mismatch, integer()} | {:error, term()}
  @spec compare_and_swap(Backend.namespace(), Backend.key(), integer(), integer()) ::
          {:ok, integer()} | {:error, :mismatch, integer()} | {:error, term()}
  def compare_and_swap(key_or_namespace, expected_or_key, new_value_or_expected, new_value \\ nil)

  def compare_and_swap(key, expected, new_value, nil)
      when (is_atom(key) or is_binary(key)) and is_integer(expected) and is_integer(new_value) do
    Keeper.compare_and_swap(@default_namespace, key, expected, new_value)
  end

  def compare_and_swap(namespace, key, expected, new_value)
      when (is_atom(namespace) or is_binary(namespace)) and
             (is_atom(key) or is_binary(key)) and
             is_integer(expected) and is_integer(new_value) do
    Keeper.compare_and_swap(namespace, key, expected, new_value)
  end

  @doc """
  Get information about the backend and counters.

  Returns a map with metadata including:
  - Backend type (`:ets`, `:atomics`, `:counters`)
  - Number of counters
  - Active namespaces
  - Backend-specific information

  ## Examples

      {:ok, info} = CounterEx.info()
      info.type
      # => :ets
      info.counters_count
      # => 42

  """
  @spec info() :: {:ok, map()} | {:error, term()}
  def info do
    Keeper.info()
  end

  ## Benchmarking

  @doc """
  Run benchmarks comparing backend performance.

  ## Examples

      CounterEx.benchmark()
      CounterEx.benchmark(parallel: 4)

  """
  def benchmark(opts \\ []) do
    parallel = Keyword.get(opts, :parallel, 2)

    backends = [
      {:ets, CounterEx.Backend.ETS, []},
      {:atomics, CounterEx.Backend.Atomics, [capacity: 1000]},
      {:counters, CounterEx.Backend.Counters, [capacity: 1000]}
    ]

    Enum.each(backends, fn {name, backend, backend_opts} ->
      IO.puts("\n=== Benchmarking #{name} backend ===\n")

      {:ok, _pid} = CounterEx.start_link(backend: backend, backend_opts: backend_opts)

      Benchee.run(
        %{
          "#{name}: inc" => fn -> CounterEx.inc(:test_key) end,
          "#{name}: get" => fn -> CounterEx.get(:test_key) end,
          "#{name}: set" => fn -> CounterEx.set(:test_key, 42) end
        },
        parallel: parallel,
        time: 2,
        warmup: 1
      )

      Keeper.stop()
      Process.sleep(100)
    end)
  end
end
