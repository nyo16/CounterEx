defmodule CounterEx.Backend.Counters do
  @moduledoc """
  Counters-based backend for CounterEx using Erlang's `:counters` module.

  This backend uses Erlang's `:counters` for write-optimized atomic counter operations:
  - **Fixed capacity**: Pre-allocated array of atomic counters
  - **Write-optimized**: Optimized for heavy concurrent writes
  - **No GC pressure**: Counters live outside the process heap
  - **Key mapping**: Uses ETS to map keys to array indices

  ## Characteristics

  - **Performance**: Optimized for write-heavy workloads
  - **Memory**: Fixed at initialization
  - **Limitations**: Fixed number of counters per namespace (default: 1000)

  ## Configuration

  Options:
  - `:capacity` - Max counters per namespace (default: 1000)
  - `:write_concurrency` - Enable write concurrency optimization (default: true)

  ## When to Use

  Use this backend when:
  - You have write-heavy workloads with many concurrent writers
  - You have a bounded, known set of counters
  - You can pre-allocate capacity
  - You need predictable memory usage

  ## Atomics vs Counters

  - **Atomics**: Better for read-heavy or mixed workloads
  - **Counters**: Better for write-heavy workloads with many concurrent writers

  ## Limitations

  - Cannot create more counters than the configured capacity
  - Deleting a counter doesn't free its slot (reusable after explicit delete)
  - Each namespace requires separate counter array
  - Counters do not support compare-and-swap natively (emulated with get+put)

  ## Example

      # Initialize with capacity for 5,000 counters
      {:ok, state} = CounterEx.Backend.Counters.init(capacity: 5_000)
      {:ok, 1} = CounterEx.Backend.Counters.inc(state, :default, :requests, 1, 0)
      {:ok, 1} = CounterEx.Backend.Counters.get(state, :default, :requests)
  """

  @behaviour CounterEx.Backend

  require Logger

  @default_capacity 1000

  defstruct capacity: nil,
            write_concurrency: true,
            counters: %{},
            key_maps: %{},
            next_index: %{},
            free_slots: %{}

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          write_concurrency: boolean(),
          counters: %{CounterEx.Backend.namespace() => :counters.counters_ref()},
          key_maps: %{CounterEx.Backend.namespace() => :ets.tid()},
          next_index: %{CounterEx.Backend.namespace() => pos_integer()},
          free_slots: %{CounterEx.Backend.namespace() => [pos_integer()]}
        }

  ## Public API

  @impl true
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    write_concurrency = Keyword.get(opts, :write_concurrency, true)

    state = %__MODULE__{
      capacity: capacity,
      write_concurrency: write_concurrency,
      counters: %{},
      key_maps: %{},
      next_index: %{},
      free_slots: %{}
    }

    # Initialize default namespace
    {:ok, ensure_namespace(state, :default)}
  end

  @impl true
  def inc(state, namespace, key, step, default) do
    state = ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, state} ->
        counters_ref = Map.fetch!(state.counters, namespace)

        # Check if this is a new counter (value is 0) and apply default
        current = :counters.get(counters_ref, index)

        if current == 0 and default != 0 do
          :counters.add(counters_ref, index, default)
        end

        :counters.add(counters_ref, index, step)
        new_value = :counters.get(counters_ref, index)

        emit_telemetry(:inc, %{namespace: namespace, key: key, step: step}, state)
        {:ok, new_value}

      {:error, :capacity_exceeded} = error ->
        error
    end
  end

  @impl true
  def get(state, namespace, key) do
    with {:ok, counters_ref} <- Map.fetch(state.counters, namespace),
         {:ok, key_map} <- Map.fetch(state.key_maps, namespace) do
      case :ets.lookup(key_map, key) do
        [] ->
          {:ok, nil}

        [{^key, index}] ->
          value = :counters.get(counters_ref, index)
          {:ok, value}
      end
    else
      :error -> {:ok, nil}
    end
  end

  @impl true
  def set(state, namespace, key, value) do
    state = ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, state} ->
        counters_ref = Map.fetch!(state.counters, namespace)
        :counters.put(counters_ref, index, value)
        emit_telemetry(:set, %{namespace: namespace, key: key, value: value}, state)
        {:ok, value}

      {:error, :capacity_exceeded} = error ->
        error
    end
  end

  @impl true
  def reset(state, namespace, key, initial_value) do
    set(state, namespace, key, initial_value)
  end

  @impl true
  def delete(state, namespace, key) do
    with {:ok, counters_ref} <- Map.fetch(state.counters, namespace),
         {:ok, key_map} <- Map.fetch(state.key_maps, namespace) do
      case :ets.lookup(key_map, key) do
        [] ->
          :ok

        [{^key, index}] ->
          # Reset the counter to 0
          :counters.put(counters_ref, index, 0)

          # Remove from key map
          :ets.delete(key_map, key)

          # Add index to free slots for reuse
          free_slots = Map.get(state.free_slots, namespace, [])
          state = put_in(state.free_slots[namespace], [index | free_slots])

          emit_telemetry(:delete, %{namespace: namespace, key: key}, state)
          :ok
      end
    else
      :error -> :ok
    end
  end

  @impl true
  def get_all(state, namespace) do
    with {:ok, counters_ref} <- Map.fetch(state.counters, namespace),
         {:ok, key_map} <- Map.fetch(state.key_maps, namespace) do
      counters =
        key_map
        |> :ets.tab2list()
        |> Enum.map(fn {key, index} ->
          value = :counters.get(counters_ref, index)
          {key, value}
        end)
        |> Enum.into(%{})

      {:ok, counters}
    else
      :error -> {:ok, %{}}
    end
  end

  @impl true
  def delete_namespace(state, namespace) do
    with {:ok, counters_ref} <- Map.fetch(state.counters, namespace),
         {:ok, key_map} <- Map.fetch(state.key_maps, namespace) do
      # Reset all counters in the namespace
      for i <- 1..state.capacity do
        :counters.put(counters_ref, i, 0)
      end

      # Clear the key map
      :ets.delete_all_objects(key_map)

      # Reset state tracking
      state = put_in(state.next_index[namespace], 1)
      state = put_in(state.free_slots[namespace], [])

      emit_telemetry(:delete_namespace, %{namespace: namespace}, state)
      :ok
    else
      :error -> :ok
    end
  end

  @impl true
  def compare_and_swap(state, namespace, key, expected, new_value) do
    state = ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, state} ->
        counters_ref = Map.fetch!(state.counters, namespace)

        # Note: :counters doesn't have native CAS, so we emulate it
        # This is NOT truly atomic across processes, but close enough for most use cases
        current = :counters.get(counters_ref, index)

        if current == expected do
          :counters.put(counters_ref, index, new_value)
          emit_telemetry(:cas, %{namespace: namespace, key: key, success: true}, state)
          {:ok, new_value}
        else
          emit_telemetry(:cas, %{namespace: namespace, key: key, success: false}, state)
          {:error, :mismatch, current}
        end

      {:error, :capacity_exceeded} = error ->
        error
    end
  end

  @impl true
  def info(state) do
    counters_by_namespace =
      state.key_maps
      |> Enum.map(fn {namespace, key_map} ->
        {namespace, :ets.info(key_map, :size)}
      end)
      |> Enum.into(%{})

    total_counters = counters_by_namespace |> Map.values() |> Enum.sum()

    utilization =
      if total_counters > 0,
        do: total_counters / (state.capacity * map_size(state.counters)),
        else: 0

    info = %{
      type: :counters,
      backend: __MODULE__,
      capacity: state.capacity,
      write_concurrency: state.write_concurrency,
      namespaces: Map.keys(state.counters),
      counters_count: total_counters,
      counters_by_namespace: counters_by_namespace,
      utilization: Float.round(utilization * 100, 2),
      free_slots_by_namespace:
        state.free_slots
        |> Enum.map(fn {ns, slots} -> {ns, length(slots)} end)
        |> Enum.into(%{})
    }

    {:ok, info}
  end

  ## Private Functions

  defp ensure_namespace(%__MODULE__{} = state, namespace) do
    if Map.has_key?(state.counters, namespace) do
      state
    else
      # Create new counters array
      counters_ref = :counters.new(state.capacity, [:write_concurrency])

      # Create ETS table for key-to-index mapping
      key_map = :ets.new(:"counters_keys_#{namespace}", [:set, :public])

      state
      |> put_in([Access.key(:counters), namespace], counters_ref)
      |> put_in([Access.key(:key_maps), namespace], key_map)
      |> put_in([Access.key(:next_index), namespace], 1)
      |> put_in([Access.key(:free_slots), namespace], [])
    end
  end

  defp get_or_allocate_index(state, namespace, key) do
    key_map = Map.fetch!(state.key_maps, namespace)

    case :ets.lookup(key_map, key) do
      [{^key, index}] ->
        {:ok, index, state}

      [] ->
        allocate_index(state, namespace, key)
    end
  end

  defp allocate_index(state, namespace, key) do
    key_map = Map.fetch!(state.key_maps, namespace)
    free_slots = Map.get(state.free_slots, namespace, [])

    # Try to reuse a free slot first
    case free_slots do
      [index | rest] ->
        :ets.insert(key_map, {key, index})
        state = put_in(state.free_slots[namespace], rest)
        {:ok, index, state}

      [] ->
        # Allocate a new index
        next_index = Map.get(state.next_index, namespace, 1)

        if next_index > state.capacity do
          Logger.warning("Counters capacity exceeded for namespace #{namespace}")
          {:error, :capacity_exceeded}
        else
          :ets.insert(key_map, {key, next_index})
          state = put_in(state.next_index[namespace], next_index + 1)
          {:ok, next_index, state}
        end
    end
  end

  defp emit_telemetry(operation, metadata, _state) do
    :telemetry.execute(
      [:counter_ex, :backend, :counters, operation],
      %{count: 1},
      metadata
    )
  end
end
