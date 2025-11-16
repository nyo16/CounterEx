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
            registry: nil,
            metadata: nil

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          write_concurrency: boolean(),
          registry: :ets.tid(),
          metadata: :ets.tid()
        }

  ## Public API

  @impl true
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    write_concurrency = Keyword.get(opts, :write_concurrency, true)
    base_name = Keyword.get(opts, :base_name, :counter_ex_counters)

    # Registry stores namespace -> {counters_ref, key_map_tid}
    registry = :ets.new(:"#{base_name}_registry", [:set, :public])

    # Metadata stores {namespace, :next_index} -> integer and {namespace, :free_slots} -> list
    metadata = :ets.new(:"#{base_name}_metadata", [:set, :public])

    state = %__MODULE__{
      capacity: capacity,
      write_concurrency: write_concurrency,
      registry: registry,
      metadata: metadata
    }

    # Initialize default namespace
    ensure_namespace(state, :default)
    {:ok, state}
  end

  @impl true
  def inc(state, namespace, key, step, default) do
    ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, _state} ->
        counters_ref = get_counters_ref(state, namespace)

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
    counters_ref = get_counters_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if counters_ref && key_map do
      case :ets.lookup(key_map, key) do
        [] ->
          {:ok, nil}

        [{^key, index}] ->
          value = :counters.get(counters_ref, index)
          {:ok, value}
      end
    else
      {:ok, nil}
    end
  end

  @impl true
  def set(state, namespace, key, value) do
    ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, _state} ->
        counters_ref = get_counters_ref(state, namespace)
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
    counters_ref = get_counters_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if counters_ref && key_map do
      case :ets.lookup(key_map, key) do
        [] ->
          :ok

        [{^key, index}] ->
          # Reset the counter to 0
          :counters.put(counters_ref, index, 0)

          # Remove from key map
          :ets.delete(key_map, key)

          # Add index to free slots for reuse
          free_slots = get_free_slots(state, namespace)
          set_free_slots(state, namespace, [index | free_slots])

          emit_telemetry(:delete, %{namespace: namespace, key: key}, state)
          :ok
      end
    else
      :ok
    end
  end

  @impl true
  def get_all(state, namespace) do
    counters_ref = get_counters_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if counters_ref && key_map do
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
      {:ok, %{}}
    end
  end

  @impl true
  def delete_namespace(state, namespace) do
    counters_ref = get_counters_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if counters_ref && key_map do
      # Reset all counters in the namespace
      for i <- 1..state.capacity do
        :counters.put(counters_ref, i, 0)
      end

      # Clear the key map
      :ets.delete_all_objects(key_map)

      # Reset state tracking
      set_next_index(state, namespace, 1)
      set_free_slots(state, namespace, [])

      emit_telemetry(:delete_namespace, %{namespace: namespace}, state)
      :ok
    else
      :ok
    end
  end

  @impl true
  def compare_and_swap(state, namespace, key, expected, new_value) do
    ensure_namespace(state, namespace)

    case get_or_allocate_index(state, namespace, key) do
      {:ok, index, _state} ->
        counters_ref = get_counters_ref(state, namespace)

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
    namespaces_and_data = :ets.tab2list(state.registry)

    counters_by_namespace =
      namespaces_and_data
      |> Enum.map(fn {namespace, _counters_ref, key_map} ->
        {namespace, :ets.info(key_map, :size)}
      end)
      |> Enum.into(%{})

    total_counters = counters_by_namespace |> Map.values() |> Enum.sum()
    namespace_count = length(namespaces_and_data)
    utilization = if total_counters > 0 and namespace_count > 0, do: total_counters / (state.capacity * namespace_count), else: 0.0

    free_slots_by_namespace =
      namespaces_and_data
      |> Enum.map(fn {namespace, _counters_ref, _key_map} ->
        slots = get_free_slots(state, namespace)
        {namespace, length(slots)}
      end)
      |> Enum.into(%{})

    info = %{
      type: :counters,
      backend: __MODULE__,
      capacity: state.capacity,
      write_concurrency: state.write_concurrency,
      namespaces: Enum.map(namespaces_and_data, fn {ns, _, _} -> ns end),
      counters_count: total_counters,
      counters_by_namespace: counters_by_namespace,
      utilization: Float.round(utilization * 100, 2),
      free_slots_by_namespace: free_slots_by_namespace
    }

    {:ok, info}
  end

  ## Private Functions

  defp ensure_namespace(%__MODULE__{} = state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, _counters_ref, _key_map}] ->
        state

      [] ->
        # Create new counters array
        counters_ref = :counters.new(state.capacity, [:write_concurrency])

        # Create ETS table for key-to-index mapping
        key_map = :ets.new(:"counters_keys_#{namespace}_#{System.unique_integer([:positive])}", [:set, :public])

        # Store in registry
        :ets.insert(state.registry, {namespace, counters_ref, key_map})

        # Initialize metadata
        :ets.insert(state.metadata, {{namespace, :next_index}, 1})
        :ets.insert(state.metadata, {{namespace, :free_slots}, []})

        state
    end
  end

  defp get_counters_ref(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, counters_ref, _key_map}] -> counters_ref
      [] -> nil
    end
  end

  defp get_key_map(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, _counters_ref, key_map}] -> key_map
      [] -> nil
    end
  end

  defp get_or_allocate_index(state, namespace, key) do
    key_map = get_key_map(state, namespace)

    case :ets.lookup(key_map, key) do
      [{^key, index}] ->
        {:ok, index, state}

      [] ->
        allocate_index(state, namespace, key)
    end
  end

  defp allocate_index(state, namespace, key) do
    key_map = get_key_map(state, namespace)
    free_slots = get_free_slots(state, namespace)

    # Try to reuse a free slot first
    case free_slots do
      [index | rest] ->
        :ets.insert(key_map, {key, index})
        set_free_slots(state, namespace, rest)
        {:ok, index, state}

      [] ->
        # Allocate a new index
        next_index = get_next_index(state, namespace)

        if next_index > state.capacity do
          Logger.warning("Counters capacity exceeded for namespace #{namespace}")
          {:error, :capacity_exceeded}
        else
          :ets.insert(key_map, {key, next_index})
          set_next_index(state, namespace, next_index + 1)
          {:ok, next_index, state}
        end
    end
  end

  defp get_next_index(state, namespace) do
    case :ets.lookup(state.metadata, {namespace, :next_index}) do
      [{{^namespace, :next_index}, value}] -> value
      [] -> 1
    end
  end

  defp set_next_index(state, namespace, value) do
    :ets.insert(state.metadata, {{namespace, :next_index}, value})
  end

  defp get_free_slots(state, namespace) do
    case :ets.lookup(state.metadata, {namespace, :free_slots}) do
      [{{^namespace, :free_slots}, slots}] -> slots
      [] -> []
    end
  end

  defp set_free_slots(state, namespace, slots) do
    :ets.insert(state.metadata, {{namespace, :free_slots}, slots})
  end

  defp emit_telemetry(operation, metadata, _state) do
    :telemetry.execute(
      [:counter_ex, :backend, :counters, operation],
      %{count: 1},
      metadata
    )
  end
end
