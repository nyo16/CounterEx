defmodule CounterEx.Backend.Atomics do
  @moduledoc """
  Atomics-based backend for CounterEx using Erlang's `:atomics` module.

  This backend uses Erlang's `:atomics` for ultra-fast atomic counter operations:
  - **Fixed capacity**: Pre-allocated array of atomic integers
  - **Ultra-fast**: Fastest operations, minimal overhead
  - **No GC pressure**: Atomics live outside the process heap
  - **Key mapping**: Uses ETS to map keys to array indices

  ## Characteristics

  - **Performance**: Highest throughput (~10-20M ops/sec)
  - **Memory**: Fixed at initialization
  - **Limitations**: Fixed number of counters per namespace (default: 1000)

  ## Configuration

  Options:
  - `:capacity` - Max counters per namespace (default: 1000)
  - `:signed` - Use signed integers (default: true)

  ## When to Use

  Use this backend when:
  - You have a bounded, known set of counters
  - You need maximum performance
  - You can pre-allocate capacity
  - Memory predictability is important

  ## Limitations

  - Cannot create more counters than the configured capacity
  - Deleting a counter doesn't free its slot (reusable after explicit delete)
  - Each namespace requires separate atomic array

  ## Example

      # Initialize with capacity for 10,000 counters
      {:ok, state} = CounterEx.Backend.Atomics.init(capacity: 10_000)
      {:ok, 1} = CounterEx.Backend.Atomics.inc(state, :default, :my_counter, 1, 0)
      {:ok, 1} = CounterEx.Backend.Atomics.get(state, :default, :my_counter)

      # Attempting to exceed capacity returns an error
      {:error, :capacity_exceeded} = CounterEx.Backend.Atomics.inc(state, :ns, :counter_10001, 1, 0)
  """

  @behaviour CounterEx.Backend

  require Logger

  @default_capacity 1000

  defstruct capacity: nil,
            signed: true,
            registry: nil,
            metadata: nil

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          signed: boolean(),
          registry: :ets.tid(),
          metadata: :ets.tid()
        }

  ## Public API

  @impl true
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    signed = Keyword.get(opts, :signed, true)
    base_name = Keyword.get(opts, :base_name, :counter_ex_atomics)

    # Registry stores namespace -> {atomics_ref, key_map_tid}
    registry = :ets.new(:"#{base_name}_registry", [:set, :public])

    # Metadata stores {namespace, :next_index} -> integer and {namespace, :free_slots} -> list
    metadata = :ets.new(:"#{base_name}_metadata", [:set, :public])

    state = %__MODULE__{
      capacity: capacity,
      signed: signed,
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
        atomics_ref = get_atomics_ref(state, namespace)

        # Check if this is a new counter (value is 0) and apply default
        current = :atomics.get(atomics_ref, index)

        if current == 0 and default != 0 do
          :atomics.add(atomics_ref, index, default)
        end

        new_value = :atomics.add_get(atomics_ref, index, step)
        emit_telemetry(:inc, %{namespace: namespace, key: key, step: step}, state)
        {:ok, new_value}

      {:error, :capacity_exceeded} = error ->
        error
    end
  end

  @impl true
  def get(state, namespace, key) do
    atomics_ref = get_atomics_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if atomics_ref && key_map do
      case :ets.lookup(key_map, key) do
        [] ->
          {:ok, nil}

        [{^key, index}] ->
          value = :atomics.get(atomics_ref, index)
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
        atomics_ref = get_atomics_ref(state, namespace)
        :atomics.put(atomics_ref, index, value)
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
    atomics_ref = get_atomics_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if atomics_ref && key_map do
      case :ets.lookup(key_map, key) do
        [] ->
          :ok

        [{^key, index}] ->
          # Reset the atomic to 0
          :atomics.put(atomics_ref, index, 0)

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
    atomics_ref = get_atomics_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if atomics_ref && key_map do
      counters =
        key_map
        |> :ets.tab2list()
        |> Enum.map(fn {key, index} ->
          value = :atomics.get(atomics_ref, index)
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
    atomics_ref = get_atomics_ref(state, namespace)
    key_map = get_key_map(state, namespace)

    if atomics_ref && key_map do
      # Reset all atomics in the namespace
      for i <- 1..state.capacity do
        :atomics.put(atomics_ref, i, 0)
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
        atomics_ref = get_atomics_ref(state, namespace)
        current = :atomics.get(atomics_ref, index)

        if current == expected do
          :atomics.put(atomics_ref, index, new_value)
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
      |> Enum.map(fn {namespace, _atomics_ref, key_map} ->
        {namespace, :ets.info(key_map, :size)}
      end)
      |> Enum.into(%{})

    total_counters = counters_by_namespace |> Map.values() |> Enum.sum()
    namespace_count = length(namespaces_and_data)
    utilization = if total_counters > 0 and namespace_count > 0, do: total_counters / (state.capacity * namespace_count), else: 0.0

    free_slots_by_namespace =
      namespaces_and_data
      |> Enum.map(fn {namespace, _atomics_ref, _key_map} ->
        slots = get_free_slots(state, namespace)
        {namespace, length(slots)}
      end)
      |> Enum.into(%{})

    info = %{
      type: :atomics,
      backend: __MODULE__,
      capacity: state.capacity,
      signed: state.signed,
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
      [{^namespace, _atomics_ref, _key_map}] ->
        state

      [] ->
        # Create new atomics array
        atomics_ref = :atomics.new(state.capacity, signed: state.signed)

        # Create ETS table for key-to-index mapping
        key_map = :ets.new(:"atomics_keys_#{namespace}_#{System.unique_integer([:positive])}", [:set, :public])

        # Store in registry
        :ets.insert(state.registry, {namespace, atomics_ref, key_map})

        # Initialize metadata
        :ets.insert(state.metadata, {{namespace, :next_index}, 1})
        :ets.insert(state.metadata, {{namespace, :free_slots}, []})

        state
    end
  end

  defp get_atomics_ref(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, atomics_ref, _key_map}] -> atomics_ref
      [] -> nil
    end
  end

  defp get_key_map(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, _atomics_ref, key_map}] -> key_map
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
          Logger.warning("Atomics capacity exceeded for namespace #{namespace}")
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
      [:counter_ex, :backend, :atomics, operation],
      %{count: 1},
      metadata
    )
  end
end
