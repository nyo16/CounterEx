defmodule CounterEx.Backend do
  @moduledoc """
  Behaviour for CounterEx backend implementations.

  Backends provide different storage mechanisms for counters:
  - `CounterEx.Backend.ETS` - ETS-based storage (unlimited counters, dynamic)
  - `CounterEx.Backend.Atomics` - Erlang `:atomics` (fixed-size, ultra-fast)
  - `CounterEx.Backend.Counters` - Erlang `:counters` (fixed-size, write-optimized)

  ## Backend Selection

  Choose your backend based on your use case:

  - **ETS**: Best for dynamic counters where you don't know the number upfront
  - **Atomics**: Best for fixed, bounded counters with very high throughput
  - **Counters**: Best for write-heavy workloads with multiple concurrent writers

  ## Implementing a Backend

  To implement a custom backend, implement all callbacks in this behaviour:

      defmodule MyBackend do
        @behaviour CounterEx.Backend

        @impl true
        def init(opts), do: ...

        # ... implement remaining callbacks
      end

  ## Namespaces

  All operations accept a namespace parameter to logically group counters.
  The default namespace is `:default`.
  """

  @type namespace :: atom() | binary()
  @type key :: atom() | binary()
  @type value :: integer()
  @type opts :: keyword()
  @type state :: term()

  @doc """
  Initialize the backend with the given options.

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.

  ## Options

  Common options across backends:
  - `:name` - Name for the backend instance (atom)

  Backend-specific options are documented in each backend module.
  """
  @callback init(opts) :: {:ok, state} | {:error, term()}

  @doc """
  Increment a counter by the given step.

  If the counter doesn't exist, it is initialized with `default` before incrementing.

  Returns the new value after incrementing.
  """
  @callback inc(state, namespace, key, step :: integer(), default :: integer()) ::
              {:ok, value} | {:error, term()}

  @doc """
  Get the current value of a counter.

  Returns `{:ok, value}` if the counter exists, or `{:ok, nil}` if it doesn't.
  """
  @callback get(state, namespace, key) :: {:ok, value | nil} | {:error, term()}

  @doc """
  Set a counter to a specific value.

  Creates the counter if it doesn't exist.

  Returns `{:ok, value}` with the set value.
  """
  @callback set(state, namespace, key, value) :: {:ok, value} | {:error, term()}

  @doc """
  Reset a counter to the given initial value (default: 0).

  Returns `{:ok, value}` with the reset value.
  """
  @callback reset(state, namespace, key, initial_value :: integer()) ::
              {:ok, value} | {:error, term()}

  @doc """
  Delete a counter.

  Returns `:ok` regardless of whether the counter existed.
  """
  @callback delete(state, namespace, key) :: :ok | {:error, term()}

  @doc """
  Get all counters in a namespace.

  Returns `{:ok, map}` where keys are counter keys and values are their current values.
  """
  @callback get_all(state, namespace) :: {:ok, %{key => value}} | {:error, term()}

  @doc """
  Delete all counters in a namespace.

  Returns `:ok` on success.
  """
  @callback delete_namespace(state, namespace) :: :ok | {:error, term()}

  @doc """
  Compare-and-swap operation.

  Atomically sets the counter to `new_value` only if its current value equals `expected`.

  Returns:
  - `{:ok, new_value}` if the swap succeeded
  - `{:error, :mismatch, current_value}` if the current value doesn't match expected
  - `{:error, reason}` for other errors
  """
  @callback compare_and_swap(state, namespace, key, expected :: integer(), new_value :: integer()) ::
              {:ok, value} | {:error, :mismatch, value} | {:error, term()}

  @doc """
  Get information about the backend.

  Returns a map with metadata about the backend such as:
  - `:type` - Backend type (`:ets`, `:atomics`, `:counters`)
  - `:counters_count` - Number of active counters
  - `:namespaces` - List of active namespaces
  - Backend-specific metadata

  This is useful for debugging and monitoring.
  """
  @callback info(state) :: {:ok, map()} | {:error, term()}
end
